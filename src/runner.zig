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
    computer_build,
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
    map_file_name: []const u8 = "LightshadeAIE"
};

const race_map = std.ComptimeStringMap(sc2p.Race, .{
    .{"terran", .terran},
    .{"zerg", .zerg},
    .{"protoss", .protoss},
    .{"random", .random},
});

const difficulty_map = std.ComptimeStringMap(sc2p.AiDifficulty, .{
    .{"very_easy", .very_easy},
    .{"easy", .easy},
    .{"medium", .medium},
    .{"medium_hard", .medium_hard},
    .{"hard", .hard},
    .{"harder", .harder},
    .{"very_hard", .very_hard},
    .{"cheat_vision", .cheat_vision},
    .{"cheat_money", .cheat_money},
    .{"cheat_insane", .cheat_insane},
});

const build_map = std.ComptimeStringMap(sc2p.AiBuild, .{
    .{"random", .random},
    .{"rush", .rush},
    .{"timing", .timing},
    .{"power", .power},
    .{"macro", .macro},
    .{"air", .air}
});

fn readArguments(allocator: mem.Allocator) ProgramArguments {
    var program_args = ProgramArguments{};

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
            } else if (mem.eql(u8, argument, "--CompRace")) {
                current_input_type = InputType.computer_race;
            } else if (mem.eql(u8, argument, "--CompDifficulty")) {
                current_input_type = InputType.computer_difficulty;
            } else if (mem.eql(u8, argument, "--CompBuild")) {
                current_input_type = InputType.computer_build;
            } else if (mem.eql(u8, argument, "--Map")) {
                current_input_type = InputType.map;
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
                    var opt_difficulty = difficulty_map.get(argument);
                    if (opt_difficulty) |difficulty| {
                        program_args.computer_difficulty = difficulty;
                    } else {
                        log.info("Unknown difficulty {s}\n", .{argument});
                        log.info("Available difficulties:\n", .{});
                        for (difficulty_map.kvs) |kv| {
                            log.info("{s}\n", .{kv.key});
                        }
                    }
                },
                InputType.computer_race => {
                    var opt_race = race_map.get(argument);
                    if (opt_race) |race| {
                        program_args.computer_race = race;
                    } else {
                        log.info("Unknown race {s}\n", .{argument});
                        log.info("Available races:\n", .{});
                        for (race_map.kvs) |kv| {
                            log.info("{s}\n", .{kv.key});
                        }
                    }
                },
                InputType.computer_build => {
                    var opt_build = build_map.get(argument);
                    if (opt_build) |build| {
                        program_args.computer_build = build;
                    } else {
                        log.info("Unknown build {s}\n", .{argument});
                        log.info("Available builds:\n", .{});
                        for (build_map.kvs) |kv| {
                            log.info("{s}\n", .{kv.key});
                        }
                    }
                },
                InputType.map => {
                    program_args.map_file_name = argument;
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
    base_allocator: mem.Allocator
) !void {
    
    var arena_instance = std.heap.ArenaAllocator.init(base_allocator);
    // Arena allocator that is freed at the end of the game
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    // Fixed buffer which is reset at the end of each step
    var step_bytes = try arena.alloc(u8, 30*1024*1024);
    var fixed_buffer_instance = std.heap.FixedBufferAllocator.init(step_bytes);
    const fixed_buffer = fixed_buffer_instance.allocator();
    
    const program_args = readArguments(arena);
    
    var ladder_game = false;
    var host: []const u8 = "127.0.0.1";
    var game_port: u16 = 5001;
    var start_port: u16 = 5002;
    var sc2_process: ?*ChildProcess = null;
    
    if (program_args.ladder_server) |ladder_server| {
        ladder_game = true;
        host = ladder_server;

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
        if (sc2_process) |sc2| {
            _ = try sc2.kill();
        }
        return;
    }
    
    defer client.deinit();
    defer {
        if (sc2_process) |sc2| {
            _ = client.quit();
            sc2.deinit();
        }
    }

    const handshake_ok = try client.completeHandshake("/sc2api");
    if (!handshake_ok) {
        log.err("Failed websocket handshake\n", .{});
        return;
    }

    var game_join: ws.GameJoin = .{};

    const bot_setup: ws.BotSetup = .{
        .name = user_bot.name, 
        .race = user_bot.race
    };
    if (ladder_game) {
        game_join = client.joinLadderGame(bot_setup, start_port);
    } else create_game_block: {
        
        const map_folder = "C:/Program Files (x86)/StarCraft II/Maps/";
        var strings_to_concat = [_][]const u8{map_folder, program_args.map_file_name, ".SC2Map"};
        var map_absolute_path = try mem.concat(arena, u8, &strings_to_concat);
        std.fs.accessAbsolute(map_absolute_path, .{}) catch {
            log.err("Map file {s} was not found\n", .{map_absolute_path});
            break :create_game_block;
        };

        game_join = client.createGameVsComputer(
            bot_setup,
            map_absolute_path,
            ws.ComputerSetup{
                .difficulty = program_args.computer_difficulty,
                .build = program_args.computer_build,
                .race = program_args.computer_race,
            },
            false
        );
        
    }
    
    if (!game_join.success) {
        log.err("Failed to join the game\n", .{});
        return;
    }

    const player_id = game_join.player_id;
    var game_info: bot_data.GameInfo = undefined;

    var first_step_done = false;

    var actions: bot_data.Actions = undefined;

    const game_data_proto = client.getGameData() catch {
        log.err("Error getting game data\n", .{});
        return;
    };

    const game_data = try bot_data.GameData.fromProto(game_data_proto, arena);
    actions = try bot_data.Actions.init(game_data, arena, fixed_buffer);

    while (true) {

        const obs = client.getObservation();

        if (obs.observation.data == null) {
            log.err("Got an invalid observation\n", .{});
            break;
        }
        const bot = try bot_data.Bot.fromProto(obs, game_data, player_id, fixed_buffer);

        if (bot.result) |res| {
            user_bot.onResult(bot, game_info, res);
            break;
        }

        if (!first_step_done) {

            const game_info_proto = client.getGameInfo() catch {
                log.err("Error getting game info\n", .{});
                break;
            };

            const start_location: bot_data.Point2 = sl: {
                for (bot.structures) |unit| {
                    if (unit.unit_type == bot_data.UnitId.CommandCenter
                        or unit.unit_type == bot_data.UnitId.Hatchery
                        or unit.unit_type == bot_data.UnitId.Nexus) {
                            break :sl unit.position;
                    }
                }
                break :sl bot_data.Point2{.x = 0, .y = 0};
            };
            

            game_info = try bot_data.GameInfo.fromProto(
                game_info_proto, 
                player_id,
                program_args.opponent_id,
                start_location,
                arena
            );
            
            user_bot.onStart(bot, game_info, &actions);
            first_step_done = true;
        }

        // Set enemy race to the observed race when we can
        if (game_info.enemy_race == .random and (bot.enemy_units.len > 0 or bot.enemy_structures.len > 0)) {
            const enemy_unit = if (bot.enemy_units.len > 0) bot.enemy_units[0] else bot.enemy_structures[0];
            const maybe_unit_data = game_data.units.get(enemy_unit.unit_type);
            if (maybe_unit_data) |unit_data| {
                game_info.enemy_race = unit_data.race;
            } else {
                log.debug("Unit {d} was not found in data\n", .{enemy_unit.unit_type});
            }
        }

        user_bot.onStep(bot, game_info, &actions);

        if (actions.leave_game) {
            _ = client.leave();
            user_bot.onResult(bot, game_info, .defeat);
            break;
        }

        const maybe_action_proto = actions.toProto();
        if (maybe_action_proto) |action_proto| {
            try client.sendActions(action_proto);
        }

        _ = client.step(step_count);

        actions.clear();
        fixed_buffer_instance.reset();
    }
    //const term = sc2_process.kill();
    //std.debug.print("Term status: {d}\n", .{term});
}


test "runner_test" {
    // Mainly checking that memory isn't leaking
    
    const TestBot = struct {
        const Self = @This();
        name: []const u8,
        race: bot_data.Race,

        pub fn onStart(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            actions: *bot_data.Actions
        ) void {
            _ = self;
            _ = game_info;
            const enemy_start_location = game_info.enemy_start_locations[0];

            for (bot.units) |unit| {
                if (unit.unit_type == bot_data.UnitId.SCV) {
                    actions.attackPosition(unit.tag, enemy_start_location, false);
                }
            }
            actions.chat(.broadcast, "Testing all chat!");
            actions.chat(.team, "Testing team chat!");
        }

        pub fn onStep(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            actions: *bot_data.Actions
        ) void {
            _ = game_info;
            _ = self;
            if (bot.game_loop > 500) actions.leaveGame();
        }

        pub fn onResult(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            result: bot_data.Result
        ) void {
            _ = bot;
            _ = game_info;
            _ = result;
            _ = self;
        }
    };

    var test_bot = TestBot{.name = "tester", .race = .terran};

    try run(&test_bot, 2, std.testing.allocator);
}