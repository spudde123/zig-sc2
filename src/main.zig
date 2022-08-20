const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const cp = std.ChildProcess;
const time = std.time;

const ws = @import("client.zig");
const runner = @import("runner.zig");
const bot_data = @import("bot.zig");

const TestBot = struct {

    name: []const u8,
    race: bot_data.Race,

    pub fn onStart(self: *TestBot, bot: bot_data.Bot) void {
        _ = self;
        _ = bot;
    }

    pub fn onStep(self: *TestBot, bot: bot_data.Bot) void {
        _ = bot;
        _ = self;
    }

    pub fn onResult(self: *TestBot, bot: bot_data.Bot, result: bot_data.Result) void {
        _ = bot;
        _ = result;
        _ = self;
    }
};

pub fn main() !void {
    var my_bot = TestBot{.name = "zig-spudde", .race = .terran};

    try runner.run(&my_bot, 2);
}