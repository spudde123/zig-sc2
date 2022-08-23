const std = @import("std");

const runner = @import("runner.zig");
const bot_data = @import("bot.zig");

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
        _ = game_info;
        _ = actions;
    }

    pub fn onStep(
        self: *Self,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        
        const first_cc = bot_data.getUnitByTag(bot.structures, self.first_cc_tag).?;
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

pub fn main() !void {
    var my_bot = TestBot{.name = "zig-bot", .race = .terran};

    try runner.run(&my_bot, 2, std.heap.page_allocator, .{});
}