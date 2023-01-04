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

const Sc2Paths = struct {
    base_folder: []const u8,
    map_folder: []const u8,
    latest_binary: []const u8,
    working_directory: ?[]const u8,
};

const LocalRunSetup = struct {
    sc2_base_folder: []const u8 = switch (builtin.os.tag) {
        .windows => "C:/Program Files (x86)/StarCraft II/",
        .macos => "/Applications/StarCraft II/",
        .linux => "~/StarCraftII/",
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
            const num = fmt.parseUnsigned(u32, version_num_string, 0) catch continue;
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
    defer {
        if (sc2_process) |_| {
            _ = client.quit();
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
        
        var strings_to_concat = [_][]const u8{sc2_paths.map_folder, program_args.map_file_name, ".SC2Map"};
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

    const game_data_proto = client.getGameData() catch {
        log.err("Error getting game data\n", .{});
        return;
    };

    const game_data = try bot_data.GameData.fromProto(game_data_proto, arena);
    var actions = try bot_data.Actions.init(game_data, arena, fixed_buffer);

    while (true) {

        const obs = client.getObservation();

        if (obs.observation.data == null) {
            log.err("Got an invalid observation\n", .{});
            break;
        }
        
        var bot = try bot_data.Bot.fromProto(obs, game_data, player_id, fixed_buffer);

        if (bot.result) |res| {
            user_bot.onResult(bot, game_info, res);
            if (sc2_process) |_| {
                if (createReplayName(arena, user_bot.name, game_info.enemy_name, game_info.map_name)) |replay_name| {
                    _ = client.saveReplay(replay_name);
                }
                _ = client.leave();
            }
            
            break;
        }

        const all_own_unit_tags = bot.getAllOwnUnitTags(fixed_buffer);
        if (all_own_unit_tags.len > 0) {
            const maybe_abilities_proto = client.getAvailableAbilities(all_own_unit_tags, true);
            if (maybe_abilities_proto) |abilities_proto| {
                bot.setUnitAbilitiesFromProto(abilities_proto, fixed_buffer);
            }
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
                bot.mineral_patches,
                bot.vespene_geysers,
                arena,
                fixed_buffer
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
            
            if (sc2_process) |_| {
                if (createReplayName(arena, user_bot.name, game_info.enemy_name, game_info.map_name)) |replay_name| {
                    _ = client.saveReplay(replay_name);
                }
            }
            
            _ = client.leave();
            user_bot.onResult(bot, game_info, .defeat);
            break;
        }

        const maybe_action_proto = actions.toProto();
        if (maybe_action_proto) |action_proto| {
            try client.sendActions(action_proto);
        }

        if (actions.debugCommandsToProto()) |debug_proto| {
            client.sendDebugRequest(debug_proto);
        }

        _ = client.step(step_count);

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

    try run(&test_bot, 2, std.testing.allocator, .{});
}


test "runner_test_expansion_locations" {
    
    const TestBot = struct {
        const Self = @This();
        name: []const u8,
        race: bot_data.Race,
        locations_expanded_to: usize = 0,
        countdown_start: usize = 0,
        countdown_started: bool = false,
        first_cc_tag: u64 = 0,

        pub fn onStart(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            actions: *bot_data.Actions
        ) void {
            self.first_cc_tag = bot.structures[0].tag;
            std.debug.print("Exp: {d}\n", .{game_info.expansion_locations.len});
            for (game_info.expansion_locations) |exp| {
                std.debug.print("Loc: {d} {d}\n", .{exp.x, exp.y});
            }
            _ = actions;
        }

        pub fn onStep(
            self: *Self,
            bot: bot_data.Bot,
            game_info: bot_data.GameInfo,
            actions: *bot_data.Actions
        ) void {
            
            const maybe_first_cc = bot_data.unit_group.getUnitByTag(bot.structures, self.first_cc_tag);
            if (maybe_first_cc == null) {
                actions.leaveGame();
                return;
            }
            const first_cc = maybe_first_cc.?;
            var current_minerals = bot.minerals;
            if (bot.minerals > 50 and first_cc.isIdle()) {
                actions.train(self.first_cc_tag, bot_data.UnitId.SCV, false);
                current_minerals -= 50;
            }

            if (current_minerals > 400 and !self.countdown_started) {
                const closest_scv = findClosestCollectingUnit(bot.units, first_cc.position);
                actions.build(
                    closest_scv.tag,
                    bot_data.UnitId.CommandCenter,
                    game_info.expansion_locations[self.locations_expanded_to],
                    false,
                );
                self.locations_expanded_to += 1;
                current_minerals -= 400;
            }

            if (!self.countdown_started and self.locations_expanded_to >= game_info.expansion_locations.len) {
                self.countdown_start = bot.game_loop;
                self.countdown_started = true;
            }

            if (self.countdown_started and bot.game_loop - self.countdown_start > 1000) {
                actions.leaveGame();
            }
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

        fn findClosestCollectingUnit(units: []bot_data.Unit, pos: bot_data.Point2) bot_data.Unit {
            var min_distance: f32 = std.math.f32_max;
            var closest_unit: bot_data.Unit = undefined;
            for (units) |unit| {
                if (!unit.isCollecting()) continue;
                const dist_sqrd = unit.position.distanceSquaredTo(pos);
                if (dist_sqrd < min_distance) {
                    min_distance = dist_sqrd;
                    closest_unit = unit;
                }
            }
            return closest_unit;
        }
    };

    var test_bot = TestBot{.name = "tester", .race = .terran};

    try run(&test_bot, 2, std.testing.allocator, .{});
}