const std = @import("std");
const zig_sc2 = @import("zig-sc2");
const bot_data = zig_sc2.bot_data;

const RampValidatorBot = struct {
    const Self = @This();

    io: std.Io,
    name: []const u8 = "ladder-ramp-validator",
    race: bot_data.Race = .terran,
    ramps_valid: bool = false,

    pub fn onStart(self: *Self, ctx: zig_sc2.BotContext) !void {
        const main_ramp = ctx.game_info.getMainBaseRamp();
        const enemy_ramp = ctx.game_info.getEnemyMainBaseRamp();

        const main_valid = try printRamp(self.io, ctx.game_info.map_name, "main", ctx.game_info.start_location, main_ramp);
        const enemy_valid = try printRamp(self.io, ctx.game_info.map_name, "enemy", ctx.game_info.enemy_start_locations[0], enemy_ramp);

        self.ramps_valid = main_valid and enemy_valid;
        ctx.actions.leaveGame();
    }

    pub fn onStep(self: *Self, ctx: zig_sc2.BotContext) !void {
        _ = self;
        ctx.actions.leaveGame();
    }

    pub fn onResult(self: *Self, ctx: zig_sc2.BotContext, result: bot_data.Result) !void {
        _ = self;
        _ = ctx;
        _ = result;
    }
};

fn printRamp(io: std.Io, map_name: []const u8, label: []const u8, start_location: bot_data.Point2, ramp: bot_data.Ramp) !bool {
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const valid =
        ramp.depot_first != null and
        ramp.depot_second != null and
        ramp.barracks_middle != null and
        ramp.barracks_with_addon != null;

    if (valid) {
        try stdout_writer.interface.print("map={s} ramp={s} valid\n", .{ map_name, label });
        return true;
    }

    try stdout_writer.interface.print(
        \\map={s} ramp={s} invalid
        \\  start=({d:.2}, {d:.2}) top=({d:.2}, {d:.2}) bottom=({d:.2}, {d:.2}) points={d}
        \\  depot_first={any} depot_second={any} barracks_middle={any} barracks_with_addon={any}
        \\
    , .{
        map_name,
        label,
        start_location.x,
        start_location.y,
        ramp.top_center.x,
        ramp.top_center.y,
        ramp.bottom_center.x,
        ramp.bottom_center.y,
        ramp.points.len,
        ramp.depot_first,
        ramp.depot_second,
        ramp.barracks_middle,
        ramp.barracks_with_addon,
    });
    try stdout_writer.interface.flush();

    return valid;
}

pub fn main(init: std.process.Init) !void {
    var validator_bot = RampValidatorBot{ .io = init.io };

    _ = try zig_sc2.run(&validator_bot, .{
        .io = init.io,
        .args = init.minimal.args,
        .env_map = init.environ_map,
        .arena = init.arena,
        .gpa = init.gpa,
    });

    if (!validator_bot.ramps_valid) return error.InvalidRamp;
}
