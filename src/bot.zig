const std = @import("std");
const mem = std.mem;

const Bot = struct {
    own_units: []u8,
    enemy_units: []u8,
    destructables: []u8,

    ramps: []u8,
    vision_blockers: []u8,
    
};

pub fn run(
    user_bot: anytype
) void {
    
    var bot: Bot = undefined;
    var current_step: u64 = 0;
    var result: i32 = 0;
    user_bot.onStart(bot);
    user_bot.onStep(bot, current_step);
    user_bot.onResult(bot, result);
}