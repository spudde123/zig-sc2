const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const cp = std.ChildProcess;
const time = std.time;
const log = std.log;

const sc2p = @import("sc2proto.zig");
const ws = @import("client.zig");
const bot_data = @import("bot.zig");

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
    ladder_server: ?[]const u8 = null,
    game_port: ?i32 = null,
    start_port: ?i32 = null,
    opponent_id: ?[]const u8 = null,
    real_time: bool = false,

    computer_race: sc2p.Race = .random,
    computer_difficulty: sc2p.AiDifficulty = .very_hard,
    computer_build: sc2p.AiBuild = .random,
    map: ?[]u8 = null
};

fn readArguments(allocator: mem.Allocator) ProgramArguments {
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

    var arg_iter = std.process.args();

    // Skip exe name
    _ = arg_iter.skip();

    var current_input_type = InputType.none;

    while (arg_iter.next(allocator)) |arg| {
        const argument = arg catch break;
        defer allocator.free(argument);
        
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
                    program_args.game_port = fmt.parseInt(i32, argument, 0) catch continue;
                },
                InputType.start_port => {
                    program_args.start_port = fmt.parseInt(i32, argument, 0) catch continue;
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

    return program_args;
}


pub fn run(
    user_bot: anytype,
    step_count: u32,
) !void {
    
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // Arena allocator that is freed at the end of each step
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    var step_bytes = try arena.alloc(u8, 30*1024*1024);
    var fixed_buffer_instance = std.heap.FixedBufferAllocator.init(step_bytes);
    const fixed_buffer = fixed_buffer_instance.allocator();
    
    var program_args = readArguments(arena);
    
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
        "C:/Program Files (x86)/StarCraft II/Versions/Base88500/SC2_X64.exe",
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
    while (!connection_ok and attempt < seconds_to_try) : (attempt += 1) {
        time.sleep(time.ns_per_s);
        std.debug.print("Doing loop {d}\n", .{attempt});
        client = ws.WebSocketClient.init("127.0.0.1", 5001, arena, fixed_buffer) catch {
            continue;
        };
        connection_ok = true;
    }

    if (!connection_ok) {
        log.err("Failed to connect to sc2\n", .{});
        return;
    }
    
    defer client.deinit();

    const handshake_ok = try client.completeHandshake("/sc2api");
    if (!handshake_ok) {
        log.err("Failed websocket handshake\n", .{});
        return;
    }

    var game_join = client.createGameVsComputer(
        .{.name = "spudde", .race = .terran},
        "C:/Program Files (x86)/StarCraft II/Maps/LightshadeAIE.SC2Map",
        .{},
        false
    );

    if (!game_join.success) {
        log.err("Failed to join the game\n", .{});
        return;
    }

    var player_id = game_join.player_id;
    
    var first_step_done = false;

    while (true) {

        const obs = client.getObservation();

        if (obs.observation.data == null) {
            log.err("Got an invalid observation\n", .{});
            break;
        }
        const bot = try bot_data.Bot.fromProto(obs, player_id, fixed_buffer);

        if (bot.game_loop > 100) {
            break;
        } else {
            std.debug.print("Game loop {d}\n", .{bot.game_loop});
        }

        if (bot.result) |res| {
            user_bot.onResult(bot, res);
            break;
        }

        if (!first_step_done) {
            user_bot.onStart(bot);
            first_step_done = true;
        }

        user_bot.onStep(bot);

        _ = client.step(step_count);
        
        fixed_buffer_instance.reset();
    }

    _ = client.quit();

    //const term = sc2_process.kill();

    //std.debug.print("Term status: {d}\n", .{term});
}