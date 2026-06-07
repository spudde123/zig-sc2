const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const Io = std.Io;
const os = std.os;
const json = std.json;
const builtin = @import("builtin");

const path_from_home_dir = switch (builtin.os.tag) {
    .windows => "\\Documents\\StarCraft II\\stableid.json",
    .macos => "/Library/Application Support/Blizzard/StarCraft II/stableid.json",
    else => @compileError("Unsupported OS"),
};

const titles = [_][]const u8{
    "Abilities",
    "Buffs",
    "Effects",
    "Units",
    "Upgrades",
};

const enum_names = [_][]const u8{
    "AbilityId",
    "BuffId",
    "EffectId",
    "UnitId",
    "UpgradeId",
};

const file_names = [_][]const u8{
    "ability_id.zig",
    "buff_id.zig",
    "effect_id.zig",
    "unit_id.zig",
    "upgrade_id.zig",
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    const var_name = switch (builtin.os.tag) {
        .windows => "USERPROFILE",
        .macos => "HOME",
        else => return error.UnsupportedOs,
    };
    const user_home = init.environ_map.get(var_name) orelse return error.NoUserProfile;
    const to_join = [_][]const u8{ user_home, path_from_home_dir };

    const stableid_file_path = try fs.path.join(arena, &to_join);
    const file_contents = try Io.Dir.cwd().readFileAlloc(init.io, stableid_file_path, arena, .limited(10000 * 1024));

    var tree = try json.parseFromSliceLeaky(json.Value, arena, file_contents, .{});

    // Fix ability data
    const ability_obj = tree.object.get("Abilities").?;
    var key_map = std.StringHashMap(bool).init(arena);
    defer key_map.deinit();

    for (ability_obj.array.items) |*ability| {
        const remap_id = ability.object.get("remapid");
        const name = ability.object.get("name");
        const friendly_name = ability.object.get("friendlyname");
        const button_name = ability.object.get("buttonname");

        var button_name_exists = false;
        if (button_name) |button| {
            if (button.string.len > 0) button_name_exists = true;
        }

        if (!button_name_exists and remap_id == null) {
            try ability.object.put(arena, "name", .{ .string = "" });
            continue;
        }

        if (friendly_name) |friendly| {
            const new_friendly_size = mem.replacementSize(u8, friendly.string, " ", "_");
            const new_friendly_string = try arena.alloc(u8, new_friendly_size);
            _ = mem.replace(u8, friendly.string, " ", "_", new_friendly_string);
            try ability.object.put(arena, "name", .{ .string = new_friendly_string });
        } else {
            const name_string = name.?;
            const button_string = button_name.?;
            const new_name = try mem.concat(arena, u8, &[_][]const u8{ name_string.string, "_", button_string.string });
            try ability.object.put(arena, "name", .{ .string = new_name });
        }

        const updated_name = ability.object.get("name").?;
        if (key_map.contains(updated_name.string)) {
            try ability.object.put(arena, "name", .{ .string = "" });
        } else {
            try key_map.put(updated_name.string, true);
        }
    }

    var i: usize = 0;

    while (i < 5) : (i += 1) {
        const title = titles[i];
        const file_name = file_names[i];
        const enum_name = enum_names[i];
        const file_path = try mem.concat(arena, u8, &[_][]const u8{ "src/ids/", file_name });
        std.debug.print("{s}\n", .{file_path});

        const file = try Io.Dir.cwd().createFile(init.io, file_path, .{});
        defer file.close(init.io);

        var writer = file.writer(init.io, &.{});
        _ = try writer.interface.write("// Generated with util/generate_ids.zig\n");
        try writer.interface.print("pub const {s} = enum(u32) {{\n", .{enum_name});

        const obj = tree.object.get(title).?;
        for (obj.array.items) |item| {
            const id = item.object.get("id").?;
            const name = item.object.get("name").?;

            const gap_size = mem.replacementSize(u8, name.string, "@", "");
            const gap_name = try arena.alloc(u8, gap_size);
            _ = mem.replace(u8, name.string, "@", "", gap_name);

            const no_gap_size = mem.replacementSize(u8, gap_name, " ", "");
            var new_name = try arena.alloc(u8, no_gap_size);
            _ = mem.replace(u8, gap_name, " ", "", new_name);

            if (new_name.len == 0) continue;

            new_name[0] = std.ascii.toUpper(new_name[0]);

            if (std.ascii.isDigit(name.string[0])) {
                try writer.interface.print("    _{s} = {d},\n", .{ new_name, id.integer });
            } else {
                try writer.interface.print("    {s} = {d},\n", .{ new_name, id.integer });
            }
        }
        std.debug.print("{d}\n", .{obj.array.items.len});
        _ = try writer.interface.write("    _,\n};\n");
    }
}
