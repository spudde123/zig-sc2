const std = @import("std");

const runner = @import("runner.zig");
const bot_data = @import("bot.zig");

const TestBot = struct {

    name: []const u8,
    race: bot_data.Race,

    pub fn onStart(
        self: *TestBot,
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
    }

    pub fn onStep(
        self: *TestBot,
        bot: bot_data.Bot,
        game_info: bot_data.GameInfo,
        actions: *bot_data.Actions
    ) void {
        _ = game_info;
        _ = self;
        if (bot.game_loop > 500) actions.leaveGame();
    }

    pub fn onResult(
        self: *TestBot,
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

pub fn main() !void {
    var my_bot = TestBot{.name = "zig-bot", .race = .terran};

    try runner.run(&my_bot, 2, std.heap.page_allocator, .{});
}