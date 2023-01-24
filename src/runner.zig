const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const ChildProcess = std.ChildProcess;
const time = std.time;
const log = std.log;
const fs = std.fs;
const builtin = @import("builtin");

const sc2p = @import("sc2proto.zig");
const ws = @import("client.zig");
pub const bot_data = @import("bot.zig");

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
    map_file_name: []const u8 = "InsideAndOutAIE"
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

const Sc2Paths = struct {
    base_folder: []const u8,
    map_folder: []const u8,
    latest_binary: []const u8,
    working_directory: ?[]const u8,
};

pub const LocalRunSetup = struct {
    sc2_base_folder: []const u8 = switch (builtin.os.tag) {
        .windows => "C:/Program Files (x86)/StarCraft II",
        .macos => "/Applications/StarCraft II",
        .linux => "~/StarCraftII",
        else => unreachable,
    },
    game_port: u16 = 5001,
};

const Sc2PathError = error{
    no_version_folders_found,
};

fn getSc2Paths(base_folder: []const u8, allocator: mem.Allocator) !Sc2Paths {
    const map_concat = [_][]const u8{base_folder, "/Maps/"};
    const support64_concat = [_][]const u8{base_folder, "/Support64/"};
    const versions_concat = [_][]const u8{base_folder, "/Versions/"};
    const versions_path = try mem.concat(allocator, u8, &versions_concat);
    var dir = try fs.openIterableDirAbsolute(versions_path, .{});
    defer dir.close();

    var iter = dir.iterate();
    var max_version: u64 = 0;
    while (try iter.next()) |version| {
        if (mem.startsWith(u8, version.name, "Base")) {
            const version_num_string = version.name[4..];
            const num = fmt.parseUnsigned(u64, version_num_string, 0) catch continue;
            if (num > max_version) max_version = num;
        }
    }

    if (max_version == 0) return Sc2PathError.no_version_folders_found;

    log.info("Using game version {d}\n", .{max_version});
    return Sc2Paths{
        .base_folder = base_folder,
        .map_folder = try mem.concat(allocator, u8, &map_concat),
        .working_directory = switch (builtin.os.tag) {
            .windows => try mem.concat(allocator, u8, &support64_concat),
            .macos, .linux => null,
            else => unreachable,
        },
        .latest_binary = switch (builtin.os.tag) {
            .windows => try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64.exe", .{versions_path, max_version}),
            .macos => try fmt.allocPrint(allocator, "{s}Base{d}/SC2.app/Contents/MacOS/SC2", .{versions_path, max_version}),
            .linux => try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64", .{versions_path, max_version}),
            else => unreachable,
        },
    };
}

fn readArguments(allocator: mem.Allocator) ProgramArguments {
    var program_args = ProgramArguments{};

    var arg_iter = std.process.argsWithAllocator(allocator) catch return program_args;
    // Skip exe name
    _ = arg_iter.skip();

    var current_input_type = InputType.none;

    while (arg_iter.next()) |argument| {
        
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
                    const opt_difficulty = difficulty_map.get(argument);
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
                    const opt_race = race_map.get(argument);
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
                    const opt_build = build_map.get(argument);
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
    base_allocator: mem.Allocator,
    local_run: LocalRunSetup
) !void {
    // Step_count 1 may cause problems from
    // what i've heard with unit orders
    // not showing up yet on the next frame
    // and so on.
    // Step_count 2 should be good enough
    // regardless
    std.debug.assert(step_count > 1);
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
    var game_port: u16 = local_run.game_port;
    var start_port: u16 = 5002;
    var sc2_process: ?ChildProcess = null;
    var sc2_paths: Sc2Paths = undefined;
    
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
        
        sc2_paths = getSc2Paths(local_run.sc2_base_folder, arena) catch {
            log.err("Couldn't form SC2 paths\n", .{});
            return;
        };
        const sc2_args = [_] []const u8{
            sc2_paths.latest_binary,
            "-listen",
            host,
            "-port",
            try fmt.allocPrint(arena, "{d}", .{game_port}),
            "-dataDir",
            sc2_paths.base_folder
        };
        
        sc2_process = ChildProcess.init(sc2_args[0..], arena);
        sc2_process.?.cwd = sc2_paths.working_directory;

        try sc2_process.?.spawn();
    }

    const times_to_try = 20;
    var attempt: u32 = 0;

    var client: ws.WebSocketClient = undefined;
    var connection_ok = false;
    while (!connection_ok and attempt < times_to_try) : (attempt += 1) {
        std.debug.print("Doing ws connection loop {d}\n", .{attempt});
        client = ws.WebSocketClient.init(host, game_port, arena, fixed_buffer) catch {
            time.sleep(2*time.ns_per_s);
            continue;
        };
        connection_ok = true;
    }

    if (!connection_ok) {
        log.err("Failed to connect to sc2\n", .{});
        
        if (sc2_process) |*sc2| {
            _ = try sc2.kill();
        }
        return;
    }
    
    defer client.deinit();

    const handshake_ok = try client.completeHandshake("/sc2api");
    if (!handshake_ok) {
        log.err("Failed websocket handshake\n", .{});
        if (sc2_process) |*sc2| {
            _ = try sc2.kill();
        }
        return;
    }

    defer {
        if (sc2_process) |_| {
            _ = client.quit() catch {
                log.err("Unable to quit the game\n", .{});
            };
        }
    }

    const bot_setup: ws.BotSetup = .{
        .name = user_bot.name, 
        .race = user_bot.race
    };

    const player_id: u32 = pid: {
        if (ladder_game) {
            break :pid client.joinLadderGame(bot_setup, start_port) catch |err| {
                log.err("Failed to join ladder game: {s}\n", .{@errorName(err)});
                return;
            };
        } else {
            const strings_to_concat = [_][]const u8{sc2_paths.map_folder, program_args.map_file_name, ".SC2Map"};
            const map_absolute_path = try mem.concat(arena, u8, &strings_to_concat);
            std.fs.accessAbsolute(map_absolute_path, .{}) catch {
                log.err("Map file {s} was not found\n", .{map_absolute_path});
                return;
            };
            break :pid client.createGameVsComputer(
                bot_setup,
                map_absolute_path,
                ws.ComputerSetup{
                    .difficulty = program_args.computer_difficulty,
                    .build = program_args.computer_build,
                    .race = program_args.computer_race,
                },
                program_args.real_time,
            ) catch |err| {
                log.err("Failed to create game: {s}\n", .{@errorName(err)});
                return;
            };
        }
    };

    var game_info: bot_data.GameInfo = undefined;

    var first_step_done = false;

    const game_data_proto = client.getGameData() catch |err| {
        log.err("Error getting game data: {s}\n", .{@errorName(err)});
        return;
    };

    const game_data = try bot_data.GameData.fromProto(game_data_proto, arena);
    var actions = try bot_data.Actions.init(game_data, &client, arena, fixed_buffer);

    var own_units = std.AutoArrayHashMap(u64, bot_data.Unit).init(arena);
    try own_units.ensureTotalCapacity(200);

    var enemy_units = std.AutoArrayHashMap(u64, bot_data.Unit).init(arena);
    try enemy_units.ensureTotalCapacity(200);

    var requested_game_loop: u32 = 0;
    while (true) {

        const obs = if (program_args.real_time) try client.getObservation(requested_game_loop) else try client.getObservation(null);

        var bot = try bot_data.Bot.fromProto(&own_units, &enemy_units, obs, game_data, player_id, fixed_buffer);
        // Not sure if the given game loop may be larger than what was requested
        // if the bot takes too long to make the step.
        // Regardless doesn't hurt to sync it
        requested_game_loop = bot.game_loop + step_count;

        if (bot.result) |res| {
            if (sc2_process) |_| {
                if (createReplayName(arena, user_bot.name, game_info.enemy_name, game_info.map_name)) |replay_name| {
                    _ = client.saveReplay(replay_name) catch |err| {
                        log.err("Unable to save replay: {s}\n", .{@errorName(err)});
                    };
                }
                _ = client.leave() catch {
                    log.err("Unable to leave game\n", .{});
                };
            }
            try user_bot.onResult(bot, game_info, res);
            break;
        }

        const all_own_unit_tags = bot.units.keys();
        if (all_own_unit_tags.len > 0) {
            if (client.getAvailableAbilities(all_own_unit_tags, true)) |abilities_proto| {
                bot.setUnitAbilitiesFromProto(abilities_proto, fixed_buffer);
            }
        }

        if (!first_step_done) {

            const game_info_proto = client.getGameInfo() catch {
                log.err("Error getting game info\n", .{});
                break;
            };

            const start_location: bot_data.Point2 = sl: {
                const unit_slice = bot.units.values();
                for (unit_slice) |unit| {
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
                bot.mineral_patches,
                bot.vespene_geysers,
                bot.destructibles,
                arena,
                fixed_buffer
            );
            bot_data.grids.InfluenceMap.MapInfo.terrain_height = game_info.terrain_height.data;
            game_info.updateGrids(bot);
            try user_bot.onStart(bot, game_info, &actions);
            first_step_done = true;
        }
        // We do this twice on the first step but it's not a problem
        game_info.updateGrids(bot);

        // Set enemy race to the observed race when we can
        if (game_info.enemy_race == .random and bot.enemy_units.count() > 0) {
            const enemy_unit = bot.enemy_units.values()[0];
            if (game_data.units.get(enemy_unit.unit_type)) |unit_data| {
                game_info.enemy_race = unit_data.race;
            } else {
                log.debug("Unit {d} was not found in data\n", .{enemy_unit.unit_type});
            }
        }

        try user_bot.onStep(bot, game_info, &actions);

        if (actions.leave_game) {
            
            if (sc2_process) |_| {
                if (createReplayName(arena, user_bot.name, game_info.enemy_name, game_info.map_name)) |replay_name| {
                    _ = client.saveReplay(replay_name) catch |err| {
                        log.err("Unable to save replay: {s}\n", .{@errorName(err)});
                    };
                }
            }
            
            _ = client.leave() catch {
                log.err("Unable to leave game\n", .{});
            };
            try user_bot.onResult(bot, game_info, .defeat);
            break;
        }

        if (actions.toProto()) |action_proto| {
            client.sendActions(action_proto) catch {
                log.err("Error sending actions at game loop {d}\n", .{bot.game_loop});
            };
        }

        if (actions.debugCommandsToProto()) |debug_proto| {
            client.sendDebugRequest(debug_proto);
        }

        if (!program_args.real_time) {
            _ = try client.step(step_count);
        }

        actions.clear();
        fixed_buffer_instance.reset();
    }
}

fn createReplayName(
    allocator: mem.Allocator,
    bot_name: []const u8,
    opponent: []const u8,
    map: []const u8
) ?[]const u8 {
    const no_gap_bot_size = mem.replacementSize(u8, bot_name, " ", "");
    var new_bot_name = allocator.alloc(u8, no_gap_bot_size) catch return null;
    _ = mem.replace(u8, bot_name, " ", "", new_bot_name);

    const no_gap_opp_size = mem.replacementSize(u8, opponent, " ", "");
    var new_opponent_name = allocator.alloc(u8, no_gap_opp_size) catch return null;
    _ = mem.replace(u8, opponent, " ", "", new_opponent_name);

    const no_gap_map_size = mem.replacementSize(u8, map, " ", "");
    var new_map_name = allocator.alloc(u8, no_gap_map_size) catch return null;
    _ = mem.replace(u8, map, " ", "", new_map_name);

    const replay_name = fmt.allocPrint(allocator, "./replays/{s}_{s}_{s}_{d}.SC2Replay", .{
        new_bot_name,
        new_opponent_name,
        new_map_name,
        time.timestamp(),
    }) catch return null;

    return replay_name;
}


test "runner_test_basic" {
    // Just test that we can connect without problems
    
    const TestBot = struct {
        const Self = @This();
        name: []const u8,
        race: bot_data.Race,

        pub fn onStart(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            actions: *bot_data.Actions
        ) !void {
            _ = self;
            const enemy_start_location = game_info.enemy_start_locations[0];
            const units = bot.units.values();

            for (units) |unit| {
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
        ) !void {
            _ = game_info;
            _ = self;
            if (bot.game_loop > 500) actions.leaveGame();
        }

        pub fn onResult(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            result: bot_data.Result
        ) !void {
            _ = bot;
            _ = game_info;
            _ = result;
            _ = self;
        }
    };

    var test_bot = TestBot{.name = "tester", .race = .terran};

    try run(&test_bot, 2, std.testing.allocator, .{});
}
