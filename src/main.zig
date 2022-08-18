const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const cp = std.ChildProcess;
const time = std.time;

const ws = @import("client.zig");
const sc2p = @import("sc2proto.zig");

const InputType = enum(u8) {
    none,
    ladder_server,
    game_port,
    start_port,
    opponent_id,
    real_time,
    computer_race,
    computer_difficulty,
    map
};

const ProgramArguments = struct {
    ladder_server: ?[]u8,
    game_port: ?u32,
    start_port: ?u32,
    opponent_id: ?[]u8,
    real_time: bool,

    computer_race: sc2p.StarcraftRace,
    computer_difficulty: sc2p.AIDifficulty,
    computer_build: sc2p.AIBuild,
    map: ?[]u8
};

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    
    var arg_iter = std.process.args();

    // Skip exe name
    _ = arg_iter.skip();

    var current_input_type = InputType.none;
    var program_args = ProgramArguments{
        .ladder_server = null,
        .game_port = null,
        .start_port = null,
        .opponent_id = null,
        .real_time = false,
        
        .computer_race = .random,
        .computer_difficulty = .easy,
        .computer_build = .random,
        .map = null
    };
    
    while (arg_iter.next(arena)) |arg| {
        const argument = arg catch break;
        
        if (mem.startsWith(u8, argument, "-")) {
            if (mem.eql(u8, argument, "--LadderServer")) {
                current_input_type = InputType.ladder_server;
            } else if (mem.eql(u8, argument, "--GamePort")) {
                current_input_type = InputType.game_port;
            } else if (mem.eql(u8, argument, "--StartPort")) {
                current_input_type = InputType.start_port;
            } else if (mem.eql(u8, argument, "--OpponentId")) {
                current_input_type = InputType.opponent_id;
            } else if (mem.eql(u8, argument, "--RealTime")) {
                current_input_type = InputType.real_time;
                program_args.real_time = true;
            } else {
                current_input_type = InputType.none;
            }
        } else if (current_input_type != InputType.none) {
            switch (current_input_type) {
                InputType.ladder_server => {
                    program_args.ladder_server = argument;
                },
                InputType.game_port => {
                    program_args.game_port = fmt.parseUnsigned(u32, argument, 0) catch continue;
                },
                InputType.start_port => {
                    program_args.start_port = fmt.parseUnsigned(u32, argument, 0) catch continue;
                },
                InputType.opponent_id => {
                    program_args.opponent_id = argument;
                },
                InputType.computer_difficulty => {

                },
                InputType.computer_race => {
                },
                InputType.map => {
                    program_args.map = argument;
                },
                else => {}
            }
            current_input_type = InputType.none;
        }
    }
    if (program_args.ladder_server) |ladder_server| {
        std.debug.print("LadderServer: {s}\n", .{ladder_server});
    }
    if (program_args.opponent_id) |opponent_id| {
        std.debug.print("OpponentId: {s}\n", .{opponent_id});
    }
    if (program_args.start_port) |start_port| {
        std.debug.print("StartPort: {d}\n", .{start_port});
    }

    if (program_args.game_port) |game_port| {
        std.debug.print("GamePort: {d}\n", .{game_port});
    }

    const a = [_] []const u8{
        "C:/Program Files (x86)/StarCraft II/Versions/Base86383/SC2_X64.exe",
        "-listen",
        "127.0.0.1",
        "-port",
        "5001",
        "-dataDir",
        "C:/Program Files (x86)/StarCraft II"
    };
    
    const sc2_process = cp.init(a[0..], arena) catch |err| {
        return err;
    };
    sc2_process.cwd = "C:/Program Files (x86)/StarCraft II/Support64";
    defer sc2_process.deinit();

    try sc2_process.spawn();

    const seconds_to_try = 10;

    var attempt: u32 = 0;

    var client: ws.WebSocketClient = undefined;
    var connection_ok = false;
    while (!connection_ok and attempt < seconds_to_try) {
        time.sleep(time.ns_per_s);
        std.debug.print("Doing loop {d}\n", .{attempt});
        client = ws.WebSocketClient.init("127.0.0.1", 5001, arena) catch {
            attempt += 1;
            continue;
        };
        connection_ok = true;
    }

    if (!connection_ok) {
        return;
    }
    
    defer client.deinit();

    var buf = try arena.alloc(u8, 1024*1000);

    if (try client.completeHandshake("/sc2api")) {
        std.debug.print("Handshake ok\n", .{});
        var ping_payload = sc2p.generatePingRequest(buf);
        var res = try client.writeAndWaitForMessage(ping_payload);
        if (res.ping.data) |ping| {
            std.debug.print("{s}\n", .{ping.game_version.data.?});
        }

        var game_join = client.createGameVsComputer(
            .{.name = "spudde", .race = .terran},
            "C:/Program Files (x86)/StarCraft II/Maps/LightshadeAIE.SC2Map",
            .{},
            false
        );

        std.debug.print("Joined game as player: {d}\n", .{game_join.player_id});
        var quit_payload = sc2p.generateQuitRequest(buf);
        res = try client.writeAndWaitForMessage(quit_payload);
        if (res.quit.data) |_| {
            std.debug.print("Got quit\n", .{});
        }
    }
    const term = sc2_process.kill();

    std.debug.print("Term status: {d}\n", .{term});
}