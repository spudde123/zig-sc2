const std = @import("std");
const net = std.net;

const base64 = std.base64;
const ascii = std.ascii;
const math = std.math;
const rand = std.rand;
const time = std.time;
const mem = std.mem;
const fs = std.fs;

const Sha1 = std.crypto.hash.Sha1;

const sc2p = @import("sc2proto.zig");
const proto = @import("protobuf.zig");

const websocket_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const handshake_key_length = 16;
const handshake_key_length_b64 = base64.standard.Encoder.calcSize(handshake_key_length);
const encoded_key_length_b64 = base64.standard.Encoder.calcSize(Sha1.digest_length);

const OpCode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};

pub const ClientError = error{
    BadResponse,
    ErrorsField,
    ReplayBytes,
    ReplayFile,
    ReplayWrite,
};

pub const ComputerSetup = struct {
    difficulty: sc2p.AiDifficulty = .very_hard,
    build: sc2p.AiBuild = .random,
    race: sc2p.Race = .random,
};

pub const BotSetup = struct {
    name: []const u8 = "Bot",
    race: sc2p.Race,
};

/// Sc2 uses websockets for communication
/// with a protobuf 2 format
/// https://github.com/Blizzard/s2client-proto.
/// It doesn't use other frame types specified
/// in the websocket protocol besides binary
/// and it doesn't use masking of the messages
pub const WebSocketClient = struct {
    addr: net.Address,
    socket: net.Stream,
    prng: rand.DefaultPrng,
    perm_allocator: mem.Allocator,
    step_allocator: mem.Allocator,
    req_buffer: []u8,
    storage: []u8,

    /// perm_alloc should not be freed from the outside while client is in use
    /// while the client is in use.
    /// step_alloc is meant to be freed after each game loop
    pub fn init(host: []const u8, port: u16, perm_alloc: mem.Allocator, step_alloc: mem.Allocator) !WebSocketClient {
        const addr = try net.Address.parseIp(host, port);
        const socket = try net.tcpConnectToAddress(addr);

        const seed = @as(u64, @truncate(@as(u128, @bitCast(time.nanoTimestamp()))));
        const req_buffer = try perm_alloc.alloc(u8, 1024 * 1000);
        const storage = try perm_alloc.alloc(u8, 5 * 1024 * 1000);

        return WebSocketClient{
            .addr = addr,
            .socket = socket,
            .prng = std.rand.DefaultPrng.init(seed),
            .perm_allocator = perm_alloc,
            .step_allocator = step_alloc,
            .req_buffer = req_buffer,
            .storage = storage,
        };
    }

    pub fn deinit(self: *WebSocketClient) void {
        self.socket.close();
        self.perm_allocator.free(self.storage);
        self.perm_allocator.free(self.req_buffer);
    }

    pub fn completeHandshake(self: *WebSocketClient, path: []const u8) !bool {
        var raw_key: [handshake_key_length]u8 = undefined;
        var handshake_key: [handshake_key_length_b64]u8 = undefined;

        self.prng.random().bytes(&raw_key);

        _ = base64.standard.Encoder.encode(&handshake_key, &raw_key);

        const request = "GET {s} HTTP/1.1\r\nConnection: Upgrade\r\nUpgrade: Websocket\r\nSec-WebSocket-Key: {s}\r\nSec-WebSocket-Version: 13\r\n\r\n";
        const stream = self.socket.writer();
        try stream.print(request, .{ path, handshake_key });

        var buf: [256]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < 4 or !mem.eql(u8, buf[total_read - 4 .. total_read], "\r\n\r\n")) {
            const n = try self.socket.read(buf[total_read..]);
            total_read += n;
        }

        std.log.debug("{s}\n", .{buf[0..total_read]});

        var split_iter = mem.split(u8, buf[0..], "\r\n");
        if (split_iter.next()) |line| {
            if (!mem.startsWith(u8, line, "HTTP/1.1 101")) {
                return false;
            }
        }

        const string_to_find = "sec-websocket-accept: ";

        var key_ok = false;
        while (split_iter.next()) |line| {
            var line_lowered = try self.step_allocator.alloc(u8, line.len);
            _ = ascii.lowerString(line_lowered, line);
            if (mem.startsWith(u8, line_lowered, string_to_find)) {
                const received_key = line[string_to_find.len..line.len];
                if (checkHandshakeKey(handshake_key[0..handshake_key_length_b64], received_key)) {
                    key_ok = true;
                }

                break;
            }
        }

        return key_ok;
    }

    pub fn createGameVsComputer(
        self: *WebSocketClient,
        bot_setup: BotSetup,
        map_name: []const u8,
        computer: ComputerSetup,
        realtime: bool,
    ) !u32 {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        // Create game
        const bot_proto = sc2p.PlayerSetup{
            .player_type = .participant,
        };
        const computer_proto = sc2p.PlayerSetup{
            .player_type = .computer,
            .race = computer.race,
            .difficulty = computer.difficulty,
            .ai_build = computer.build,
        };

        var setups = [_]sc2p.PlayerSetup{ bot_proto, computer_proto };
        const map = sc2p.LocalMap{
            .map_path = map_name,
        };

        const create_game = sc2p.RequestCreateGame{
            .map = map,
            .player_setup = setups[0..],
            .disable_fog = false,
            .realtime = realtime,
        };

        const create_game_req = sc2p.Request{ .create_game = create_game };
        const create_game_payload = writer.encodeBaseStruct(create_game_req);

        const create_game_res = try self.writeAndWaitForMessage(create_game_payload);
        if (create_game_res.create_game == null or create_game_res.status == null) {
            std.log.err("Did not get create game response\n", .{});
            return ClientError.BadResponse;
        }

        const cg_data = create_game_res.create_game.?;

        if (cg_data.error_code) |code| {
            std.log.err("Create game error: {d}\n", .{@intFromEnum(code)});
            if (cg_data.error_details) |details| {
                std.log.err("{s}\n", .{details});
            }
            return ClientError.BadResponse;
        }

        if (create_game_res.status.? != sc2p.Status.init_game) {
            std.log.err("Wrong status after create game: {d}\n", .{@intFromEnum(create_game_res.status.?)});
            return ClientError.BadResponse;
        }

        // Join game

        const interface = sc2p.InterfaceOptions{
            .raw = true,
            .score = false,
            .show_cloaked = true,
            .raw_affects_selection = false,
            .raw_crop_to_playable_area = false,
            .show_placeholders = true,
            .show_burrowed_shadows = true,
        };

        const join_game = sc2p.RequestJoinGame{
            .race = bot_setup.race,
            .options = interface,
            .server_ports = null,
            .client_ports = null,
            .player_name = bot_setup.name,
        };

        writer.cursor = 0;

        const join_game_req = sc2p.Request{ .join_game = join_game };
        const join_game_payload = writer.encodeBaseStruct(join_game_req);

        var join_game_res = try self.writeAndWaitForMessage(join_game_payload);
        if (join_game_res.join_game == null) {
            std.log.err("Did not get join game response\n", .{});
            return ClientError.BadResponse;
        }

        const jg_data = join_game_res.join_game.?;

        if (jg_data.error_code) |code| {
            std.log.err("Join game error: {d}\n", .{code});
            if (jg_data.error_details) |details| {
                std.log.err("{s}\n", .{details});
            }
            return ClientError.BadResponse;
        }

        return jg_data.player_id.?;
    }

    pub fn createGameVsHuman(
        self: *WebSocketClient,
        map_name: []const u8,
        realtime: bool,
    ) !void {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        // Create game
        const bot_proto = sc2p.PlayerSetup{
            .player_type = .participant,
        };
        const human_proto = sc2p.PlayerSetup{
            .player_type = .participant,
        };

        var setups = [_]sc2p.PlayerSetup{ bot_proto, human_proto };
        const map = sc2p.LocalMap{
            .map_path = map_name,
        };

        const create_game = sc2p.RequestCreateGame{
            .map = map,
            .player_setup = setups[0..],
            .disable_fog = false,
            .realtime = realtime,
        };

        const create_game_req = sc2p.Request{ .create_game = create_game };
        const create_game_payload = writer.encodeBaseStruct(create_game_req);

        const create_game_res = try self.writeAndWaitForMessage(create_game_payload);
        if (create_game_res.create_game == null or create_game_res.status == null) {
            std.log.err("Did not get create game response\n", .{});
            return ClientError.BadResponse;
        }

        const cg_data = create_game_res.create_game.?;

        if (cg_data.error_code) |code| {
            std.log.err("Create game error: {d}\n", .{@intFromEnum(code)});
            if (cg_data.error_details) |details| {
                std.log.err("{s}\n", .{details});
            }
            return ClientError.BadResponse;
        }

        if (create_game_res.status.? != sc2p.Status.init_game) {
            std.log.err("Wrong status after create game: {d}\n", .{@intFromEnum(create_game_res.status.?)});
            return ClientError.BadResponse;
        }
    }

    pub fn joinMultiplayerGame(
        self: *WebSocketClient,
        bot_setup: BotSetup,
        start_port: u16,
    ) !u32 {
        const interface = sc2p.InterfaceOptions{
            .raw = true,
            .score = false,
            .show_cloaked = true,
            .raw_affects_selection = false,
            .raw_crop_to_playable_area = false,
            .show_placeholders = true,
            .show_burrowed_shadows = true,
        };

        const int_port = @as(i32, start_port);

        const server_ports = sc2p.PortSet{
            .game_port = int_port + 1,
            .base_port = int_port + 2,
        };

        const client_ports = sc2p.PortSet{
            .game_port = int_port + 3,
            .base_port = int_port + 4,
        };

        const join_game = sc2p.RequestJoinGame{
            .race = bot_setup.race,
            .options = interface,
            .server_ports = server_ports,
            .client_ports = client_ports,
            .player_name = bot_setup.name,
        };

        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const join_game_req = sc2p.Request{ .join_game = join_game };
        const join_game_payload = writer.encodeBaseStruct(join_game_req);

        const join_game_res = try self.writeAndWaitForMessage(join_game_payload);
        if (join_game_res.join_game == null) {
            std.log.err("Did not get join game response\n", .{});
            return ClientError.BadResponse;
        }

        const jg_data = join_game_res.join_game.?;

        if (jg_data.error_code) |code| {
            std.log.err("Join game error: {d}\n", .{code});
            if (jg_data.error_details) |details| {
                std.log.err("{s}\n", .{details});
            }
            return ClientError.BadResponse;
        }

        return jg_data.player_id.?;
    }

    pub fn getObservation(self: *WebSocketClient, game_loop: ?u32) !sc2p.ResponseObservation {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const obs_req = sc2p.RequestObservation{
            .disable_fog = false,
            .game_loop = game_loop,
        };

        const base_req = sc2p.Request{
            .observation = obs_req,
        };

        var payload = writer.encodeBaseStruct(base_req);
        var res = try self.writeAndWaitForMessage(payload);

        if (res.observation) |obs| {
            return obs;
        }
        return ClientError.BadResponse;
    }

    pub fn getGameInfo(self: *WebSocketClient) !sc2p.ResponseGameInfo {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const request = sc2p.Request{ .game_info = {} };
        const payload = writer.encodeBaseStruct(request);

        const res = try self.writeAndWaitForMessage(payload);

        if (res.game_info) |game_info| {
            return game_info;
        } else {
            return ClientError.BadResponse;
        }
    }

    pub fn getGameData(self: *WebSocketClient) !sc2p.ResponseData {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const data_request = sc2p.RequestData{
            .unit_id = true,
            .upgrade_id = true,
        };
        const request = sc2p.Request{ .game_data = data_request };
        const payload = writer.encodeBaseStruct(request);

        const res = try self.writeAndWaitForMessage(payload);

        if (res.game_data) |game_data| {
            return game_data;
        } else {
            return ClientError.BadResponse;
        }
    }

    pub fn sendActions(self: *WebSocketClient, action_proto: sc2p.RequestAction) !void {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const request = sc2p.Request{ .action = action_proto };
        const payload = writer.encodeBaseStruct(request);

        _ = try self.writeAndWaitForMessage(payload);
    }

    pub fn sendDebugRequest(self: *WebSocketClient, debug_proto: sc2p.RequestDebug) void {
        // This can silently fail without a big problem.
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const request = sc2p.Request{ .debug = debug_proto };
        const payload = writer.encodeBaseStruct(request);

        _ = self.writeAndWaitForMessage(payload) catch return;
    }

    pub fn getAvailableAbilities(self: *WebSocketClient, unit_tags: []u64, ignore_resource_requirements: bool) ?[]sc2p.ResponseQueryAvailableAbilities {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };
        var query_list = self.step_allocator.alloc(sc2p.RequestQueryAvailableAbilities, unit_tags.len) catch return null;

        for (unit_tags, 0..) |tag, i| {
            const abil_req = sc2p.RequestQueryAvailableAbilities{
                .unit_tag = tag,
            };
            query_list[i] = abil_req;
        }
        const query_req = sc2p.RequestQuery{
            .abilities = query_list,
            .ignore_resource_requirements = ignore_resource_requirements,
        };

        const request = sc2p.Request{ .query = query_req };
        const payload = writer.encodeBaseStruct(request);

        const res = self.writeAndWaitForMessage(payload) catch return null;

        if (res.query) |query_proto| {
            return query_proto.abilities;
        }
        return null;
    }

    pub fn sendPlacementQuery(self: *WebSocketClient, query: sc2p.RequestQuery) ?[]sc2p.ResponseQueryBuildingPlacement {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const request = sc2p.Request{ .query = query };
        const payload = writer.encodeBaseStruct(request);

        const res = self.writeAndWaitForMessage(payload) catch return null;

        if (res.query) |query_proto| {
            return query_proto.placements;
        }
        return null;
    }

    pub fn step(self: *WebSocketClient, count: u32) !void {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const step_req = sc2p.RequestStep{
            .count = count,
        };

        const base_req = sc2p.Request{
            .step = step_req,
        };

        const payload = writer.encodeBaseStruct(base_req);
        _ = try self.writeAndWaitForMessage(payload);
    }

    pub fn leave(self: *WebSocketClient) !void {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const request = sc2p.Request{ .leave_game = {} };
        const payload = writer.encodeBaseStruct(request);

        _ = try self.writeAndWaitForMessage(payload);
    }

    pub fn saveReplay(self: *WebSocketClient, replay_path: []const u8) !void {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };

        const request = sc2p.Request{ .save_replay = {} };
        const payload = writer.encodeBaseStruct(request);

        const res = try self.writeAndWaitForMessage(payload);

        if (res.save_replay) |replay_proto| {
            const bytes = replay_proto.bytes orelse return ClientError.ReplayBytes;
            const file = fs.cwd().createFile(replay_path, .{}) catch return ClientError.ReplayFile;
            defer file.close();

            _ = file.writeAll(bytes) catch return ClientError.ReplayWrite;
            return;
        }
        return ClientError.BadResponse;
    }

    pub fn quit(self: *WebSocketClient) !void {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };
        const request = sc2p.Request{ .quit = {} };
        const payload = writer.encodeBaseStruct(request);
        _ = try self.writeAndWaitForMessage(payload);
    }

    pub fn ping(self: *WebSocketClient) sc2p.ResponsePing {
        var writer = proto.ProtoWriter{ .buffer = self.req_buffer };
        const request = sc2p.Request{ .ping = {} };
        const payload = writer.encodeBaseStruct(request);
        const res = self.writeAndWaitForMessage(payload) catch return .{};

        if (res.ping) |ping_res| {
            return ping_res;
        }

        return .{};
    }

    pub fn writeAndWaitForMessage(self: *WebSocketClient, payload: []u8) !sc2p.Response {
        {
            self.storage[0] = @intFromEnum(OpCode.binary);
            self.storage[0] |= 0x80;

            var payload_start: usize = 2;

            if (payload.len <= 125) {
                self.storage[1] = @as(u8, @truncate(payload.len));
            } else if (payload.len <= 65535) {
                self.storage[1] = 126;
                mem.writeIntBig(u16, self.storage[2..4], @as(u16, @truncate(payload.len)));
                payload_start += 2;
            } else {
                self.storage[1] = 127;
                mem.writeIntBig(u64, self.storage[2..10], payload.len);
                payload_start += 8;
            }

            mem.copy(u8, self.storage[payload_start..], payload);

            const stream = self.socket.writer();
            try stream.writeAll(self.storage[0..(payload_start + payload.len)]);
        }

        var cursor: usize = 0;
        var read_length = try self.socket.read(self.storage);
        cursor += read_length;

        while (!self.messageReceived(cursor)) {
            read_length = try self.socket.read(self.storage[cursor..]);
            cursor += read_length;
        }

        const payload_desc = self.storage[1];
        var payload_start: usize = 2;
        var payload_length = @as(u64, payload_desc);

        if (payload_desc == 126) {
            payload_length = mem.readIntBig(u16, self.storage[2..4]);
            payload_start += 2;
        } else if (payload_desc == 127) {
            payload_length = mem.readIntBig(u64, self.storage[2..10]);
            payload_start += 8;
        }

        var reader = proto.ProtoReader{ .bytes = self.storage[payload_start..(payload_start + payload_length)] };
        const res = try reader.decodeStruct(reader.bytes.len, sc2p.Response, self.step_allocator);

        if (res.errors) |errors| {
            for (errors) |error_string| {
                std.log.err("Message error: {s}\n", .{error_string});
            }
            return ClientError.ErrorsField;
        }

        return res;
    }

    fn messageReceived(self: *WebSocketClient, cursor: usize) bool {
        if (cursor < 2) return false;
        const payload_desc = self.storage[1];
        var payload_start: usize = 2;
        var payload_length = @as(u64, payload_desc);

        if (payload_desc == 126) {
            if (cursor < 4) return false;
            payload_length = mem.readIntBig(u16, self.storage[2..4]);
            payload_start += 2;
        } else if (payload_desc == 127) {
            if (cursor < 10) return false;
            payload_length = mem.readIntBig(u64, self.storage[2..10]);
            payload_start += 8;
        }

        return cursor >= payload_start + payload_length;
    }
};

fn checkHandshakeKey(original: []const u8, received: []const u8) bool {
    var hash = Sha1.init(.{});
    hash.update(original);
    hash.update(websocket_guid);

    var hashed_key: [Sha1.digest_length]u8 = undefined;
    hash.final(&hashed_key);

    var encoded: [encoded_key_length_b64]u8 = undefined;
    _ = base64.standard.Encoder.encode(encoded[0..], hashed_key[0..]);

    return mem.eql(u8, encoded[0..], received);
}
