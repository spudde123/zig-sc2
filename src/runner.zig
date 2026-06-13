const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const ChildProcess = std.process.Child;
const time = std.time;
const log = std.log;
const Io = std.Io;
const builtin = @import("builtin");

const sc2p = @import("sc2proto.zig");
const ws = @import("client.zig");
pub const bot_data = @import("bot.zig");

pub const BotContext = struct {
    bot: *const bot_data.Bot,
    game_info: *const bot_data.GameInfo,
    actions: *bot_data.Actions,
};

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
    proton,
    steam_compat_data_path,
    replay,
    observed_player,
    observed_bot,
    disable_fog,
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
    // These are necessary when running on Linux using Proton
    // The command is of the form "proton runinprefix SC2.exe"
    // And it requires steam_compat_data_path environment variable to be set
    proton: ?[]const u8 = null,
    steam_compat_data_path: ?[]const u8 = null,
    replay_path: ?[]const u8 = null,
    observed_player_id: ?u32 = null,
    observed_bot_name: ?[]const u8 = null,
    disable_fog: bool = false,
};

/// Which player to observe when watching a replay.
/// A bot name needs to be resolved to a player id
/// through a replay info request once we are connected.
pub const ObservedPlayer = union(enum) {
    player_id: u32,
    bot_name: []const u8,
};

/// Explicit representation of what the runner should do,
/// resolved from the command line arguments.
pub const GameMode = union(enum) {
    ladder: struct {
        opponent_id: ?[]const u8,
    },
    vs_computer: struct {
        computer: ws.ComputerSetup,
        map: []const u8,
    },
    vs_human: struct {
        human_race: sc2p.Race,
        map: []const u8,
    },
    replay: struct {
        path: []const u8,
        observed: ObservedPlayer,
        disable_fog: bool,
    },
};

const Config = struct {
    mode: GameMode,
    realtime: bool,
    host: []const u8,
    game_port: u16,
    start_port: u16,
};

const race_map = std.StaticStringMap(sc2p.Race).initComptime(.{
    .{ "terran", .terran },
    .{ "zerg", .zerg },
    .{ "protoss", .protoss },
    .{ "random", .random },
});

const difficulty_map = std.StaticStringMap(sc2p.AiDifficulty).initComptime(.{
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

const build_map = std.StaticStringMap(sc2p.AiBuild).initComptime(.{
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

fn getStandardSC2Folder(allocator: mem.Allocator, proton: bool, env: *const std.process.Environ.Map) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => "C:/Program Files (x86)/StarCraft II",
        .macos => "/Applications/StarCraft II",
        .linux => l: {
            const home = env.get("HOME") orelse "";

            if (proton) {
                break :l try std.fs.path.join(
                    allocator,
                    &.{
                        home,
                        "Games/Heroic/Prefixes/default/pfx/drive_c/Program Files (x86)/StarCraft II",
                    },
                );
            }
            break :l try std.fs.path.join(
                allocator,
                &.{
                    home,
                    "StarCraftII",
                },
            );
        },
        else => @compileError("OS not supported"),
    };
}

const RunError = error{
    NoConnection,
    NoGameData,
    NoGameInfo,
    FailedToCreateGame,
    FailedToSpawnThread,
    FailedToJoin,
    FailedToStartReplay,
    ConflictingArguments,
    ReplayNotFound,
    BotNotInReplay,
};

const Sc2PathError = error{
    NoVersionFoldersFound,
};

fn getSc2Paths(base_folder: []const u8, allocator: mem.Allocator, io: std.Io, proton: bool) !Sc2Paths {
    const map_concat = [_][]const u8{ base_folder, "/Maps/" };
    const support64_concat = [_][]const u8{ base_folder, "/Support64/" };
    const versions_concat = [_][]const u8{ base_folder, "/Versions/" };

    const versions_path = try mem.concat(allocator, u8, &versions_concat);

    var dir = Io.Dir.openDirAbsolute(io, versions_path, .{ .iterate = true }) catch {
        log.err("Couldn't open versions folder {s}", .{versions_path});
        return Sc2PathError.NoVersionFoldersFound;
    };
    defer dir.close(io);

    var iter = dir.iterate();
    var max_version: u64 = 0;
    while (try iter.next(io)) |version| {
        if (mem.startsWith(u8, version.name, "Base")) {
            const version_num_string = version.name[4..];
            const num = fmt.parseUnsigned(u64, version_num_string, 0) catch continue;
            if (num > max_version) max_version = num;
        }
    }

    if (max_version == 0) return Sc2PathError.NoVersionFoldersFound;

    log.debug("Using game version {d}", .{max_version});
    return Sc2Paths{
        .base_folder = base_folder,
        .map_folder = try mem.concat(allocator, u8, &map_concat),
        .working_directory = switch (builtin.os.tag) {
            .windows => try mem.concat(allocator, u8, &support64_concat),
            .macos => null,
            .linux => if (proton) try mem.concat(allocator, u8, &support64_concat) else null,
            else => @compileError("OS not supported"),
        },
        .latest_binary = switch (builtin.os.tag) {
            .windows => try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64.exe", .{ versions_path, max_version }),
            .macos => try fmt.allocPrint(allocator, "{s}Base{d}/SC2.app/Contents/MacOS/SC2", .{ versions_path, max_version }),
            .linux => l: {
                if (proton) break :l try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64.exe", .{ versions_path, max_version });
                break :l try fmt.allocPrint(allocator, "{s}Base{d}/SC2_x64", .{ versions_path, max_version });
            },
            else => @compileError("OS not supported"),
        },
    };
}

fn readArguments(allocator: mem.Allocator, args: std.process.Args) ProgramArguments {
    var program_args = ProgramArguments{};
    var arg_iter = args.iterateAllocator(allocator) catch {
        log.err("Failed to iterate arguments", .{});
        return program_args;
    };
    defer arg_iter.deinit();
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
            } else if (mem.eql(u8, argument, "--Proton")) {
                current_input_type = InputType.proton;
            } else if (mem.eql(u8, argument, "--SteamCompatDataPath")) {
                current_input_type = InputType.steam_compat_data_path;
            } else if (mem.eql(u8, argument, "--Replay")) {
                current_input_type = InputType.replay;
            } else if (mem.eql(u8, argument, "--ObservedPlayer")) {
                current_input_type = InputType.observed_player;
            } else if (mem.eql(u8, argument, "--ObservedBot")) {
                current_input_type = InputType.observed_bot;
            } else if (mem.eql(u8, argument, "--DisableFog")) {
                current_input_type = InputType.disable_fog;
                program_args.disable_fog = true;
            } else {
                current_input_type = InputType.none;
            }
        } else if (current_input_type != InputType.none) {
            switch (current_input_type) {
                InputType.ladder_server => {
                    program_args.ladder_server = argument;
                },
                InputType.game_port => {
                    program_args.game_port = fmt.parseUnsigned(u16, argument, 0) catch {
                        log.err("Invalid game port {s}", .{argument});
                        continue;
                    };
                },
                InputType.start_port => {
                    program_args.start_port = fmt.parseUnsigned(u16, argument, 0) catch {
                        log.err("Invalid start port {s}", .{argument});
                        continue;
                    };
                },
                InputType.opponent_id => {
                    program_args.opponent_id = argument;
                },
                InputType.computer_difficulty => {
                    if (difficulty_map.get(argument)) |difficulty| {
                        program_args.computer_difficulty = difficulty;
                    } else {
                        log.err("Unknown difficulty {s}", .{argument});
                        log.err("Available difficulties:", .{});
                        for (difficulty_map.keys()) |key| {
                            log.err("{s}", .{key});
                        }
                    }
                },
                InputType.computer_race => {
                    if (race_map.get(argument)) |race| {
                        program_args.computer_race = race;
                    } else {
                        log.err("Unknown race {s}", .{argument});
                        log.err("Available races:", .{});
                        for (race_map.keys()) |key| {
                            log.err("{s}", .{key});
                        }
                    }
                },
                InputType.computer_build => {
                    if (build_map.get(argument)) |build| {
                        program_args.computer_build = build;
                    } else {
                        log.err("Unknown build {s}", .{argument});
                        log.err("Available builds:", .{});
                        for (build_map.keys()) |key| {
                            log.err("{s}", .{key});
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
                        log.err("Unknown race {s}", .{argument});
                        log.err("Available races:", .{});
                        for (race_map.keys()) |key| {
                            log.err("{s}", .{key});
                        }
                    }
                },
                InputType.sc2_path => {
                    program_args.sc2_path = argument;
                },
                InputType.proton => {
                    program_args.proton = argument;
                },
                InputType.steam_compat_data_path => {
                    program_args.steam_compat_data_path = argument;
                },
                InputType.replay => {
                    program_args.replay_path = argument;
                },
                InputType.observed_player => {
                    program_args.observed_player_id = fmt.parseUnsigned(u32, argument, 0) catch {
                        log.err("Invalid observed player id {s}", .{argument});
                        continue;
                    };
                },
                InputType.observed_bot => {
                    program_args.observed_bot_name = argument;
                },
                else => {},
            }
            current_input_type = InputType.none;
        }
    }
    return program_args;
}

/// Resolves the explicit game mode and connection settings
/// from the raw command line arguments.
fn buildConfig(arena: mem.Allocator, io: Io, program_args: ProgramArguments) !Config {
    const mode: GameMode = mode: {
        if (program_args.replay_path != null and (program_args.ladder_server != null or program_args.human_game)) {
            log.err("--Replay can't be combined with --LadderServer or --Human", .{});
            return RunError.ConflictingArguments;
        }

        if (program_args.ladder_server != null) {
            break :mode .{ .ladder = .{ .opponent_id = program_args.opponent_id } };
        }

        if (program_args.replay_path) |path| {
            if (program_args.observed_player_id != null and program_args.observed_bot_name != null) {
                log.err("--ObservedPlayer can't be combined with --ObservedBot", .{});
                return RunError.ConflictingArguments;
            }
            const observed: ObservedPlayer = observed: {
                if (program_args.observed_bot_name) |name| {
                    break :observed .{ .bot_name = name };
                }
                break :observed .{ .player_id = program_args.observed_player_id orelse 1 };
            };
            // Sc2 resolves relative paths against its own replay folder
            // which is rarely what the user means, so resolve the path
            // against our working directory instead
            const absolute_path = Io.Dir.cwd().realPathFileAlloc(io, path, arena) catch {
                log.err("Replay file not found: {s}", .{path});
                return RunError.ReplayNotFound;
            };
            break :mode .{ .replay = .{
                .path = absolute_path,
                .observed = observed,
                .disable_fog = program_args.disable_fog,
            } };
        }

        var map_name = program_args.map_file_name;
        if (!mem.endsWith(u8, map_name, ".SC2Map")) {
            map_name = try mem.concat(arena, u8, &.{ map_name, ".SC2Map" });
        }

        if (program_args.human_game) {
            break :mode .{ .vs_human = .{
                .human_race = program_args.human_race,
                .map = map_name,
            } };
        }

        break :mode .{ .vs_computer = .{
            .computer = .{
                .difficulty = program_args.computer_difficulty,
                .build = program_args.computer_build,
                .race = program_args.computer_race,
            },
            .map = map_name,
        } };
    };

    const game_port: u16 = program_args.game_port orelse 5001;
    return .{
        .mode = mode,
        // Replays don't seem to work in realtime mode
        .realtime = if (mode == .replay) false else program_args.realtime,
        .host = program_args.ladder_server orelse "127.0.0.1",
        .game_port = game_port,
        .start_port = program_args.start_port orelse game_port + 2,
    };
}

fn launchSc2(
    io: Io,
    arena: mem.Allocator,
    sc2_paths: Sc2Paths,
    env: *const std.process.Environ.Map,
    host: []const u8,
    port: u16,
    proton: ?[]const u8,
) !ChildProcess {
    var sc2_args: std.ArrayList([]const u8) = .empty;
    if (proton) |proton_path| {
        try sc2_args.append(arena, proton_path);
        try sc2_args.append(arena, "runinprefix");
    }
    try sc2_args.appendSlice(arena, &.{
        sc2_paths.latest_binary,
        "-listen",
        host,
        "-port",
        try fmt.allocPrint(arena, "{d}", .{port}),
        "-dataDir",
        sc2_paths.base_folder,
    });

    const cwd: ChildProcess.Cwd = if (sc2_paths.working_directory) |path| .{ .path = path } else .{ .inherit = {} };

    return std.process.spawn(io, .{
        .argv = sc2_args.items,
        .cwd = cwd,
        .environ_map = env,
        // On headless linux the game outputs some spam so we discard these
        .stderr = .ignore,
        .stdout = .ignore,
    });
}

const connection_attempts = 20;
const connection_retry_delay_s = 2;

fn connectAndHandshake(
    io: Io,
    host: []const u8,
    port: u16,
    perm_alloc: mem.Allocator,
    step_alloc: mem.Allocator,
) !ws.WebSocketClient {
    var attempt: u32 = 0;
    var client = while (attempt < connection_attempts) : (attempt += 1) {
        log.debug("Doing ws connection loop {d}", .{attempt});
        const client = ws.WebSocketClient.init(io, host, port, perm_alloc, step_alloc) catch {
            try io.sleep(.fromSeconds(connection_retry_delay_s), .awake);
            continue;
        };
        break client;
    } else {
        log.err("Failed to connect to sc2", .{});
        return RunError.NoConnection;
    };
    errdefer client.deinit();

    client.completeHandshake("/sc2api") catch |err| {
        log.err("Failed websocket handshake", .{});
        return err;
    };

    return client;
}

fn runHumanGame(
    io: Io,
    allocator: mem.Allocator,
    step_count: u32,
    sc2_paths: Sc2Paths,
    map_name: []const u8,
    bot_setup: ws.BotSetup,
    realtime: bool,
    game_port: u16,
    start_port: u16,
    proton: ?[]const u8,
    env: *const std.process.Environ.Map,
) !void {
    var arena_instance = std.heap.ArenaAllocator.init(allocator);
    // Arena allocator that is freed at the end of the game
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();

    var step_arena_instance = std.heap.ArenaAllocator.init(allocator);
    defer step_arena_instance.deinit();
    const step_arena = step_arena_instance.allocator();

    const host = "127.0.0.1";

    var sc2_process = try launchSc2(io, arena, sc2_paths, env, host, game_port, proton);

    var client = connectAndHandshake(io, host, game_port, arena, step_arena) catch |err| {
        sc2_process.kill(io);
        return err;
    };
    defer client.deinit();

    defer {
        _ = client.quit() catch {
            log.err("Unable to quit the game", .{});
        };
    }

    client.createGameVsHuman(map_name, realtime) catch |err| {
        log.err("Failed to create human game: {s}", .{@errorName(err)});
        return;
    };

    _ = client.joinMultiplayerGame(bot_setup, start_port) catch |err| {
        log.err("Human client failed to join the game: {s}", .{@errorName(err)});
        return;
    };

    var requested_game_loop: u32 = 0;
    while (true) {
        const obs = if (realtime) try client.getObservation(requested_game_loop) else try client.getObservation(null);

        if (obs.player_result) |_| {
            client.leave() catch |err| {
                log.err("Human unable to leave game {s}", .{@errorName(err)});
            };
            break;
        }
        requested_game_loop = obs.observation.?.game_loop.? + step_count;

        if (!realtime) client.step(step_count) catch break;

        _ = step_arena_instance.reset(.retain_capacity);
    }
}

const RunParams = struct {
    /// Should be greater than 1.
    step_count: u32 = 2,
    arena: *std.heap.ArenaAllocator,
    gpa: mem.Allocator,
    env_map: *const std.process.Environ.Map,
    args: std.process.Args,
    io: std.Io,
};
pub fn run(
    user_bot: anytype,
    params: RunParams,
) !bot_data.Result {
    // Step_count 1 may cause problems from
    // with unit orders not showing up yet on the next frame
    // and so on.
    // Step_count 2 should be good enough
    if (params.step_count < 2) return error.InvalidStepCount;
    // Arena allocator that is freed at the end of the game
    const arena = params.arena.allocator();

    // Arena which is reset at the end of each step.
    // Do a first allocation to grow the arena in size
    // to 10MB so we hopefully don't need to grow it many
    // times during the game
    var step_arena_instance = std.heap.ArenaAllocator.init(params.gpa);
    defer step_arena_instance.deinit();
    const step_arena = step_arena_instance.allocator();
    _ = try step_arena.alloc(u8, 1024 * 1024 * 10);
    _ = step_arena_instance.reset(.retain_capacity);

    var program_args = readArguments(arena, params.args);

    // Allow these to be given also with env vars
    // so tests can be properly run
    var env = try params.env_map.clone(arena);
    if (program_args.proton == null) {
        program_args.proton = env.get("PROTON");
    }
    if (program_args.steam_compat_data_path == null) {
        // Copying the memory because we may be overriding the map
        // value later and it can cause a problem
        if (env.get("STEAM_COMPAT_DATA_PATH")) |scdp| {
            program_args.steam_compat_data_path = try arena.dupe(u8, scdp);
        }
    }
    if (program_args.sc2_path == null) {
        program_args.sc2_path = env.get("SC2");
    }
    const config = try buildConfig(arena, params.io, program_args);

    var sc2_process: ?ChildProcess = null;
    var sc2_paths: Sc2Paths = undefined;

    if (config.mode != .ladder) {
        const sc2_base_folder = program_args.sc2_path orelse try getStandardSC2Folder(arena, program_args.proton != null, &env);
        sc2_paths = try getSc2Paths(sc2_base_folder, arena, params.io, program_args.proton != null);
        if (program_args.steam_compat_data_path) |steam_compat_data_path| {
            try env.put("STEAM_COMPAT_DATA_PATH", steam_compat_data_path);
        }
        sc2_process = try launchSc2(
            params.io,
            arena,
            sc2_paths,
            &env,
            config.host,
            config.game_port,
            program_args.proton,
        );
    }

    var client = connectAndHandshake(params.io, config.host, config.game_port, arena, step_arena) catch |err| {
        if (sc2_process) |*sc2| {
            sc2.kill(params.io);
        }
        return err;
    };

    defer {
        if (sc2_process) |*sc2| {
            // This should close sc2 the game on all platforms
            _ = client.quit() catch {
                log.err("Unable to quit the game", .{});
            };
            // When running with Proton we need to kill the proton process
            // also. Afterwards kill all wine stuff if they are still running
            if (program_args.proton) |proton| {
                _ = sc2.kill(params.io);
                const last_slash = mem.lastIndexOfScalar(u8, proton, '/') orelse 0;
                const proton_folder = proton[0 .. last_slash + 1];
                const wine_server_path = std.fs.path.join(arena, &.{ proton_folder, "files/bin/wineserver" }) catch "wineserver";
                _ = std.process.run(arena, params.io, .{
                    .argv = &[_][]const u8{ wine_server_path, "-k" },
                }) catch e: {
                    break :e std.process.RunResult{
                        .term = .{ .exited = 1 },
                        .stdout = &.{},
                        .stderr = &.{},
                    };
                };
            }
        }
    }

    var human_thread: ?std.Thread = null;
    defer {
        if (human_thread) |ht| {
            ht.join();
        }
    }
    const bot_setup: ws.BotSetup = .{ .name = user_bot.name, .race = user_bot.race };

    const player_id: u32 = switch (config.mode) {
        .ladder => client.joinMultiplayerGame(bot_setup, config.start_port) catch |err| {
            log.err("Failed to join ladder game: {s}", .{@errorName(err)});
            return RunError.FailedToJoin;
        },
        .vs_human => |human| pid: {
            // Start a separate thread for the human to play
            // the game. That client acts as the game host
            // because it seems only the host can manually
            // control units.

            human_thread = std.Thread.spawn(.{}, runHumanGame, .{
                params.io,
                params.gpa,
                params.step_count,
                sc2_paths,
                human.map,
                ws.BotSetup{ .name = "Human", .race = human.human_race },
                config.realtime,
                config.game_port + 1,
                config.start_port,
                program_args.proton,
                &env,
            }) catch |err| {
                log.err("Failed to spawn human game thread: {s}", .{@errorName(err)});
                return RunError.FailedToSpawnThread;
            };

            break :pid client.joinMultiplayerGame(bot_setup, config.start_port) catch |err| {
                log.err("Failed to join human game with bot: {s}", .{@errorName(err)});
                return RunError.FailedToJoin;
            };
        },
        .vs_computer => |comp| client.createGameVsComputerAndJoin(
            bot_setup,
            comp.map,
            comp.computer,
            config.realtime,
        ) catch |err| {
            log.err("Failed to create game: {s}", .{@errorName(err)});
            return RunError.FailedToCreateGame;
        },
        .replay => |replay| pid: {
            const observed_player_id: u32 = switch (replay.observed) {
                .player_id => |id| id,
                .bot_name => |name| try resolveObservedPlayerId(&client, replay.path, name),
            };
            client.startReplay(
                replay.path,
                observed_player_id,
                replay.disable_fog,
                config.realtime,
            ) catch |err| {
                log.err("Failed to start replay: {s}", .{@errorName(err)});
                return RunError.FailedToStartReplay;
            };
            break :pid observed_player_id;
        },
    };

    const is_replay = config.mode == .replay;

    var game_info: bot_data.GameInfo = undefined;

    var first_step_done = false;

    const game_data_proto = client.getGameData() catch |err| {
        log.err("Error getting game data: {s}", .{@errorName(err)});
        return RunError.NoGameData;
    };

    const game_data = try bot_data.GameData.fromProto(game_data_proto, arena);
    var actions = try bot_data.Actions.init(game_data, &client, arena, step_arena);

    var own_units: std.array_hash_map.Auto(u64, bot_data.Unit) = .empty;
    try own_units.ensureTotalCapacity(arena, 200);

    var enemy_units: std.array_hash_map.Auto(u64, bot_data.Unit) = .empty;
    try enemy_units.ensureTotalCapacity(arena, 200);

    var requested_game_loop: u32 = 0;
    while (true) {
        defer _ = step_arena_instance.reset(.retain_capacity);

        const obs = if (config.realtime) try client.getObservation(requested_game_loop) else try client.getObservation(null);

        var bot = try bot_data.Bot.fromProto(&own_units, &enemy_units, obs, game_data, player_id, arena, step_arena);
        // Not sure if the given game loop may be larger than what was requested
        // if the bot takes too long to make the step.
        // Regardless doesn't hurt to sync it
        requested_game_loop = bot.game_loop + params.step_count;

        // In a replay we may not get a player result and instead
        // the status just changes to ended once the replay is over
        const replay_ended = is_replay and client.status == .ended;
        if (bot.result != null or replay_ended) {
            const res: bot_data.Result = bot.result orelse .undecided;
            if (!is_replay and sc2_process != null) {
                if (first_step_done) {
                    if (createReplayName(params.io, arena, user_bot.name, game_info.enemy_name, game_info.map_name)) |replay_name| {
                        _ = client.saveReplay(replay_name) catch |err| {
                            log.err("Unable to save replay: {s}", .{@errorName(err)});
                        };
                    }
                }
                client.leave() catch {
                    log.err("Unable to leave game", .{});
                };
            }
            try user_bot.onResult(.{
                .bot = &bot,
                .game_info = &game_info,
                .actions = &actions,
            }, res);
            return res;
        }

        if (!is_replay) {
            const all_own_unit_tags = bot.units.keys();
            if (all_own_unit_tags.len > 0) {
                if (client.getAvailableAbilities(all_own_unit_tags, false)) |abilities_proto| {
                    bot.setUnitAbilitiesFromProto(abilities_proto, step_arena);
                }
            }
        }

        if (!first_step_done) {
            const game_info_proto = client.getGameInfo() catch {
                log.err("Error getting game info", .{});
                return RunError.NoGameInfo;
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
            game_info.updateGrids(bot);
            try user_bot.onStart(.{
                .bot = &bot,
                .game_info = &game_info,
                .actions = &actions,
            });
            first_step_done = true;
        } else game_info.updateGrids(bot);

        // Set enemy race to the observed race when we can
        if (game_info.enemy_race == .random and bot.enemy_units.count() > 0) {
            const enemy_unit = bot.enemy_units.values()[0];
            if (game_data.units.get(enemy_unit.unit_type)) |unit_data| {
                game_info.enemy_race = unit_data.race;
            } else {
                log.debug("Unit {d} was not found in data", .{enemy_unit.unit_type});
            }
        }

        try user_bot.onStep(.{
            .bot = &bot,
            .game_info = &game_info,
            .actions = &actions,
        });

        if (actions.leave_game) {
            const res: bot_data.Result = if (is_replay) .undecided else .defeat;
            if (!is_replay) {
                if (sc2_process) |_| {
                    if (createReplayName(params.io, arena, user_bot.name, game_info.enemy_name, game_info.map_name)) |replay_name| {
                        _ = client.saveReplay(replay_name) catch |err| {
                            log.err("Unable to save replay: {s}", .{@errorName(err)});
                        };
                    }
                }

                client.leave() catch {
                    log.err("Unable to leave game", .{});
                };
            }
            try user_bot.onResult(.{
                .bot = &bot,
                .game_info = &game_info,
                .actions = &actions,
            }, res);
            return res;
        }

        if (!is_replay) {
            if (actions.toProto()) |action_proto| {
                client.sendActions(action_proto) catch {
                    log.err("Error sending actions at game loop {d}", .{bot.game_loop});
                };
            }
            if (actions.debugCommandsToProto()) |debug_proto| {
                // Ignore errors from debug request, as it can silently fail without a problem
                client.sendDebugRequest(debug_proto) catch {};
            }
        }
        if (!config.realtime) {
            try client.step(params.step_count);
        }
        actions.clear();
    }
}

/// Asks sc2 for info about the replay and finds the player id
/// of the player with the given name. Errors out if no such
/// player is playing in the replay.
fn resolveObservedPlayerId(
    client: *ws.WebSocketClient,
    replay_path: []const u8,
    bot_name: []const u8,
) !u32 {
    const replay_info = client.getReplayInfo(replay_path) catch |err| {
        log.err("Failed to get replay info: {s}", .{@errorName(err)});
        return RunError.FailedToStartReplay;
    };

    const players = replay_info.player_info orelse {
        log.err("Replay info contained no players", .{});
        return RunError.BotNotInReplay;
    };

    for (players) |player_extra| {
        const player = player_extra.player_info orelse continue;
        const player_name = player.player_name orelse continue;
        if (mem.eql(u8, player_name, bot_name)) {
            return player.player_id orelse continue;
        }
    }

    log.err("Bot {s} is not playing in the replay. Players in the replay:", .{bot_name});
    for (players) |player_extra| {
        const player = player_extra.player_info orelse continue;
        log.err("{d}: {s}", .{ player.player_id orelse 0, player.player_name orelse "Unknown" });
    }
    return RunError.BotNotInReplay;
}

fn createReplayName(
    io: Io,
    allocator: mem.Allocator,
    bot_name: []const u8,
    opponent: []const u8,
    map: []const u8,
) ?[]const u8 {
    const no_gap_bot_size = mem.replacementSize(u8, bot_name, " ", "");
    const new_bot_name = allocator.alloc(u8, no_gap_bot_size) catch return null;
    _ = mem.replace(u8, bot_name, " ", "", new_bot_name);

    const no_gap_opp_size = mem.replacementSize(u8, opponent, " ", "");
    const new_opponent_name = allocator.alloc(u8, no_gap_opp_size) catch return null;
    _ = mem.replace(u8, opponent, " ", "", new_opponent_name);

    const no_gap_map_size = mem.replacementSize(u8, map, " ", "");
    const new_map_name = allocator.alloc(u8, no_gap_map_size) catch return null;
    _ = mem.replace(u8, map, " ", "", new_map_name);

    const replay_name = fmt.allocPrint(allocator, "./replays/{s}_{s}_{s}_{d}.SC2Replay", .{
        new_bot_name,
        new_opponent_name,
        new_map_name,
        Io.Timestamp.now(io, .awake).toSeconds(),
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
            ctx: BotContext,
        ) !void {
            _ = self;
            const enemy_start_location = ctx.game_info.enemy_start_locations[0];
            const units = ctx.bot.units.values();

            for (units) |unit| {
                if (unit.unit_type == bot_data.UnitId.SCV) {
                    ctx.actions.attackPosition(unit.tag, enemy_start_location, false);
                }
            }
            ctx.actions.chat(.broadcast, "Testing all chat!");
            ctx.actions.chat(.team, "Testing team chat!");
        }

        pub fn onStep(
            self: *Self,
            ctx: BotContext,
        ) !void {
            _ = self;
            if (ctx.bot.game_loop > 500) ctx.actions.leaveGame();
        }

        pub fn onResult(
            self: *Self,
            ctx: BotContext,
            result: bot_data.Result,
        ) !void {
            try std.testing.expectEqual(.defeat, result);
            _ = ctx;
            _ = self;
        }
    };

    var test_bot = TestBot{ .name = "tester", .race = .terran };

    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    const arena = arena_instance.allocator();
    defer arena_instance.deinit();
    var env_map = try std.testing.environ.createMap(arena);

    try std.testing.expect(.defeat == try run(
        &test_bot,
        .{
            .step_count = 2,
            .gpa = std.testing.allocator,
            .arena = &arena_instance,
            .env_map = &env_map,
            .args = undefined,
            .io = std.testing.io,
        },
    ));
}
