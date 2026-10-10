const std = @import("std");
const net = std.Io.net;
const base64 = std.base64;
const ascii = std.ascii;
const math = std.math;
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

const default_interface_options = sc2p.InterfaceOptions{
    .raw = true,
    .score = false,
    .show_cloaked = true,
    .raw_affects_selection = false,
    .raw_crop_to_playable_area = false,
    .show_placeholders = true,
    .show_burrowed_shadows = true,
};

fn RequestPayload(comptime field: []const u8) type {
    return @typeInfo(@FieldType(sc2p.Request, field)).optional.child;
}

fn ResponsePayload(comptime field: []const u8) type {
    return @typeInfo(@FieldType(sc2p.Response, field)).optional.child;
}

/// Sc2 uses websockets for communication
/// with a protobuf 2 format
/// https://github.com/Blizzard/s2client-proto.
/// Only uses the binary messagetype of the websocket
/// protocol
pub const WebSocketClient = struct {
    io: std.Io,
    addr: net.IpAddress,
    socket: net.Stream,
    step_allocator: mem.Allocator,
    status: sc2p.Status = .default,

    /// step_alloc is meant to be freed after each game loop
    pub fn init(io: std.Io, host: []const u8, port: u16, step_alloc: mem.Allocator) !WebSocketClient {
        const addr = try net.IpAddress.parse(host, port);
        const socket = try addr.connect(io, .{
            .mode = .stream,
            .protocol = .tcp,
        });

        return WebSocketClient{
            .io = io,
            .addr = addr,
            .socket = socket,
            .step_allocator = step_alloc,
        };
    }

    pub fn deinit(self: *WebSocketClient) void {
        self.socket.close(self.io);
    }

    pub fn completeHandshake(self: *WebSocketClient, path: []const u8) !void {
        var raw_key: [handshake_key_length]u8 = undefined;
        var handshake_key: [handshake_key_length_b64]u8 = undefined;

        self.io.random(&raw_key);

        _ = base64.standard.Encoder.encode(&handshake_key, &raw_key);

        const request = "GET {s} HTTP/1.1\r\nConnection: Upgrade\r\nUpgrade: Websocket\r\nSec-WebSocket-Key: {s}\r\nSec-WebSocket-Version: 13\r\n\r\n";
        var stream_writer = self.socket.writer(self.io, &.{});
        try stream_writer.interface.print(request, .{ path, handshake_key });

        var buf: [256]u8 = undefined;
        var total_read: usize = 0;
        var stream_reader = self.socket.reader(self.io, &.{});
        while (total_read < buf.len) {
            var bufs = [_][]u8{buf[total_read..]};
            total_read += try stream_reader.interface.readVec(&bufs);
            if (total_read >= 4 and mem.eql(u8, buf[total_read - 4 .. total_read], "\r\n\r\n")) break;
        }

        if (total_read >= buf.len) {
            return error.ResponseTooLarge;
        }
        std.log.debug("{s}", .{buf[0..total_read]});

        var split_iter = mem.tokenizeSequence(u8, buf[0..total_read], "\r\n");
        if (split_iter.next()) |line| {
            if (!mem.startsWith(u8, line, "HTTP/1.1 101")) {
                return error.ProtocolError;
            }
        }

        const string_to_find = "sec-websocket-accept: ";

        while (split_iter.next()) |line| {
            if (ascii.startsWithIgnoreCase(line, string_to_find)) {
                const received_key = line[string_to_find.len..];
                if (checkHandshakeKey(handshake_key[0..handshake_key_length_b64], received_key)) {
                    return;
                }
                break;
            }
        }

        return error.HandshakeFailed;
    }

    pub fn createGameVsComputerAndJoin(
        self: *WebSocketClient,
        bot_setup: BotSetup,
        map_name: []const u8,
        computer: ComputerSetup,
        realtime: bool,
    ) !u32 {
        var setups = [_]sc2p.PlayerSetup{
            .{ .player_type = .participant },
            .{
                .player_type = .computer,
                .race = computer.race,
                .difficulty = computer.difficulty,
                .ai_build = computer.build,
            },
        };
        try self.createGame(&setups, map_name, realtime);
        return self.joinGame(bot_setup, null);
    }

    pub fn createGameVsHuman(
        self: *WebSocketClient,
        map_name: []const u8,
        realtime: bool,
    ) !void {
        var setups = [_]sc2p.PlayerSetup{
            .{ .player_type = .participant },
            .{ .player_type = .participant },
        };
        try self.createGame(&setups, map_name, realtime);
    }

    pub fn joinMultiplayerGame(
        self: *WebSocketClient,
        bot_setup: BotSetup,
        start_port: u16,
    ) !u32 {
        const int_port = @as(i32, start_port);
        return self.joinGame(bot_setup, .{
            .server = .{ .game_port = int_port + 1, .base_port = int_port + 2 },
            .client = .{ .game_port = int_port + 3, .base_port = int_port + 4 },
        });
    }

    fn createGame(
        self: *WebSocketClient,
        setups: []sc2p.PlayerSetup,
        map_name: []const u8,
        realtime: bool,
    ) !void {
        _ = try self.call("create_game", .{
            .map = .{ .map_path = map_name },
            .player_setup = setups,
            .disable_fog = false,
            .realtime = realtime,
        });
        try self.expectStatus(.init_game);
    }

    const GamePorts = struct {
        server: sc2p.PortSet,
        client: sc2p.PortSet,
    };

    fn joinGame(self: *WebSocketClient, bot_setup: BotSetup, ports: ?GamePorts) !u32 {
        const jg_data = try self.call("join_game", .{
            .race = bot_setup.race,
            .options = default_interface_options,
            .server_ports = if (ports) |p| p.server else null,
            .client_ports = if (ports) |p| p.client else null,
            .player_name = bot_setup.name,
        });
        return jg_data.player_id orelse ClientError.BadResponse;
    }

    /// Fetches metadata about a replay, including which
    /// players are playing in it.
    /// The path should be absolute, otherwise sc2 resolves
    /// it relative to its own replay folder.
    /// Note: The response is allocated with the step allocator,
    /// so it is only valid until the next step arena reset.
    pub fn getReplayInfo(self: *WebSocketClient, replay_path: []const u8) !sc2p.ResponseReplayInfo {
        return self.call("replay_info", .{
            .replay_path = replay_path,
            .download_data = false,
        });
    }

    /// Starts watching a replay from the given path.
    /// The path should be absolute, otherwise sc2 resolves
    /// it relative to its own replay folder.
    pub fn startReplay(
        self: *WebSocketClient,
        replay_path: []const u8,
        observed_player_id: u32,
        disable_fog: bool,
        realtime: bool,
    ) !void {
        _ = try self.call("start_replay", .{
            .replay_path = replay_path,
            .observed_player_id = @as(i32, @intCast(observed_player_id)),
            .options = default_interface_options,
            .disable_fog = disable_fog,
            .realtime = realtime,
        });
        try self.expectStatus(.in_replay);
    }

    pub fn getObservation(self: *WebSocketClient, game_loop: ?u32) !sc2p.ResponseObservation {
        return self.call("observation", .{
            .disable_fog = false,
            .game_loop = game_loop,
        });
    }

    pub fn getGameInfo(self: *WebSocketClient) !sc2p.ResponseGameInfo {
        return self.call("game_info", {});
    }

    pub fn getGameData(self: *WebSocketClient) !sc2p.ResponseData {
        return self.call("game_data", .{
            .unit_id = true,
            .upgrade_id = true,
        });
    }

    pub fn sendActions(self: *WebSocketClient, action_proto: sc2p.RequestAction) !void {
        _ = try self.send("action", action_proto);
    }

    pub fn sendDebugRequest(self: *WebSocketClient, debug_proto: sc2p.RequestDebug) !void {
        // This can silently fail without a big problem.
        _ = try self.send("debug", debug_proto);
    }

    pub fn getAvailableAbilities(self: *WebSocketClient, unit_tags: []u64, ignore_resource_requirements: bool) ?[]sc2p.ResponseQueryAvailableAbilities {
        const query_list = self.step_allocator.alloc(sc2p.RequestQueryAvailableAbilities, unit_tags.len) catch return null;
        for (unit_tags, query_list) |tag, *query| {
            query.* = .{ .unit_tag = tag };
        }

        const query_res = self.call("query", .{
            .abilities = query_list,
            .ignore_resource_requirements = ignore_resource_requirements,
        }) catch return null;
        return query_res.abilities;
    }

    pub fn sendPlacementQuery(self: *WebSocketClient, query: sc2p.RequestQuery) ?[]sc2p.ResponseQueryBuildingPlacement {
        const query_res = self.call("query", query) catch return null;
        return query_res.placements;
    }

    pub fn step(self: *WebSocketClient, count: u32) !void {
        _ = try self.send("step", .{ .count = count });
    }

    pub fn leave(self: *WebSocketClient) !void {
        _ = try self.send("leave_game", {});
    }

    pub fn saveReplay(self: *WebSocketClient, replay_path: []const u8) !void {
        const replay_proto = try self.call("save_replay", {});
        const bytes = replay_proto.bytes orelse return ClientError.ReplayBytes;
        const file = std.Io.Dir.cwd().createFile(self.io, replay_path, .{}) catch return ClientError.ReplayFile;
        defer file.close(self.io);

        _ = file.writeStreamingAll(self.io, bytes) catch return ClientError.ReplayWrite;
    }

    pub fn quit(self: *WebSocketClient) !void {
        _ = try self.send("quit", {});
    }

    pub fn ping(self: *WebSocketClient) !sc2p.ResponsePing {
        return self.call("ping", {});
    }

    /// Sends a request with only `field` set and returns the whole response.
    fn send(
        self: *WebSocketClient,
        comptime field: []const u8,
        payload: RequestPayload(field),
    ) !sc2p.Response {
        var request: sc2p.Request = .{};
        @field(request, field) = payload;
        return self.writeAndWaitForMessage(request);
    }

    /// Like `send`, but returns the response field with the same name
    /// as the request field. A missing response field or a set
    /// `error_code` are turned into errors.
    fn call(
        self: *WebSocketClient,
        comptime field: []const u8,
        payload: RequestPayload(field),
    ) !ResponsePayload(field) {
        const res = try self.send(field, payload);
        const data = @field(res, field) orelse {
            std.log.err("Did not get {s} response", .{field});
            return ClientError.BadResponse;
        };

        const T = @TypeOf(data);
        if (@typeInfo(T) == .@"struct" and @hasField(T, "error_code")) {
            if (data.error_code) |code| {
                std.log.err("{s} error: {d}", .{ field, @intFromEnum(code) });
                if (data.error_details) |details| {
                    std.log.err("{s}", .{details});
                }
                return ClientError.BadResponse;
            }
        }
        return data;
    }

    fn expectStatus(self: *WebSocketClient, expected: sc2p.Status) !void {
        if (self.status != expected) {
            std.log.err("Wrong status: expected {s}, got {d}", .{ @tagName(expected), @intFromEnum(self.status) });
            return ClientError.BadResponse;
        }
    }

    fn writeAndWaitForMessage(self: *WebSocketClient, request: sc2p.Request) !sc2p.Response {
        {
            // Leaving space in the beginning for the bytes needed
            // in the websocket message
            const max_websocket_header_size = 14;

            var buf = try self.step_allocator.alloc(u8, 2 * 1024 * 1024);
            defer self.step_allocator.free(buf);

            const payload = try proto.encode(buf[max_websocket_header_size..], request);
            var msg = payload.ptr;
            var pre_payload: usize = 6;

            if (payload.len <= 125) {
                msg -= pre_payload;
                msg[1] = @as(u8, @truncate(payload.len));
            } else if (payload.len <= 65535) {
                pre_payload += 2;
                msg -= pre_payload;
                msg[1] = 126;
                mem.writeInt(u16, msg[2..4], @as(u16, @truncate(payload.len)), .big);
            } else {
                pre_payload += 8;
                msg -= pre_payload;
                msg[1] = 127;
                mem.writeInt(u64, msg[2..10], payload.len, .big);
            }
            msg[0] = @intFromEnum(OpCode.binary);
            //Last frame
            msg[0] |= 0x80;
            //Mask
            msg[1] |= 0x80;
            @memset(msg[pre_payload - 4 .. pre_payload], 0);

            const payload_end = pre_payload + payload.len;

            var stream_writer = self.socket.writer(self.io, &.{});
            errdefer {
                if (stream_writer.err) |err| {
                    std.log.err("Write error: {s}", .{@errorName(err)});
                }
            }
            try stream_writer.interface.writeAll(msg[0..payload_end]);
        }

        var stream_reader = self.socket.reader(self.io, &.{});
        errdefer {
            if (stream_reader.err) |err| {
                std.log.err("Read error: {s}", .{@errorName(err)});
            }
        }
        var reader = &stream_reader.interface;

        var header: [2]u8 = undefined;
        try reader.readSliceAll(&header);

        const payload_desc = header[1];
        var payload_length = @as(u64, payload_desc);

        if (payload_desc == 126) {
            var length: [2]u8 = undefined;
            try reader.readSliceAll(&length);
            payload_length = mem.readInt(u16, &length, .big);
        } else if (payload_desc == 127) {
            var length: [8]u8 = undefined;
            try reader.readSliceAll(&length);
            payload_length = mem.readInt(u64, &length, .big);
        }
        const payload_len: usize = @intCast(payload_length);
        const response_payload = try reader.readAlloc(self.step_allocator, payload_len);

        const res = try proto.decode(sc2p.Response, response_payload, self.step_allocator);

        if (res.errors) |errors| {
            for (errors) |error_string| {
                std.log.err("Message error: {s}", .{error_string});
            }
            return ClientError.ErrorsField;
        }

        if (res.status) |status| {
            self.status = status;
        }

        return res;
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
