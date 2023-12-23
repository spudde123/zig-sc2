const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

const f32_max = math.floatMax(f32);

pub const GridSize = struct {
    w: usize,
    h: usize,
};

pub const Rectangle = struct {
    // Left bottom
    p0: GridPoint,
    // Top right
    p1: GridPoint,

    pub fn width(self: Rectangle) i32 {
        return self.p1.x - self.p0.x + 1;
    }

    pub fn height(self: Rectangle) i32 {
        return self.p1.y - self.p0.y + 1;
    }

    pub fn pointIsInside(self: Rectangle, point: GridPoint) bool {
        return (point.x >= self.p0.x and point.x <= self.p1.x and point.y >= self.p0.y and point.y <= self.p1.y);
    }
};

pub const GridPoint = struct {
    x: i32,
    y: i32,
};

pub const Circle = struct {
    center: Point2,
    r: f32,

    pub fn isInside(self: Circle, point: Point2) bool {
        return self.center.distanceSquaredTo(point) < self.r * self.r;
    }
};

pub const Point2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn distanceTo(self: Point2, other: Point2) f32 {
        const x = self.x - other.x;
        const y = self.y - other.y;
        return math.sqrt(x * x + y * y);
    }

    pub fn distanceSquaredTo(self: Point2, other: Point2) f32 {
        const x = self.x - other.x;
        const y = self.y - other.y;
        return x * x + y * y;
    }

    pub fn towards(self: Point2, other: Point2, distance: f32) Point2 {
        const d = self.distanceTo(other);
        if (d == 0) return self;

        return .{
            .x = self.x + (other.x - self.x) / d * distance,
            .y = self.y + (other.y - self.y) / d * distance,
        };
    }

    pub fn length(self: Point2) f32 {
        return math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Point2) Point2 {
        const l = self.length();
        return .{
            .x = self.x / l,
            .y = self.y / l,
        };
    }

    pub fn add(self: Point2, other: Point2) Point2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn sub(self: Point2, other: Point2) Point2 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    /// Angle in radians
    pub fn rotate(self: Point2, angle: f32) Point2 {
        const cos = math.cos(angle);
        const sin = math.sin(angle);
        return .{
            .x = cos * self.x - sin * self.y,
            .y = sin * self.x + cos * self.y,
        };
    }

    pub fn multiply(self: Point2, multiplier: f32) Point2 {
        return .{
            .x = self.x * multiplier,
            .y = self.y * multiplier,
        };
    }

    pub fn dot(self: Point2, other: Point2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn floor(self: Point2) Point2 {
        return .{
            .x = math.floor(self.x),
            .y = math.floor(self.y),
        };
    }

    pub fn ceil(self: Point2) Point2 {
        return .{
            .x = math.ceil(self.x),
            .y = math.ceil(self.y),
        };
    }

    pub fn octileDistance(self: Point2, other: Point2) f32 {
        const x_diff = math.fabs(self.x - other.x);
        const y_diff = math.fabs(self.y - other.y);
        return @max(x_diff, y_diff) + (math.sqrt2 - 1) * @min(x_diff, y_diff);
    }

    pub fn findClosestPoint(self: Point2, points: []const Point2) ?Point2 {
        var min_distance: f32 = f32_max;
        var closest_point: ?Point2 = null;
        for (points) |point| {
            const dist_sqrd = self.distanceSquaredTo(point);
            if (dist_sqrd < min_distance) {
                min_distance = dist_sqrd;
                closest_point = point;
            }
        }
        return closest_point;
    }

    pub fn findFurthestPoint(self: Point2, points: []const Point2) ?Point2 {
        var max_distance: f32 = 0;
        var furthest_point: ?Point2 = null;
        for (points) |point| {
            const dist_sqrd = self.distanceSquaredTo(point);
            if (dist_sqrd > max_distance) {
                max_distance = dist_sqrd;
                furthest_point = point;
            }
        }
        return furthest_point;
    }
};

pub const Point3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn fromPoint2(p: Point2, z: f32) Point3 {
        return .{
            .x = p.x,
            .y = p.y,
            .z = z,
        };
    }
};

pub const Grid = struct {
    data: []u8,
    w: usize,
    h: usize,

    pub fn getValue(self: Grid, point: Point2) u8 {
        const x: usize = @as(usize, @intFromFloat(math.floor(point.x)));
        const y: usize = @as(usize, @intFromFloat(math.floor(point.y)));

        assert(x >= 0 and x < self.w);
        assert(y >= 0 and y < self.h);

        return self.data[x + y * self.w];
    }

    pub fn setValues(self: *Grid, indices: []const usize, value: u8) void {
        for (indices) |index| {
            self.data[index] = value;
        }
    }

    pub fn allEqual(self: Grid, indices: []const usize, value: u8) bool {
        for (indices) |index| {
            if (self.data[index] != value) return false;
        }
        return true;
    }

    pub fn count(self: Grid, indices: []const usize) u64 {
        var total: u64 = 0;
        for (indices) |index| {
            total += @as(u64, self.data[index]);
        }
        return total;
    }

    pub fn pointToIndex(self: Grid, point: Point2) usize {
        const x: usize = @as(usize, @intFromFloat(math.floor(point.x)));
        const y: usize = @as(usize, @intFromFloat(math.floor(point.y)));
        return x + y * self.w;
    }

    pub fn indexToPoint(self: Grid, index: usize) Point2 {
        const x = @as(f32, @floatFromInt(@mod(index, self.w)));
        const y = @as(f32, @floatFromInt(@divFloor(index, self.w)));
        return .{
            .x = x,
            .y = y,
        };
    }
};

/// Tries to find the cliff edges reapers can path through.
/// Not tested on all ladder maps but looks to be working..
/// Berlingrad for example has a platform with a unusual shape
/// in the pathing and terrain height arrays
pub fn findClimbablePoints(allocator: mem.Allocator, pathing: Grid, terrain: Grid) ![]usize {
    var list = std.ArrayList(usize).init(allocator);
    const w = pathing.w;
    const h = pathing.h;
    const level_diff = 16;

    for (pathing.data, 0..) |val, i| {
        const x = @mod(i, w);
        const y = i / w;
        // Edges of the map are pointless regardless
        // and we avoid the need for checking index validity later
        if (x < 2 or y < 2 or x > w - 3 or y > h - 3 or val > 0) continue;

        const cur_terrain = terrain.data[x + y * w];

        // First looking at vertical or horizontal jumps
        const up_val = pathing.data[x + (y - 1) * w];
        const up_terrain = terrain.data[x + (y - 1) * w];

        const down_val = pathing.data[x + (y + 1) * w];
        const down_terrain = terrain.data[x + (y + 1) * w];
        const vert_diff = if (up_terrain > down_terrain) up_terrain - down_terrain else down_terrain - up_terrain;

        const left_val = pathing.data[x - 1 + y * w];
        const left_terrain = terrain.data[x - 1 + y * w];

        const right_val = pathing.data[x + 1 + y * w];
        const right_terrain = terrain.data[x + 1 + y * w];
        const horiz_diff = if (left_terrain > right_terrain) left_terrain - right_terrain else right_terrain - left_terrain;

        if (up_val == 1 and down_val == 1 and vert_diff == level_diff) try list.append(i);
        if (left_val == 1 and right_val == 1 and horiz_diff == level_diff) try list.append(i);

        // And then diagonal jumps
        const diag_moves = [_]usize{ w + 1, w - 1 };
        for (diag_moves) |diag_move| {
            const val1 = pathing.data[i - 2 * diag_move];
            const val2 = pathing.data[i - diag_move];
            const val3 = pathing.data[i + diag_move];
            const val4 = pathing.data[i + 2 * diag_move];

            const terrain2 = terrain.data[i - diag_move];
            const terrain3 = terrain.data[i + diag_move];
            const total_diff = if (terrain2 > terrain3) terrain2 - terrain3 else terrain3 - terrain2;
            const diff2 = if (cur_terrain > terrain2) cur_terrain - terrain2 else terrain2 - cur_terrain;
            const diff3 = if (cur_terrain > terrain3) cur_terrain - terrain3 else terrain3 - cur_terrain;

            const terrain_valid_double = total_diff == 2 * level_diff and diff2 == level_diff and diff3 == level_diff;
            const pathing_valid_double = (val2 > 0 and val4 > 0) or (val1 > 0 and val3 > 0);

            if (terrain_valid_double and pathing_valid_double) {
                try list.append(i - diag_move);
                try list.append(i);
                try list.append(i + diag_move);
            }

            if (total_diff == level_diff and val2 == 1 and val3 == 1) {
                try list.append(i);
            }
        }
    }

    return list.toOwnedSlice() catch &[_]usize{};
}

pub fn createReaperGrid(allocator: mem.Allocator, pathing_grid: Grid, climbable_points: []const usize) !Grid {
    var data = try allocator.dupe(u8, pathing_grid.data);

    for (climbable_points) |index| {
        data[index] = 1;
    }
    return .{
        .data = data,
        .w = pathing_grid.w,
        .h = pathing_grid.h,
    };
}

pub fn updateReaperGrid(reaper_grid: Grid, pathing_grid: Grid, climbable_points: []const usize) void {
    @memcpy(reaper_grid.data, pathing_grid.data);
    for (climbable_points) |index| {
        reaper_grid.data[index] = 1;
    }
}

pub fn createAirGrid(allocator: mem.Allocator, map_width: usize, map_height: usize, playable_area: Rectangle) !Grid {
    const start_x = @as(usize, @intCast(playable_area.p0.x));
    const end_x = @as(usize, @intCast(playable_area.p1.x));
    const start_y = @as(usize, @intCast(playable_area.p0.y));
    const end_y = @as(usize, @intCast(playable_area.p1.y));

    var data = try allocator.alloc(u8, map_width * map_height);

    var y: usize = 0;
    while (y < map_height) : (y += 1) {
        var x: usize = 0;
        while (x < map_width) : (x += 1) {
            const index = x + map_width * y;
            const playable = x >= start_x and x <= end_x and y >= start_y and y <= end_y;
            data[index] = if (playable) 1 else 0;
        }
    }
    return .{ .data = data, .w = map_width, .h = map_height };
}

pub const PathfindResult = struct {
    path_len: usize,
    next_point: Point2,
};

pub const InfluenceMap = struct {
    grid: []f32 = &[_]f32{},
    w: usize = 0,
    h: usize = 0,

    const sqrt2 = math.sqrt2;

    // This needs to be set to the proper terrain height slice
    // before calling any pathfinding functions
    pub var terrain_height: []const u8 = &[_]u8{};

    pub const DecayTag = enum {
        none,
        linear,
    };

    pub const Decay = union(DecayTag) {
        none: void,
        // Linear float should be the value we should decay to at the edge of circle
        linear: f32,
    };

    const BoundingRect = struct {
        min_x: usize,
        max_x: usize,
        min_y: usize,
        max_y: usize,
    };

    pub fn fromGrid(allocator: mem.Allocator, base_grid: Grid) !InfluenceMap {
        var grid = try allocator.alloc(f32, base_grid.data.len);
        for (base_grid.data, 0..) |val, i| {
            grid[i] = if (val > 0) 1 else f32_max;
        }
        return .{
            .grid = grid,
            .w = base_grid.w,
            .h = base_grid.h,
        };
    }

    pub fn reset(self: *InfluenceMap, base_grid: Grid) void {
        for (base_grid.data, 0..) |val, i| {
            self.grid[i] = if (val > 0) 1 else f32_max;
        }
    }

    pub fn deinit(self: *InfluenceMap, allocator: mem.Allocator) void {
        // Checking this because in bot code the influence map
        // struct may be around as a field for example
        // but it can only really be initialized on game start
        // with proper data
        if (self.grid.len > 0) allocator.free(self.grid);
    }

    fn getCircleBoundingRect(self: InfluenceMap, center: Point2, radius: f32) BoundingRect {
        const f32_w = @as(f32, @floatFromInt(self.w - 1));
        const f32_h = @as(f32, @floatFromInt(self.h - 1));
        const min_x = @as(usize, @intFromFloat(@max(center.x - radius, 0)));
        const max_x = @as(usize, @intFromFloat(@min(center.x + radius, f32_w)));
        const min_y = @as(usize, @intFromFloat(@max(center.y - radius, 0)));
        const max_y = @as(usize, @intFromFloat(@min(center.y + radius, f32_h)));
        return .{
            .min_x = min_x,
            .max_x = max_x,
            .min_y = min_y,
            .max_y = max_y,
        };
    }

    pub fn addInfluence(self: *InfluenceMap, center: Point2, radius: f32, amount: f32, decay: Decay) void {
        const bounding_rect = self.getCircleBoundingRect(center, radius);
        const r_sqrd = radius * radius;

        var y = bounding_rect.min_y;
        while (y <= bounding_rect.max_y) : (y += 1) {
            var x = bounding_rect.min_x;
            while (x <= bounding_rect.max_x) : (x += 1) {
                const index = x + self.w * y;
                // If cell is not pathable let's not change it
                if (self.grid[index] == f32_max) continue;

                const point = self.indexToPoint(index).add(.{ .x = 0.5, .y = 0.5 });
                const dist_sqrd = point.distanceSquaredTo(center);
                if (dist_sqrd < r_sqrd) {
                    switch (decay) {
                        .none => self.grid[index] += amount,
                        .linear => |end_amount| {
                            const dist = math.sqrt(dist_sqrd);
                            const t = dist / radius;
                            self.grid[index] += (1 - t) * amount + t * end_amount;
                        },
                    }
                    self.grid[index] = @max(1, self.grid[index]);
                }
            }
        }
    }

    pub fn addInfluenceHollow(self: *InfluenceMap, center: Point2, radius: f32, hollow_radius: f32, amount: f32, decay: Decay) void {
        self.addInfluence(center, radius, amount, decay);
        switch (decay) {
            .none => self.addInfluence(center, hollow_radius, -amount, .none),
            .linear => |end_amount| {
                const t = hollow_radius / radius;
                const hollow_amount = (1 - t) * amount + t * end_amount;
                self.addInfluence(center, hollow_radius, -amount, .{ .linear = -hollow_amount });
            },
        }
    }

    pub fn addInfluenceCreep(self: *InfluenceMap, creep: Grid, amount: f32) void {
        for (creep.data, 0..) |val, i| {
            if (val > 0) self.grid[i] += amount;
        }
    }

    pub fn isAreaSafe(self: InfluenceMap, pos: Point2, radius: f32, threshold: f32) bool {
        const bounding_rect = self.getCircleBoundingRect(pos, radius);

        const r_sqrd = radius * radius;

        var y = bounding_rect.min_y;
        while (y <= bounding_rect.max_y) : (y += 1) {
            var x = bounding_rect.min_x;
            while (x <= bounding_rect.max_x) : (x += 1) {
                const index = x + self.w * y;
                const point = self.indexToPoint(index).add(.{ .x = 0.5, .y = 0.5 });
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and self.grid[index] < f32_max and self.grid[index] >= threshold) {
                    return false;
                }
            }
        }

        return true;
    }

    pub fn findClosestSafeSpot(self: InfluenceMap, pos: Point2, radius: f32) ?Point2 {
        const bounding_rect = self.getCircleBoundingRect(pos, radius);
        const r_sqrd = radius * radius;

        var best_val: f32 = f32_max;
        var best_dist: f32 = f32_max;
        var best_point: ?Point2 = null;

        var y = bounding_rect.min_y;
        while (y <= bounding_rect.max_y) : (y += 1) {
            var x = bounding_rect.min_x;
            while (x <= bounding_rect.max_x) : (x += 1) {
                const index = x + self.w * y;
                const point = self.indexToPoint(index).add(.{ .x = 0.5, .y = 0.5 });
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and self.grid[index] <= best_val and self.grid[index] < f32_max and dist_sqrd < best_dist) {
                    best_val = self.grid[index];
                    best_dist = dist_sqrd;
                    best_point = point;
                }
            }
        }

        return best_point;
    }

    const Node = struct {
        index: usize,
        path_len: usize,
        cost: f32,
        heuristic: f32,
    };

    const Neighbor = struct {
        index: usize,
        movement_cost: f32,
    };

    const CameFrom = struct {
        prev: usize,
        path_len: usize,
        cost: f32,
    };

    /// First tries to find a pathable point on the same height
    /// as the asked point. After that accepts any spot
    /// that is pathable
    fn findClosestValidPoint(self: InfluenceMap, pos: Point2) ?Point2 {
        // Terrain height has to be set from outside
        // to the correct slice
        assert(terrain_height.len > 0);
        const radius = 6;
        const bounding_rect = self.getCircleBoundingRect(pos, radius);

        const r_sqrd = radius * radius;

        var best_dist: f32 = f32_max;
        var best_point: ?Point2 = null;

        const height_at_start = terrain_height[self.pointToIndex(pos)];

        var y = bounding_rect.min_y;
        while (y <= bounding_rect.max_y) : (y += 1) {
            var x = bounding_rect.min_x;
            while (x <= bounding_rect.max_x) : (x += 1) {
                const index = x + self.w * y;
                const point = self.indexToPoint(index);

                const height = terrain_height[index];
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and height == height_at_start and self.grid[index] < f32_max and dist_sqrd < best_dist) {
                    best_dist = dist_sqrd;
                    best_point = point;
                }
            }
        }

        if (best_point) |p| return p;

        y = bounding_rect.min_y;
        while (y <= bounding_rect.max_y) : (y += 1) {
            var x = bounding_rect.min_x;
            while (x <= bounding_rect.max_x) : (x += 1) {
                const index = x + self.w * y;
                const point = self.indexToPoint(index);
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and self.grid[index] < f32_max and dist_sqrd < best_dist) {
                    best_dist = dist_sqrd;
                    best_point = point;
                }
            }
        }
        return best_point;
    }

    pub fn validateEndPoint(self: InfluenceMap, pos: Point2) ?Point2 {
        const index = self.pointToIndex(pos);
        if (self.grid[index] < f32_max) return pos;

        return self.findClosestValidPoint(pos);
    }

    /// Returns just the path length and the direction, which is probably in practice what we mostly need
    /// during a game before we do another call the next step
    pub fn pathfindDirection(self: InfluenceMap, allocator: mem.Allocator, start: Point2, goal: Point2, large_unit: bool) ?PathfindResult {
        const validated_start = self.validateEndPoint(start) orelse return null;
        const validated_goal = self.validateEndPoint(goal) orelse return null;

        var came_from = self.runPathfind(allocator, validated_start, validated_goal, large_unit) catch return null;
        defer came_from.deinit();

        const goal_index = self.pointToIndex(validated_goal);
        var cur = came_from.get(goal_index);
        if (cur == null) return null;

        const path_len = cur.?.path_len;
        const point_to_take = 5;

        if (path_len <= point_to_take) {
            return .{
                .path_len = path_len,
                .next_point = validated_goal.add(.{ .x = 0.5, .y = 0.5 }),
            };
        }
        // Give the 5th point from the beginning as direction
        var i: usize = path_len;
        while (i > point_to_take) : (i -= 1) {
            cur = came_from.get(cur.?.prev);
        }

        return .{
            .path_len = path_len,
            .next_point = self.indexToPoint(cur.?.prev).add(.{ .x = 0.5, .y = 0.5 }),
        };
    }

    /// Returns the entire path we took from start to goal. Caller needs to free the slice, or just
    /// use an arena or a fixed buffer for the step
    pub fn pathfindPath(self: InfluenceMap, allocator: mem.Allocator, start: Point2, goal: Point2, large_unit: bool) ?[]Point2 {
        const validated_start = self.validateEndPoint(start) orelse return null;
        const validated_goal = self.validateEndPoint(goal) orelse return null;

        var came_from = self.runPathfind(allocator, validated_start, validated_goal, large_unit) catch return null;
        defer came_from.deinit();

        const goal_index = self.pointToIndex(validated_goal);
        var cur = came_from.get(goal_index);
        // No path
        if (cur == null) return null;

        var index = cur.?.path_len;
        var res = allocator.alloc(Point2, index) catch return null;

        while (cur) |node| {
            res[index - 1] = self.indexToPoint(node.prev).add(.{ .x = 0.5, .y = 0.5 });
            if (index == 1) break;
            cur = came_from.get(node.prev);
            index -= 1;
        }

        return res;
    }

    fn heuristicOrder(context: void, a: Node, b: Node) math.Order {
        _ = context;
        return math.order(a.heuristic, b.heuristic);
    }

    fn runPathfind(self: InfluenceMap, allocator: mem.Allocator, start: Point2, goal: Point2, large_unit: bool) !std.AutoHashMap(usize, CameFrom) {
        const orig_size = 256;

        var queue = std.PriorityQueue(Node, void, heuristicOrder).init(allocator, {});
        defer queue.deinit();
        try queue.ensureTotalCapacity(orig_size);

        const start_floor = start.floor();
        const start_index = self.pointToIndex(start);
        const goal_floor = goal.floor();
        const goal_index = self.pointToIndex(goal);

        try queue.add(.{
            .index = start_index,
            .path_len = 0,
            .cost = 0,
            .heuristic = start_floor.octileDistance(goal_floor),
        });

        const grid = self.grid;
        const w = self.w;

        var neighbors = std.BoundedArray(Neighbor, 8){};

        var closed = try std.DynamicBitSet.initEmpty(allocator, self.w * self.h);
        defer closed.deinit();

        var came_from = std.AutoHashMap(usize, CameFrom).init(allocator);
        try came_from.ensureTotalCapacity(orig_size);

        while (queue.removeOrNull()) |node| {
            if (node.index == goal_index) break;

            const index = node.index;
            // If this is a node that was already visited with a lower cost
            // This is still in the priority queue because we don't
            // update the existing node but add a new one with a higher priority
            if (closed.isSet(index)) continue;
            closed.set(index);

            // We are assuming that we won't go out of bounds because in ingame grids the playable area is always only a portion
            // in the middle and it's surrounded by a lot of unpathable cells

            const valid1 = grid[index - w - 1] < f32_max and grid[index - w] < f32_max and grid[index - 1] < f32_max;
            if (valid1) neighbors.appendAssumeCapacity(.{ .index = index - w - 1, .movement_cost = sqrt2 });

            const valid2 = !large_unit or grid[index - w - 1] < f32_max or grid[index - w + 1] < f32_max;
            if (grid[index - w] < f32_max and valid2) neighbors.appendAssumeCapacity(.{ .index = index - w, .movement_cost = 1 });

            const valid3 = grid[index - w + 1] < f32_max and grid[index - w] < f32_max and grid[index + 1] < f32_max;
            if (valid3) neighbors.appendAssumeCapacity(.{ .index = index - w + 1, .movement_cost = sqrt2 });

            const valid4 = !large_unit or grid[index - w - 1] < f32_max or grid[index + w - 1] < f32_max;
            if (grid[index - 1] < f32_max and valid4) neighbors.appendAssumeCapacity(.{ .index = index - 1, .movement_cost = 1 });

            const valid5 = !large_unit or grid[index - w + 1] < f32_max or grid[index + w + 1] < f32_max;
            if (grid[index + 1] < f32_max and valid5) neighbors.appendAssumeCapacity(.{ .index = index + 1, .movement_cost = 1 });

            const valid6 = grid[index + w - 1] < f32_max and grid[index + w] < f32_max and grid[index - 1] < f32_max;
            if (valid6) neighbors.appendAssumeCapacity(.{ .index = index + w - 1, .movement_cost = sqrt2 });

            const valid7 = !large_unit or grid[index + w - 1] < f32_max or grid[index + w + 1] < f32_max;
            if (grid[index + w] < f32_max and valid7) neighbors.appendAssumeCapacity(.{ .index = index + w, .movement_cost = 1 });

            const valid8 = grid[index + w + 1] < f32_max and grid[index + w] < f32_max and grid[index + 1] < f32_max;
            if (valid8) neighbors.appendAssumeCapacity(.{ .index = index + w + 1, .movement_cost = sqrt2 });

            for (neighbors.constSlice()) |nbr| {
                if (closed.isSet(nbr.index)) continue;

                const nbr_cost = node.cost + nbr.movement_cost * grid[nbr.index];

                if (came_from.get(nbr.index)) |prev| {
                    if (nbr_cost >= prev.cost) continue;
                }

                // We just add the updated node to the queue with a higher
                // priority and don't update the old one because the
                // current std lib implementation for update is a bit strange

                const nbr_point = self.indexToPoint(nbr.index);
                const estimated_cost = nbr_cost + nbr_point.octileDistance(goal_floor);

                try came_from.put(nbr.index, .{ .prev = index, .path_len = node.path_len + 1, .cost = nbr_cost });
                try queue.add(.{
                    .index = nbr.index,
                    .path_len = node.path_len + 1,
                    .cost = nbr_cost,
                    .heuristic = estimated_cost,
                });
            }

            neighbors.resize(0) catch unreachable;
        }

        return came_from;
    }

    pub fn pointToIndex(self: InfluenceMap, point: Point2) usize {
        const x: usize = @as(usize, @intFromFloat(math.floor(point.x)));
        const y: usize = @as(usize, @intFromFloat(math.floor(point.y)));
        return x + y * self.w;
    }

    pub fn indexToPoint(self: InfluenceMap, index: usize) Point2 {
        const x = @as(f32, @floatFromInt(@mod(index, self.w)));
        const y = @as(f32, @floatFromInt(@divFloor(index, self.w)));
        return .{
            .x = x,
            .y = y,
        };
    }
};

test "test_pf_basic" {
    // Let's make a grid with unpathable cells on the edge because
    // that's how the grids ingame look.
    const size = 12;

    var allocator = std.testing.allocator;
    var data = try allocator.alloc(u8, size * size);
    defer allocator.free(data);

    @memset(data, 0);
    var row: usize = 1;
    while (row < size - 1) : (row += 1) {
        @memset(data[1 + row * size .. (row + 1) * size - 1], 1);
    }
    var grid = Grid{ .data = data, .w = size, .h = size };

    var terrain_data = try allocator.alloc(u8, size * size);
    defer allocator.free(terrain_data);

    @memset(terrain_data, 10);
    InfluenceMap.terrain_height = terrain_data;

    var map = try InfluenceMap.fromGrid(allocator, grid);
    defer map.deinit(allocator);

    const start: Point2 = .{ .x = 1.5, .y = 1.5 };
    const goal: Point2 = .{ .x = 10.5, .y = 10.5 };

    const path = map.pathfindPath(allocator, start, goal, false);
    defer allocator.free(path.?);

    const dir = map.pathfindDirection(allocator, start, goal, false);
    try std.testing.expectEqual(path.?.len, 9);
    try std.testing.expectEqual(dir.?.path_len, path.?.len);
    try std.testing.expectEqual(dir.?.next_point, path.?[4]);

    const wall_indices = [_]usize{ 2 * size + 2, 3 * size + 2, 4 * size + 2, 5 * size + 2, 6 * size + 2, 7 * size + 2, 8 * size + 2, 2 * size + 3, 2 * size + 4, 2 * size + 5, 2 * size + 6 };
    grid.setValues(&wall_indices, 0);

    var map2 = try InfluenceMap.fromGrid(allocator, grid);
    defer map2.deinit(allocator);
    const dir2 = map2.pathfindDirection(allocator, start, goal, false).?;
    try std.testing.expectEqual(dir2.path_len, 15);

    map2.addInfluence(.{ .x = 8, .y = 4 }, 4, 10, .none);
    const dir3 = map2.pathfindDirection(allocator, start, goal, false).?;
    try std.testing.expectEqual(dir3.path_len, 17);

    const safe = map2.findClosestSafeSpot(.{ .x = 8, .y = 4 }, 6);
    try std.testing.expectEqual(safe.?, .{ .x = 4.5, .y = 1.5 });

    const old_value = map2.grid[map2.pointToIndex(.{ .x = 4.5, .y = 1.5 })];
    map2.addInfluenceHollow(.{ .x = 5.5, .y = 2.5 }, 5, 2, 10, .{ .linear = 5 });
    const new_value = map2.grid[map2.pointToIndex(.{ .x = 4.5, .y = 1.5 })];
    try std.testing.expectApproxEqAbs(old_value, new_value, 0.02);
}
