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
    realtime,
    computer_race,
    computer_difficulty,
    computer_build,
    map,
    human_race,
    sc2_path,
};

const ProgramArguments = struct {
    ladder_server: ?[]const u8 = null,
    game_port: ?u16 = null,
    start_port: ?u16 = null,
    opponent_id: ?[]const u8 = null,
    realtime: bool = false,
    computer_race: sc2p.Race = .random,
    computer_difficulty: sc2p.AiDifficulty = .very_hard,
    computer_build: sc2p.AiBuild = .random,
    map_file_name: []const u8 = "InsideAndOutAIE",
    human_game: bool = false,
    human_race: sc2p.Race = .random,
    sc2_path: ?[]const u8 = null,
};

const race_map = std.ComptimeStringMap(sc2p.Race, .{
    .{ "terran", .terran },
    .{ "zerg", .zerg },
    .{ "protoss", .protoss },
    .{ "random", .random },
});

const difficulty_map = std.ComptimeStringMap(sc2p.AiDifficulty, .{
    .{ "very_easy", .very_easy },
    .{ "easy", .easy },
    .{ "medium", .medium },
    .{ "medium_hard", .medium_hard },
    .{ "hard", .hard },
    .{ "harder", .harder },
    .{ "very_hard", .very_hard },
    .{ "cheat_vision", .cheat_vision },
    .{ "cheat_money", .cheat_money },
    .{ "cheat_insane", .cheat_insane },
});

const build_map = std.ComptimeStringMap(sc2p.AiBuild, .{
    .{ "random", .random },
    .{ "rush", .rush },
    .{ "timing", .timing },
    .{ "power", .power },
    .{ "macro", .macro },
    .{ "air", .air },
});

const Sc2Paths = struct {
    base_folder: []const u8,
    map_folder: []const u8,
    latest_binary: []const u8,
    working_directory: ?[]const u8,
};

const standard_sc2_base_folder: []const u8 = switch (builtin.os.tag) {
    .windows => "C:/Program Files (x86)/StarCraft II",
    .macos => "/Applications/StarCraft II",
    .linux => "~/StarCraftII",
    else => @compileError("OS not supported"),
};

const Sc2PathError = error{
    no_version_folders_found,
};

fn getSc2Paths(base_folder: []const u8, allocator: mem.Allocator) !Sc2Paths {
    const map_concat = [_][]const u8{ base_folder, "/Maps/" };
    const support64_concat = [_][]const u8{ base_folder, "/Support64/" };
    const versions_concat = [_][]const u8{ base_folder, "/Versions/" };
    const versions_path = try mem.concat(allocator, u8, &versions_concat);
    var dir = fs.openIterableDirAbsolute(versions_path, .{}) catch {
        log.err("Couldn't open versions folder {s}\n", .{versions_path});
        return Sc2PathError.no_version_folders_found;
    };
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

    log.debug("Using game version {d}\n", .{max_version});
    return Sc2Paths{
        .base_folder = base_folder,
        .map_folder = try mem.concat(allocator, u8, &map_concat),
        .working_directory = switch (builtin.os.tag) {
            .windows => try mem.concat(allocator, u8, &support64_concat),
            .macos, .linux => null,
            else => @compileError("OS not supported"),
        },
        .latest_binary = switch (builtin.os.tag) {
            .windows => try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64.exe", .{ versions_path, max_version }),
            .macos => try fmt.allocPrint(allocator, "{s}Base{d}/SC2.app/Contents/MacOS/SC2", .{ versions_path, max_version }),
            .linux => try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64", .{ versions_path, max_version }),
            else => @compileError("OS not supported"),
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
                current_input_type = InputType.realtime;
                program_args.realtime = true;
            } else if (mem.eql(u8, argument, "--CompRace")) {
                current_input_type = InputType.computer_race;
            } else if (mem.eql(u8, argument, "--CompDifficulty")) {
                current_input_type = InputType.computer_difficulty;
            } else if (mem.eql(u8, argument, "--CompBuild")) {
                current_input_type = InputType.computer_build;
            } else if (mem.eql(u8, argument, "--Map")) {
                current_input_type = InputType.map;
            } else if (mem.eql(u8, argument, "--Human")) {
                current_input_type = InputType.human_race;
                program_args.human_game = true;
            } else if (mem.eql(u8, argument, "--SC2")) {
                current_input_type = InputType.sc2_path;
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
                    if (difficulty_map.get(argument)) |difficulty| {
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
                    if (race_map.get(argument)) |race| {
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
                    if (build_map.get(argument)) |build| {
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
                InputType.human_race => {
                    if (race_map.get(argument)) |race| {
                        program_args.human_race = race;
                    } else {
                        log.info("Unknown race {s}\n", .{argument});
                        log.info("Available races:\n", .{});
                        for (race_map.kvs) |kv| {
                            log.info("{s}\n", .{kv.key});
                        }
                    }
                },
                InputType.sc2_path => {
                    program_args.sc2_path = argument;
                },
                else => {},
            }
            current_input_type = InputType.none;
        }
    }

    return program_args;
}

fn runHumanGame(
    step_count: u32,
    base_allocator: mem.Allocator,
    sc2_paths: Sc2Paths,
    map_absolute_path: []const u8,
    bot_setup: ws.BotSetup,
    realtime: bool,
    game_port: u16,
    start_port: u16,
) !void {
    var arena_instance = std.heap.ArenaAllocator.init(base_allocator);
    // Arena allocator that is freed at the end of the game
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    var step_arena_instance = std.heap.ArenaAllocator.init(base_allocator);
    defer step_arena_instance.deinit();
    const step_arena = step_arena_instance.allocator();

    const host = "127.0.0.1";

    const sc2_args = [_][]const u8{
        sc2_paths.latest_binary,
        "-listen",
        host,
        "-port",
        try fmt.allocPrint(arena, "{d}", .{game_port}),
        "-dataDir",
        sc2_paths.base_folder,
    };

    var sc2_process = ChildProcess.init(sc2_args[0..], arena);
    sc2_process.cwd = sc2_paths.working_directory;

    try sc2_process.spawn();

    const times_to_try = 20;
    var attempt: u32 = 0;

    var client: ws.WebSocketClient = undefined;
    var connection_ok = false;
    while (!connection_ok and attempt < times_to_try) : (attempt += 1) {
        log.debug("Doing ws connection loop {d}\n", .{attempt});
        client = ws.WebSocketClient.init(host, game_port, arena, step_arena) catch {
            time.sleep(2 * time.ns_per_s);
            continue;
        };
        connection_ok = true;
    }

    if (!connection_ok) {
        log.err("Failed to connect to sc2\n", .{});

        _ = try sc2_process.kill();
        return;
    }

    defer client.deinit();

    const handshake_ok = try client.completeHandshake("/sc2api");
    if (!handshake_ok) {
        log.err("Failed websocket handshake\n", .{});
        _ = try sc2_process.kill();
        return;
    }

    defer {
        _ = client.quit() catch {
            log.err("Unable to quit the game\n", .{});
        };
    }

    client.createGameVsHuman(map_absolute_path, realtime) catch |err| {
        log.err("Failed to create human game: {s}\n", .{@errorName(err)});
        return;
    };

    _ = client.joinMultiplayerGame(bot_setup, start_port) catch |err| {
        log.err("Human client failed to join the game: {s}\n", .{@errorName(err)});
        return;
    };

    var requested_game_loop: u32 = 0;
    while (true) {
        const obs = if (realtime) try client.getObservation(requested_game_loop) else try client.getObservation(null);

        if (obs.player_result) |_| {
            _ = client.leave() catch |err| {
                log.err("Human unable to leave game {s}\n", .{@errorName(err)});
            };
            break;
        }
        requested_game_loop = obs.observation.?.game_loop.? + step_count;

        if (!realtime) client.step(step_count) catch break;

        _ = step_arena_instance.reset(.retain_capacity);
    }
}

pub fn run(
    user_bot: anytype,
    step_count: u32,
    base_allocator: mem.Allocator,
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

    // Arena which is reset at the end of each step.
    // Do a first allocation to grow the arena in size
    // to 10MB so we hopefully don't need to grow it many
    // times during the game
    var step_arena_instance = std.heap.ArenaAllocator.init(base_allocator);
    defer step_arena_instance.deinit();
    const step_arena = step_arena_instance.allocator();
    _ = try step_arena.alloc(u8, 1024 * 1024 * 10);
    _ = step_arena_instance.reset(.retain_capacity);

    const program_args = readArguments(arena);

    const sc2_base_folder = program_args.sc2_path orelse standard_sc2_base_folder;
    const ladder_game = program_args.ladder_server != null;
    const host: []const u8 = program_args.ladder_server orelse "127.0.0.1";
    const game_port: u16 = program_args.game_port orelse 5001;
    const start_port: u16 = program_args.start_port orelse game_port + 2;

    var sc2_process: ?ChildProcess = null;
    var sc2_paths: Sc2Paths = undefined;

    if (!ladder_game) {
        sc2_paths = getSc2Paths(sc2_base_folder, arena) catch {
            log.err("Couldn't form SC2 paths\n", .{});
            return;
        };
        const sc2_args = [_][]const u8{
            sc2_paths.latest_binary,
            "-listen",
            host,
            "-port",
            try fmt.allocPrint(arena, "{d}", .{game_port}),
            "-dataDir",
            sc2_paths.base_folder,
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
        log.debug("Doing ws connection loop {d}\n", .{attempt});
        client = ws.WebSocketClient.init(host, game_port, arena, step_arena) catch {
            time.sleep(2 * time.ns_per_s);
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
        if (sc2_process) |*sc2| {
            _ = client.quit() catch {
                log.err("Unable to quit the game\n", .{});
                _ = sc2.kill() catch {
                    log.err("Unable to kill the game\n", .{});
                };
            };
        }
    }

    var human_thread: ?std.Thread = null;
    defer {
        if (human_thread) |ht| {
            ht.join();
        }
    }
    const bot_setup: ws.BotSetup = .{ .name = user_bot.name, .race = user_bot.race };

    const player_id: u32 = pid: {
        if (ladder_game) {
            break :pid client.joinMultiplayerGame(bot_setup, start_port) catch |err| {
                log.err("Failed to join ladder game: {s}\n", .{@errorName(err)});
                return;
            };
        } else if (program_args.human_game) {
            const strings_to_concat = [_][]const u8{ sc2_paths.map_folder, program_args.map_file_name, ".SC2Map" };
            const map_absolute_path = try mem.concat(arena, u8, &strings_to_concat);
            std.fs.accessAbsolute(map_absolute_path, .{}) catch {
                log.err("Map file {s} was not found\n", .{map_absolute_path});
                return;
            };

            // Start a separate thread for the human to play
            // the game. That client acts as the game host
            // because it seems only the host can manually
            // control units.

            human_thread = std.Thread.spawn(.{}, runHumanGame, .{
                step_count,
                base_allocator,
                sc2_paths,
                map_absolute_path,
                .{ .name = "Human", .race = program_args.human_race },
                program_args.realtime,
                game_port + 1,
                start_port,
            }) catch |err| {
                log.err("Failed to spawn human game thread: {s}\n", .{@errorName(err)});
                return;
            };

            break :pid client.joinMultiplayerGame(bot_setup, start_port) catch |err| {
                log.err("Failed to join human game with bot: {s}\n", .{@errorName(err)});
                return;
            };
        } else {
            const strings_to_concat = [_][]const u8{ sc2_paths.map_folder, program_args.map_file_name, ".SC2Map" };
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
                program_args.realtime,
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
    var actions = try bot_data.Actions.init(game_data, &client, arena, step_arena);

    var own_units = std.AutoArrayHashMap(u64, bot_data.Unit).init(arena);
    try own_units.ensureTotalCapacity(200);

    var enemy_units = std.AutoArrayHashMap(u64, bot_data.Unit).init(arena);
    try enemy_units.ensureTotalCapacity(200);

    var requested_game_loop: u32 = 0;
    while (true) {
        defer _ = step_arena_instance.reset(.retain_capacity);

        const obs = if (program_args.realtime) try client.getObservation(requested_game_loop) else try client.getObservation(null);

        var bot = try bot_data.Bot.fromProto(&own_units, &enemy_units, obs, game_data, player_id, step_arena);
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
                bot.setUnitAbilitiesFromProto(abilities_proto, step_arena);
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
                    if (unit.unit_type == bot_data.UnitId.CommandCenter or
                        unit.unit_type == bot_data.UnitId.Hatchery or
                        unit.unit_type == bot_data.UnitId.Nexus)
                    {
                        break :sl unit.position;
                    }
                }
                break :sl bot_data.Point2{ .x = 0, .y = 0 };
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
                step_arena,
            );
            bot_data.grids.InfluenceMap.terrain_height = game_info.terrain_height.data;
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

        if (!program_args.realtime) {
            _ = client.step(step_count) catch |err| {
                log.err("Couldn't do a step request: {s}\n", .{@errorName(err)});
                break;
            };
        }

        actions.clear();
    }
}

fn createReplayName(
    allocator: mem.Allocator,
    bot_name: []const u8,
    opponent: []const u8,
    map: []const u8,
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
            actions: *bot_data.Actions,
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
            actions: *bot_data.Actions,
        ) !void {
            _ = game_info;
            _ = self;
            if (bot.game_loop > 500) actions.leaveGame();
        }

        pub fn onResult(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            result: bot_data.Result,
        ) !void {
            _ = bot;
            _ = game_info;
            _ = result;
            _ = self;
        }
    };

    var test_bot = TestBot{ .name = "tester", .race = .terran };

    try run(&test_bot, 2, std.testing.allocator);
}
