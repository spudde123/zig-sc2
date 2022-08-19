const std = @import("std");
const net = std.net;

const base64 = std.base64;
const ascii = std.ascii;
const math = std.math;
const rand = std.rand;
const time = std.time;
const mem = std.mem;

const Sha1 = std.crypto.hash.Sha1;

const sc2p = @import("sc2proto.zig");
const proto = @import("protobuf.zig");

const websocket_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const handshake_key_length = 16;
const handshake_key_length_b64 = base64.standard.Encoder.calcSize(handshake_key_length);
const encoded_key_length_b64 = base64.standard.Encoder.calcSize(Sha1.digest_length);

pub const OpCode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};

pub const SocketInitError = error {
    ParseAddress,
    TCPConnect,
};

pub const Ping = struct {
    game_version: []const u8 = "",
    data_version: []const u8 = "",
    data_build: u32 = 0,
    base_build: u32 = 0,
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

pub const GameJoin = struct {
    success: bool = false,
    player_id: u32 = 0,
};

pub const WebSocketClient = struct {

    addr: net.Address,
    socket: net.Stream,
    prng: rand.Random,
    perm_allocator: mem.Allocator,
    step_allocator: mem.Allocator,
    req_buffer: []u8,
    storage: []u8,
    storage_cursor: usize,

    /// perm_alloc should not be freed from the outside
    /// while the client is in use.
    /// step_alloc is meant to be freed after each game loop
    pub fn init(host: []const u8, port: u16, perm_alloc: mem.Allocator, step_alloc: mem.Allocator) !WebSocketClient {

        const addr = try net.Address.parseIp(host, port);
        const socket = try net.tcpConnectToAddress(addr);

        const seed = @truncate(u64, @bitCast(u128, time.nanoTimestamp()));
        const prng = std.rand.DefaultPrng.init(seed).random();
        var req_buffer = try perm_alloc.alloc(u8, 1024*1000);
        var storage = try perm_alloc.alloc(u8, 5*1024*1000);

        return WebSocketClient{
            .addr = addr,
            .socket = socket,
            .prng = prng,
            .perm_allocator = perm_alloc,
            .step_allocator = step_alloc,
            .req_buffer = req_buffer,
            .storage = storage,
            .storage_cursor = 0,
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
        
        self.prng.bytes(&raw_key);

        _ = base64.standard.Encoder.encode(&handshake_key, &raw_key);

        const request = "GET {s} HTTP/1.1\r\nConnection: Upgrade\r\nUpgrade: Websocket\r\nSec-WebSocket-Key: {s}\r\nSec-WebSocket-Version: 13\r\n\r\n";
        const stream = self.socket.writer();
        try stream.print(request, .{path, handshake_key});

        var buf: [256]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < 4 or !mem.eql(u8, buf[total_read - 4 .. total_read], "\r\n\r\n")) {
            const n = try self.socket.read(buf[total_read..]);
            total_read += n;
        }
        
        std.debug.print("{s}\n", .{buf[0..total_read]});

        var split_iter = mem.split(u8, buf[0..], "\r\n");
        if (split_iter.next()) |line| {
            if (!mem.startsWith(u8, line, "HTTP/1.1 101")) {
                return false;
            }
        }

        const string_to_find = "Sec-WebSocket-Accept: ";

        var key_ok = false;
        while (split_iter.next()) |line| {

            if (mem.startsWith(u8, line, string_to_find)) {
                const received_key = line[string_to_find.len..line.len];
                if (checkHandshakeKey(handshake_key[0..handshake_key_length_b64], received_key)) {
                    key_ok = true;
                }

                break;
            }
        }

        return key_ok;
    }

    pub fn writeEmptyControlMessage(self: *WebSocketClient, op: OpCode) !void {
        var bytes: [6]u8 = undefined;

        bytes[0] = @enumToInt(op);
        // Set this to be the final message
        bytes[0] |= 0x80;
        var mask: [4]u8 = undefined;
        self.prng.bytes(&mask);

        // Payload length to 0 and mask bit to 1
        bytes[1] = 0;
        bytes[1] |= 0x80;

        mem.copy(u8, bytes[2..], mask[0..]);

        const stream = self.socket.writer();
        try stream.writeAll(bytes[0..]);
    }

    pub fn writeMessageWithBinaryPayload(self: *WebSocketClient, payload: []u8, mask_payload: bool) !void {
        const max_len = 6 + payload.len + 8;
        var bytes = try self.step_allocator.alloc(u8, max_len);
        bytes[0] = @enumToInt(OpCode.binary);
        bytes[0] |= 0x80;

        var payload_start: usize = undefined;

        var mask_start: usize = 2;
        if (payload.len <= 125) {
            bytes[1] = @truncate(u8, payload.len);
        } else if (payload.len <= 65535) {
            bytes[1] = 126;
            mem.writeIntBig(u16, bytes[2..4], @truncate(u16, payload.len));
            mask_start += 2;
        } else {
            bytes[1] = 127;
            mem.writeIntBig(u64, bytes[2..10], payload.len);
            mask_start += 8;
        }

        if (mask_payload) {
            var mask: [4]u8 = undefined;
            self.prng.bytes(&mask);
            // Mask bit to 1
            bytes[1] |= 0x80;

            mem.copy(u8, bytes[mask_start..(mask_start + 4)], mask[0..]);
            payload_start = mask_start + 4;

            var insert_index = payload_start;
            for (payload) |char, index| {
                bytes[insert_index] = char ^ mask[index % 4];
                insert_index += 1;
            }
        } else {
            payload_start = mask_start;
            mem.copy(u8, bytes[payload_start..], payload);
        }

        const stream = self.socket.writer();
        try stream.writeAll(bytes[0..(payload_start + payload.len)]);
    }

    // According to the spec pong should include the same payload as the ping
    // Not sure what to do in terms of whether it should be masked or not?
    pub fn writePong(self: *WebSocketClient) !void {
        try self.writeEmptyControlMessage(OpCode.pong);
    }

    pub fn writePing(self: *WebSocketClient) !void {
        try self.writeEmptyControlMessage(OpCode.ping);
    }

    pub fn writeCloseFrame(self: *WebSocketClient) !void {
        try self.writeEmptyControlMessage(OpCode.close);
    }

    pub fn createGameVsComputer(
        self: *WebSocketClient,
        bot_setup: BotSetup,
        map_name: []const u8,
        computer: ComputerSetup,
        realtime: bool
    ) GameJoin {
        var writer = proto.ProtoWriter{.buffer = self.req_buffer};
        
        // Create game
        const bot_proto = sc2p.PlayerSetup{
            .player_type = .{.data = .participant},
        };
        const computer_proto = sc2p.PlayerSetup{
            .player_type = .{.data = .computer},
            .race = .{.data = computer.race},
            .difficulty = .{.data = computer.difficulty},
            .ai_build = .{.data = computer.build},
        };

        var setups = [_]sc2p.PlayerSetup{bot_proto, computer_proto};
        const map = sc2p.LocalMap{
            .map_path = .{.data = map_name},
        };

        const create_game = sc2p.RequestCreateGame{
            .map = .{.data = map},
            .player_setup = .{.data = setups[0..]},
            .disable_fog = .{.data = false},
            .realtime = .{.data = realtime},
        };

        const create_game_req = sc2p.Request{.create_game = .{.data = create_game}};
        const create_game_payload = writer.encodeBaseStruct(create_game_req);
        
        var create_game_res = self.writeAndWaitForMessage(create_game_payload) catch return .{};
        if (create_game_res.create_game.data == null or create_game_res.status.data == null) {
            std.debug.print("Did not get create game response\n", .{});
            return .{};
        }

        var cg_data = create_game_res.create_game.data.?;

        if (cg_data.error_code.data) |code| {
            std.debug.print("Create game error: {d}\n", .{code});
            if (cg_data.error_details.data) |details| {
                std.debug.print("{s}\n", .{details});
            }
            return .{};
        }

        if (create_game_res.status.data.? != sc2p.Status.init_game) {
            std.debug.print(
                "Wrong status after create game: {d}\n",
                .{create_game_res.status.data.?}
            );
            return .{};
        }

        // Join game

        const interface = sc2p.InterfaceOptions{
            .raw = .{.data = true},
            .score = .{.data = true},
            .show_cloaked = .{.data = true},
            .raw_affects_selection = .{.data = false},
            .raw_crop_to_playable_area = .{.data = false},
            .show_placeholders = .{.data = true},
            .show_burrowed_shadows = .{.data = true},
        };
        
        const join_game = sc2p.RequestJoinGame{
            .race = .{.data = bot_setup.race},
            .options = .{.data = interface},
            .server_ports = .{.data = null},
            .client_ports = .{.data = null},
            .player_name = .{.data = bot_setup.name},
        };

        writer.cursor = 0;

        const join_game_req = sc2p.Request{.join_game = .{.data = join_game}};
        const join_game_payload = writer.encodeBaseStruct(join_game_req);

        var join_game_res = self.writeAndWaitForMessage(join_game_payload) catch return .{};
        if (join_game_res.join_game.data == null) {
            std.debug.print("Did not get join game response\n", .{});
            return .{};
        }

        var jg_data = join_game_res.join_game.data.?;

        if (jg_data.error_code.data) |code| {
            std.debug.print("Join game error: {d}\n", .{code});
            if (jg_data.error_details.data) |details| {
                std.debug.print("{s}\n", .{details});
            }
            return .{};
        }

        return GameJoin{.success = true, .player_id = jg_data.player_id.data.?};

    }

    pub fn createGameVsHuman(self: *WebSocketClient) bool {
        _ = self;
        return false;
    }

    pub fn joinLadderGame(self: *WebSocketClient) bool {
        _ = self;
        return false;
    }

    pub fn getObservation(self: *WebSocketClient) sc2p.ResponseObservation {
        var writer = proto.ProtoWriter{.buffer = self.req_buffer};

        const obs_req = sc2p.RequestObservation{
            .disable_fog = .{.data = false},
        };

        const base_req = sc2p.Request{
            .observation = .{.data = obs_req},
        };

        var payload = writer.encodeBaseStruct(base_req);
        var res = self.writeAndWaitForMessage(payload) catch return .{};

        if (res.observation.data) |obs| {
            return obs;
        }
        return .{};
    }

    pub fn getGameInfo(self: *WebSocketClient) sc2p.ResponseGameInfo {
        var writer = proto.ProtoWriter{.buffer = self.req_buffer};

        var request = sc2p.Request{.game_info = .{.data = {}}};
        var payload = writer.encodeBaseStruct(request);

        var res = self.writeAndWaitForMessage(payload) catch return .{};

        return res;
    }

    pub fn step(self: *WebSocketClient, count: u32) bool {
        var writer = proto.ProtoWriter{.buffer = self.req_buffer};

        const step_req = sc2p.RequestStep{
            .count = .{.data = count},
        };

        const base_req = sc2p.Request{
            .step = .{.data = step_req},
        };

        var payload = writer.encodeBaseStruct(base_req);
        _ = self.writeAndWaitForMessage(payload) catch false;

        return true;
    }

    pub fn leave(self: *WebSocketClient) bool {
        var writer = proto.ProtoWriter{.buffer = self.req_buffer};

        var request = sc2p.Request{.leave_game = .{.data = {}}};
        var payload = writer.encodeBaseStruct(request);

        _ = self.writeAndWaitForMessage(payload) catch false;

        return true;
    }

    pub fn quit(self: *WebSocketClient) bool {
        var quit_req = sc2p.generateQuitRequest(self.req_buffer);
        var res = self.writeAndWaitForMessage(quit_req) catch return false;
        if (res.quit.data) |_| {
            return true;
        }

        return false;
    }

    pub fn ping(self: *WebSocketClient) Ping {
        var ping_req = sc2p.generatePingRequest(self.req_buffer);
        var res = self.writeAndWaitForMessage(ping_req) catch return Ping{};

        if (res.ping.data) |ping_res| {
            return Ping{
                .game_version = ping_res.game_version.data.?,
                .data_version = ping_res.data_version.data.?,
                .data_build = ping_res.data_build.data.?,
                .base_build = ping_res.data_build.data.?,
            };
        }

        return Ping{};
    }

    pub fn writeAndWaitForMessage(self: *WebSocketClient, payload: []u8) !sc2p.Response {
        self.storage_cursor = 0;

        {
            const max_len = 2 + payload.len + 8;
            var bytes = try self.step_allocator.alloc(u8, max_len);
            bytes[0] = @enumToInt(OpCode.binary);
            bytes[0] |= 0x80;

            var payload_start: usize = 2;

            if (payload.len <= 125) {
                bytes[1] = @truncate(u8, payload.len);
            } else if (payload.len <= 65535) {
                bytes[1] = 126;
                mem.writeIntBig(u16, bytes[2..4], @truncate(u16, payload.len));
                payload_start += 2;
            } else {
                bytes[1] = 127;
                mem.writeIntBig(u64, bytes[2..10], payload.len);
                payload_start += 8;
            }

            mem.copy(u8, bytes[payload_start..], payload);

            const stream = self.socket.writer();
            try stream.writeAll(bytes[0..(payload_start + payload.len)]);
        }

        var res: sc2p.Response = undefined;

        while (true) {
            var read_length = try self.socket.read(self.storage);
            if (read_length == 0) continue;

            var start: usize = 0;
            var found_ws_start = false;
            for (self.storage[0..read_length]) |byte, i| {
                if (byte == 130) {
                    start = i;
                    found_ws_start = true;
                    break;
                }
            }

            if (!found_ws_start) continue;

            self.storage_cursor += read_length - start;
            
            while (!self.messageReceived()) {
                read_length = try self.socket.read(self.storage[self.storage_cursor..]);
                self.storage_cursor += read_length - start;
            }

            var payload_desc = self.storage[1];
            var payload_start: usize = 2;
            var payload_length = @as(u64, payload_desc);

            if (payload_desc == 126) {
                payload_length = mem.readIntBig(u16, self.storage[2..4]);
                payload_start += 2;
            } else if (payload_desc == 127) {
                payload_length = mem.readIntBig(u64, self.storage[2..10]);
                payload_start += 8;
            }

            res = try sc2p.decodeResponse(self.storage[payload_start .. (payload_start + payload_length)], self.step_allocator);
            break;
        }

        if (res.errors.data) |errors| {
            for (errors) |error_string| {
                std.debug.print("Message error: {s}\n", .{error_string});
            }
        }

        if (res.status.data) |status| {
            std.debug.print("Status: {d}\n", .{@enumToInt(status)});
        }

        return res;
    }

    fn messageReceived(self: *WebSocketClient) bool {
        if (self.storage_cursor < 2) return false;
        var payload_desc = self.storage[1];
        var payload_start: usize = 2;
        var payload_length = @as(u64, payload_desc);

        if (payload_desc == 126) {
            if (self.storage_cursor < 4) return false;
            payload_length = mem.readIntBig(u16, self.storage[2..4]);
            payload_start += 2;
        } else if (payload_desc == 127) {
            if (self.storage_cursor < 10) return false;
            payload_length = mem.readIntBig(u64, self.storage[2..10]);
            payload_start += 8;
        }

        return self.storage_cursor >= payload_start + payload_length;
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
