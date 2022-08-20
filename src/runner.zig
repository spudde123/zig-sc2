const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const ChildProcess = std.ChildProcess;
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
    game_port: ?u16 = null,
    start_port: ?u16 = null,
    opponent_id: ?[]const u8 = null,
    real_time: bool = false,

    computer_race: sc2p.Race = .random,
    computer_difficulty: sc2p.AiDifficulty = .very_hard,
    computer_build: sc2p.AiBuild = .random,
    map: ?[]const u8 = null
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
                    program_args.game_port = fmt.parseUnsigned(u16, argument, 0) catch continue;
                },
                InputType.start_port => {
                    program_args.start_port = fmt.parseUnsigned(u16, argument, 0) catch continue;
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
    
    var ladder_game = false;
    var host: []const u8 = "127.0.0.1";
    var game_port: u16 = 5001;
    var start_port: u16 = 5002;
    var opponent_id: []const u8 = "Unknown";
    var sc2_process: ?*ChildProcess = null;
    
    if (program_args.ladder_server) |ladder_server| {
        ladder_game = true;
        host = ladder_server;

        if (program_args.opponent_id) |opp_id| {
            opponent_id = opp_id;
        }
        start_port = program_args.start_port orelse {
            log.err("Start port is missing\n", .{});
            return;
        };
        
        game_port = program_args.game_port orelse {
            log.err("Game port is missing\n", .{});
            return;
        };
    } else {
        const sc2_args = [_] []const u8{
            "C:/Program Files (x86)/StarCraft II/Versions/Base88500/SC2_X64.exe",
            "-listen",
            host,
            "-port",
            try fmt.allocPrint(arena, "{d}", .{game_port}),
            "-dataDir",
            "C:/Program Files (x86)/StarCraft II"
        };
        
        sc2_process = ChildProcess.init(sc2_args[0..], arena) catch |err| {
            return err;
        };
        sc2_process.?.cwd = "C:/Program Files (x86)/StarCraft II/Support64";

        try sc2_process.?.spawn();
    }

    const seconds_to_try = 10;

    var attempt: u32 = 0;

    var client: ws.WebSocketClient = undefined;
    var connection_ok = false;
    while (!connection_ok and attempt < seconds_to_try) : (attempt += 1) {
        std.debug.print("Doing ws connection loop {d}\n", .{attempt});
        client = ws.WebSocketClient.init(host, game_port, arena, fixed_buffer) catch {
            time.sleep(time.ns_per_s);
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

    var game_join: ws.GameJoin = undefined;

    const bot_setup: ws.BotSetup = .{
        .name = user_bot.name, 
        .race = user_bot.race
    };
    if (ladder_game) {
        game_join = client.joinLadderGame(bot_setup, start_port);
    } else {
        game_join = client.createGameVsComputer(
            bot_setup,
            "C:/Program Files (x86)/StarCraft II/Maps/LightshadeAIE.SC2Map",
            .{},
            false
        );
    }
    
    if (!game_join.success) {
        log.err("Failed to join the game\n", .{});
        return;
    }

    var player_id = game_join.player_id;
    var game_info: bot_data.GameInfo = undefined;

    var first_step_done = false;

    var actions = try bot_data.Actions.init(arena, fixed_buffer);

    while (true) {

        const obs = client.getObservation();

        if (obs.observation.data == null) {
            log.err("Got an invalid observation\n", .{});
            break;
        }
        const bot = try bot_data.Bot.fromProto(obs, player_id, fixed_buffer);

        if (bot.game_loop > 500) {
            _ = client.leave();
            break;
        } else {
            std.debug.print("Game loop {d}\n", .{bot.game_loop});
        }

        if (bot.result) |res| {
            user_bot.onResult(bot, game_info, res);
            break;
        }

        if (!first_step_done) {
            var game_info_proto = client.getGameInfo() catch {
                log.err("Error getting game info\n", .{});
                break;
            };

            var start_location: bot_data.Point2d = undefined;
            for (bot.own_units) |unit| {
                if (unit.unit_type == bot_data.UnitId.CommandCenter
                    or unit.unit_type == bot_data.UnitId.Hatchery
                    or unit.unit_type == bot_data.UnitId.Nexus) {
                        start_location = unit.position;
                        break;
                }
            }

            game_info = try bot_data.GameInfo.fromProto(
                game_info_proto, 
                player_id, 
                start_location,
                arena
            );
            
            user_bot.onStart(bot, game_info, &actions);
            first_step_done = true;
        }

        user_bot.onStep(bot, game_info, &actions);

        const maybe_action_proto = actions.toProto();
        if (maybe_action_proto) |action_proto| {
            try client.sendActions(action_proto);
        }

        _ = client.step(step_count);

        actions.clear();
        fixed_buffer_instance.reset();
    }
    //const term = sc2_process.kill();

    if (sc2_process) |sc2| {
        _ = client.quit();
        sc2.deinit();
    }
    //std.debug.print("Term status: {d}\n", .{term});
}