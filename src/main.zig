const std = @import("std");

const runner = @import("runner.zig");
const bot_data = @import("bot.zig");
const unit_group = bot_data.unit_group;

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
        _ = game_info;
        _ = actions;
    }

    pub fn onStep(
        self: *Self,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        
        const maybe_first_cc = unit_group.getUnitByTag(bot.structures, self.first_cc_tag);
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

        if (current_minerals > 100 and unit_group.amountOfType(bot.structures, bot_data.UnitId.SupplyDepot) == 0) {
            const closest_scv = findClosestCollectingUnit(bot.units, first_cc.position);
            const main_base_ramp = game_info.getMainBaseRamp();
            actions.build(
                closest_scv.tag,
                bot_data.UnitId.SupplyDepot,
                main_base_ramp.depot_first.?,
                false,
            );
            current_minerals -= 100;
        }

        if (current_minerals > 100 and unit_group.amountOfType(bot.structures, bot_data.UnitId.SupplyDepot) == 1) {
            const closest_scv = findClosestCollectingUnit(bot.units, first_cc.position);
            const main_base_ramp = game_info.getMainBaseRamp();
            actions.build(
                closest_scv.tag,
                bot_data.UnitId.SupplyDepot,
                main_base_ramp.depot_second.?,
                false,
            );
            current_minerals -= 100;
        }

        if (current_minerals > 150 and unit_group.amountOfType(bot.structures, bot_data.UnitId.SupplyDepot) == 2) {
            const closest_scv = findClosestCollectingUnit(bot.units, first_cc.position);
            const main_base_ramp = game_info.getMainBaseRamp();
            actions.build(
                closest_scv.tag,
                bot_data.UnitId.Barracks,
                main_base_ramp.barracks_middle.?,
                false,
            );
            current_minerals -= 150;
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
            self.locations_expanded_to = @mod(self.locations_expanded_to, game_info.expansion_locations.len);
            current_minerals -= 400;
        }

        drawRamps(game_info, actions);
    }

    fn drawRamps(
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        for (game_info.ramps) |ramp| {
            for (ramp.points) |point| {
                const fx = @intToFloat(f32, point.x);
                const fy = @intToFloat(f32, point.y);
                const fz = game_info.getTerrainZ(.{.x = fx, .y = fy});
                actions.debugTextWorld(
                    "o",
                    .{.x = fx + 0.5, .y = fy + 0.5, .z = fz},
                    .{.r = 0, .g = 255, .b = 0},
                    12
                );
            }

            const z = game_info.getTerrainZ(ramp.top_center);

            if (ramp.depot_first) |depot_first| {
                const draw_loc = depot_first.add(.{.x = 0.5, .y = 0.5});
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x - 1, .y = draw_loc.y - 1, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x - 1, .y = draw_loc.y, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x, .y = draw_loc.y - 1, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x, .y = draw_loc.y, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
            }

            if (ramp.depot_second) |depot_second| {
                const draw_loc = depot_second.add(.{.x = 0.5, .y = 0.5});
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x - 1, .y = draw_loc.y - 1, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x - 1, .y = draw_loc.y, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x, .y = draw_loc.y - 1, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = draw_loc.x, .y = draw_loc.y, .z = z},
                    .{.r = 0, .g = 0, .b = 255},
                    16
                );
            }

            if (ramp.barracks_middle) |rax_loc| {
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x - 1, .y = rax_loc.y - 1, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x - 1, .y = rax_loc.y, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x - 1, .y = rax_loc.y + 1, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x, .y = rax_loc.y - 1, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x, .y = rax_loc.y, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x, .y = rax_loc.y + 1, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x + 1, .y = rax_loc.y - 1, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x + 1, .y = rax_loc.y, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
                actions.debugTextWorld(
                    "o",
                    .{.x = rax_loc.x + 1, .y = rax_loc.y + 1, .z = z},
                    .{.r = 0, .g = 255, .b = 255},
                    16
                );
            }

        }

        for (game_info.vision_blockers) |vb| {
            for (vb.points) |point| {
                const fx = @intToFloat(f32, point.x);
                const fy = @intToFloat(f32, point.y);
                const fz = game_info.getTerrainZ(.{.x = fx, .y = fy});
                actions.debugTextWorld(
                    "o",
                    .{.x = fx + 0.5, .y = fy + 0.5, .z = fz},
                    .{.r = 255, .g = 0, .b = 0},
                    12
                );
            }
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

pub fn main() !void {
    var my_bot = TestBot{.name = "zig-bot", .race = .terran};

    try runner.run(&my_bot, 2, std.heap.page_allocator, .{});
}