const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

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
        return (
            point.x >= self.p0.x
            and point.x <= self.p1.x
            and point.y >= self.p0.y
            and point.y <= self.p1.y
        );
    }
};

pub const GridPoint = struct {
    x: i32,
    y: i32,
};

pub const Point2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn distanceTo(self: Point2, other: Point2) f32 {
        const x = self.x - other.x;
        const y = self.y - other.y;
        return math.sqrt(x*x + y*y);
    }

    pub fn distanceSquaredTo(self: Point2, other: Point2) f32 {
        const x = self.x - other.x;
        const y = self.y - other.y;
        return x*x + y*y;
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

    pub fn subtract(self: Point2, other: Point2) Point2 {
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
        return math.max(x_diff, y_diff) + (math.sqrt2 - 1)*math.min(x_diff, y_diff);
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
        const x: usize = @floatToInt(usize, math.floor(point.x));
        const y: usize = @floatToInt(usize, math.floor(point.y));

        assert(x >= 0 and x < self.w);
        assert(y >= 0 and y < self.h);
        
        return self.data[x + y*self.w];
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
        const x: usize = @floatToInt(usize, math.floor(point.x));
        const y: usize = @floatToInt(usize, math.floor(point.y));
        return x + y*self.w;
    }

    pub fn indexToPoint(self: Grid, index: usize) Point2 {
        const x = @intToFloat(f32, @mod(index, self.w));
        const y = @intToFloat(f32, @divFloor(index, self.w));
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

    for (pathing.data) |val, i| {
        const x = @mod(i, w);
        const y = i / w;
        // Edges of the map are pointless regardless
        // and we avoid the need for checking index validity later
        if (x < 2 or y < 2 or x > w - 3 or y > h - 3 or val > 0) continue;

        const cur_terrain = terrain.data[x + y*w];

        // First looking at vertical or horizontal jumps
        const up_val = pathing.data[x + (y - 1)*w];
        const up_terrain = terrain.data[x + (y - 1)*w];
        
        const down_val = pathing.data[x + (y + 1)*w];
        const down_terrain = terrain.data[x + (y + 1)*w];
        const vert_diff = if (up_terrain > down_terrain) up_terrain - down_terrain else down_terrain - up_terrain;

        const left_val = pathing.data[x - 1 + y*w];
        const left_terrain = terrain.data[x - 1 + y*w];

        const right_val = pathing.data[x + 1 + y*w];
        const right_terrain = terrain.data[x + 1 + y*w];
        const horiz_diff = if (left_terrain > right_terrain) left_terrain - right_terrain else right_terrain - left_terrain;

        if (up_val == 1 and down_val == 1 and vert_diff == level_diff) try list.append(i);
        if (left_val == 1 and right_val == 1 and horiz_diff == level_diff) try list.append(i);

        // And then diagonal jumps
        const diag_moves = [_]usize{w + 1, w - 1};
        for (diag_moves) |diag_move| {
            const val1 = pathing.data[i - 2*diag_move];
            const val2 = pathing.data[i - diag_move];
            const val3 = pathing.data[i + diag_move];
            const val4 = pathing.data[i + 2*diag_move];

            const terrain2 = terrain.data[i - diag_move];
            const terrain3 = terrain.data[i + diag_move];
            const total_diff = if (terrain2 > terrain3) terrain2 - terrain3 else terrain3 - terrain2;
            const diff2 = if (cur_terrain > terrain2) cur_terrain - terrain2 else terrain2 - cur_terrain;
            const diff3 = if (cur_terrain > terrain3) cur_terrain - terrain3 else terrain3 - cur_terrain;
            
            const terrain_valid_double = total_diff == 2*level_diff and diff2 == level_diff and diff3 == level_diff;
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

    return list.toOwnedSlice();
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

pub fn createAirGrid(allocator: mem.Allocator, map_width: usize, map_height: usize, playable_area: Rectangle) !Grid {
    const start_x = @intCast(usize, playable_area.p0.x);
    const end_x = @intCast(usize, playable_area.p1.x);
    const start_y = @intCast(usize, playable_area.p0.y);
    const end_y = @intCast(usize, playable_area.p1.y);

    var data = try allocator.alloc(u8, map_width*map_height);

    var y: usize = 0;
    while (y < map_height) : (y += 1) {
        var x: usize = 0;
        while (x < map_width) : (x += 1) {
            const index = x + map_width*y;
            const playable = x >= start_x and x <= end_x and y >= start_y and y <= end_y;
            data[index] = if (playable) 1 else 0;
        }
    }
    return .{
        .data = data,
        .w = map_width,
        .h = map_height
    };
}

pub const PathfindResult = struct {
    path_len: usize,
    next_point: Point2,
};

pub const InfluenceMap = struct {

    grid: []f32,
    terrain_height: []const u8,
    w: usize,
    h: usize,

    const sqrt2 = math.sqrt2;

    pub const DecayTag = enum {
        none,
        linear,
    };

    pub const Decay = union(DecayTag) {
        none: void,
        // Linear float should be the value we should decay to at the edge of circle
        linear: f32,
    } ;

    pub fn fromGrid(allocator: mem.Allocator, base_grid: Grid, terrain_height: Grid) !InfluenceMap {
        var grid = try allocator.alloc(f32, base_grid.data.len);
        for (base_grid.data) |val, i| {
            grid[i] = if (val > 0) 1 else math.f32_max;
        }
        return .{
            .grid = grid,
            .terrain_height = terrain_height.data,
            .w = base_grid.w,
            .h = base_grid.h,
        };
    }

    pub fn reset(self: *InfluenceMap, base_grid: Grid) void {
        for (base_grid.data) |val, i| {
            self.grid[i] = if (val > 0) 1 else math.f32_max;
        }
    }

    pub fn deinit(self: *InfluenceMap, allocator: mem.Allocator) void {
        allocator.free(self.grid);
    }

    pub fn addInfluence(self: *InfluenceMap, center: Point2, radius: f32, amount: f32, decay: Decay) void {
        const f32_w = @intToFloat(f32, self.w - 1);
        const f32_h = @intToFloat(f32, self.h - 1);
        const bounding_rect_min_x = @floatToInt(usize, math.max(center.x - radius, 0));
        const bounding_rect_max_x = @floatToInt(usize, math.min(center.x + radius, f32_w));
        const bounding_rect_min_y = @floatToInt(usize, math.max(center.y - radius, 0));
        const bounding_rect_max_y = @floatToInt(usize, math.min(center.y + radius, f32_h));
        const r_sqrd = radius*radius;

        var y = bounding_rect_min_y;
        while (y <= bounding_rect_max_y) : (y += 1) {
            var x = bounding_rect_min_x;
            while (x <= bounding_rect_max_x) : (x += 1) {
                const index = x + self.w*y;
                const point = self.indexToPoint(index).add(.{.x = 0.5, .y = 0.5});
                const dist_sqrd = point.distanceSquaredTo(center);
                if (dist_sqrd < r_sqrd) {
                    switch (decay) {
                        .none => self.grid[index] += amount,
                        .linear => |end_amount| {
                            const dist = math.sqrt(dist_sqrd);
                            const t = dist / radius;
                            self.grid[index] += (1 - t)*amount + t*end_amount;
                        },
                    }
                    self.grid[index] = math.max(1, self.grid[index]);
                }
            }
        }
    }

    pub fn addInfluenceHollow(self: *InfluenceMap, center: Point2, radius: f32, hollow_radius: f32, amount: f32, decay: Decay) void {
        self.addInfluence(center, radius, amount, decay);
        self.addInfluence(center, hollow_radius, -amount, .none);
    }

    pub fn findClosestSafeSpot(self: *InfluenceMap, pos: Point2, radius: f32) ?Point2 {
        const f32_w = @intToFloat(f32, self.w - 1);
        const f32_h = @intToFloat(f32, self.h - 1);
        const bounding_rect_min_x = @floatToInt(usize, math.max(pos.x - radius, 0));
        const bounding_rect_max_x = @floatToInt(usize, math.min(pos.x + radius, f32_w));
        const bounding_rect_min_y = @floatToInt(usize, math.max(pos.y - radius, 0));
        const bounding_rect_max_y = @floatToInt(usize, math.min(pos.y + radius, f32_h));
        const r_sqrd = radius*radius;

        var best_val: f32 = math.f32_max;
        var best_dist: f32 = math.f32_max;
        var best_point: ?Point2 = null;

        var y = bounding_rect_min_y;
        while (y <= bounding_rect_max_y) : (y += 1) {
            var x = bounding_rect_min_x;
            while (x <= bounding_rect_max_x) : (x += 1) {
                const index = x + self.w*y;
                const point = self.indexToPoint(index).add(.{.x = 0.5, .y = 0.5});
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and self.grid[index] <= best_val and self.grid[index] < math.f32_max and dist_sqrd < best_dist) {
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
    };

    fn lessThan(context: void, a: Node, b: Node) math.Order {
        _ = context;
        return math.order(a.heuristic, b.heuristic);
    }
    
    /// First tries to find a pathable point on the same height
    /// as the asked point. After that accepts any spot
    /// that is pathable
    fn findClosestValidPoint(self: InfluenceMap, pos: Point2) ?Point2 {
        const radius = 6;
        const f32_w = @intToFloat(f32, self.w - 1);
        const f32_h = @intToFloat(f32, self.h - 1);
        const bounding_rect_min_x = @floatToInt(usize, math.max(pos.x - radius, 0));
        const bounding_rect_max_x = @floatToInt(usize, math.min(pos.x + radius, f32_w));
        const bounding_rect_min_y = @floatToInt(usize, math.max(pos.y - radius, 0));
        const bounding_rect_max_y = @floatToInt(usize, math.min(pos.y + radius, f32_h));
        const r_sqrd = radius*radius;

        var best_dist: f32 = math.f32_max;
        var best_point: ?Point2 = null;
        const height_at_start = self.terrain_height[self.pointToIndex(pos)];

        var y = bounding_rect_min_y;
        while (y <= bounding_rect_max_y) : (y += 1) {
            var x = bounding_rect_min_x;
            while (x <= bounding_rect_max_x) : (x += 1) {
                const index = x + self.w*y;
                const point = self.indexToPoint(index);
                
                const height = self.terrain_height[index];
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and height == height_at_start and self.grid[index] < math.f32_max and dist_sqrd < best_dist) {
                    best_dist = dist_sqrd;
                    best_point = point;
                }
            }
        }

        if (best_point) |p| return p;

        y = bounding_rect_min_y;
        while (y <= bounding_rect_max_y) : (y += 1) {
            var x = bounding_rect_min_x;
            while (x <= bounding_rect_max_x) : (x += 1) {
                const index = x + self.w*y;
                const point = self.indexToPoint(index);
                const dist_sqrd = point.distanceSquaredTo(pos);
                if (dist_sqrd < r_sqrd and self.grid[index] < math.f32_max and dist_sqrd < best_dist) {
                    best_dist = dist_sqrd;
                    best_point = point;
                }
            }
        }
        return best_point;
    }

    pub fn validateEndPoint(self: InfluenceMap, pos: Point2) ?Point2 {
        const index = self.pointToIndex(pos);
        if (self.grid[index] < math.f32_max) return pos;

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

        // Let's keep track of a certain number of recent steps so we can return for example the 3rd step
        // as the desired direction to go to
        var last_nodes = [_]usize{goal_index} ** 5;
        const path_len = cur.?.path_len;
        while (cur) |node| {
            var j: usize = last_nodes.len - 1;
            while (j > 0) : (j -= 1) {
                last_nodes[j] = last_nodes[j - 1]; 
            }
            last_nodes[0] = node.prev;
            cur = came_from.get(node.prev);
        }

        return .{
            .path_len = path_len,
            .next_point = self.indexToPoint(last_nodes[last_nodes.len - 1]).add(.{.x = 0.5, .y = 0.5}),
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
            res[index - 1] = self.indexToPoint(node.prev).add(.{.x = 0.5, .y = 0.5});
            if (index == 1) break;
            cur = came_from.get(node.prev);
            index -= 1;
        }

        return res;
    }

    fn runPathfind(self: InfluenceMap, allocator: mem.Allocator, start: Point2, goal: Point2, large_unit: bool) !std.AutoHashMap(usize, CameFrom) {
        var queue = std.PriorityQueue(Node, void, lessThan).init(allocator, {});
        defer queue.deinit();

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
        const h = self.h;

        var neighbors = try std.ArrayList(Neighbor).initCapacity(allocator, 8);
        defer neighbors.deinit();

        var came_from = std.AutoHashMap(usize, CameFrom).init(allocator);

        while (queue.count() > 0) {
            const node = queue.remove();
            if (node.index == goal_index) break;

            const index = node.index;
            const x = @mod(index, w);
            const y = index / w;

            const x_low = x > 0;
            const x_large = x < w - 1;
            const y_low = y > 0;
            const y_large = y < h - 1;

            if (x_low and y_low and grid[index - w - 1] < math.f32_max
                and grid[index - 1] < math.f32_max and grid[index - w] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index - w - 1, .movement_cost = sqrt2});
            
            if (y_low and grid[index - w] < math.f32_max) {
                if (!large_unit or grid[index - w - 1] < math.f32_max or grid[index - w + 1] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index - w, .movement_cost = 1});
            }
            if (x_large and y_low and grid[index - w + 1] < math.f32_max
                and grid[index + 1] < math.f32_max and grid[index - w] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index - w + 1, .movement_cost = sqrt2});
            
            if (x_low and grid[index - 1] < math.f32_max) {
                if (!large_unit or grid[index - w - 1] < math.f32_max or grid[index + w - 1] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index - 1, .movement_cost = 1});
            }

            if (x_large and grid[index + 1] < math.f32_max) {
                if (!large_unit or grid[index - w + 1] < math.f32_max or grid[index + w + 1] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index + 1, .movement_cost = 1});
            }

            if (x_low and y_large and grid[index + w - 1] < math.f32_max
                and grid[index - 1] < math.f32_max and grid[index + w] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index + w - 1, .movement_cost = sqrt2});
            
            if (y_large and grid[index + w] < math.f32_max) {
                if (!large_unit or grid[index + w - 1] < math.f32_max or grid[index + w + 1] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index + w, .movement_cost = 1});
            }

            if (x_large and y_large and grid[index + w + 1] < math.f32_max
                and grid[index + 1] < math.f32_max and grid[index + w] < math.f32_max) neighbors.appendAssumeCapacity(.{.index = index + w + 1, .movement_cost = sqrt2});

            for (neighbors.items) |nbr| {
                if (nbr.index == start_index or came_from.contains(nbr.index)) continue;

                const nbr_cost = node.cost + nbr.movement_cost * grid[nbr.index];
                const nbr_point = self.indexToPoint(nbr.index);
                const estimated_cost = nbr_cost + nbr_point.octileDistance(goal_floor);

                try queue.add(.{
                    .index = nbr.index,
                    .path_len = node.path_len + 1,
                    .cost = nbr_cost,
                    .heuristic = estimated_cost,
                });
                try came_from.put(nbr.index, .{.prev = index, .path_len = node.path_len + 1});
            }

            neighbors.clearRetainingCapacity();
        }

        return came_from;
    }
    
    pub fn pointToIndex(self: InfluenceMap, point: Point2) usize {
        const x: usize = @floatToInt(usize, math.floor(point.x));
        const y: usize = @floatToInt(usize, math.floor(point.y));
        return x + y*self.w;
    }

    pub fn indexToPoint(self: InfluenceMap, index: usize) Point2 {
        const x = @intToFloat(f32, @mod(index, self.w));
        const y = @intToFloat(f32, @divFloor(index, self.w));
        return .{
            .x = x,
            .y = y,
        };
    }
};

test "test_pf_basic" {
    var allocator = std.testing.allocator;
    var data = try allocator.alloc(u8, 10*10);
    defer allocator.free(data);

    mem.set(u8, data, 1);
    var grid = Grid{.data = data, .w = 10, .h = 10};

    var terrain_data = try allocator.alloc(u8, 10*10);
    defer allocator.free(terrain_data);

    mem.set(u8, terrain_data, 10);
    var terrain_grid = Grid{.data = terrain_data, .w = 10, .h = 10};

    var map = try InfluenceMap.fromGrid(allocator, grid, terrain_grid);
    defer map.deinit(allocator);

    const start: Point2 = .{.x = 0.5, .y = 0.5};
    const goal: Point2 = .{.x = 9.5, .y = 9.5};

    const path = map.pathfindPath(allocator, start, goal, false);
    defer allocator.free(path.?);

    const dir = map.pathfindDirection(allocator, start, goal, false);
    try std.testing.expectEqual(path.?.len, 9);
    try std.testing.expectEqual(dir.?.path_len, path.?.len);
    try std.testing.expectEqual(dir.?.next_point, path.?[4]);
    
    const wall_indices = [_]usize{11, 21, 31, 41, 51, 61, 71, 12, 13, 14, 15};
    grid.setValues(&wall_indices, 0);

    var map2 = try InfluenceMap.fromGrid(allocator, grid, terrain_grid);
    defer map2.deinit(allocator);
    const dir2 = map2.pathfindDirection(allocator, start, goal, false).?;
    try std.testing.expectEqual(dir2.path_len, 15);
    
    map2.addInfluence(.{.x = 7, .y = 3}, 4, 10, .none);
    const dir3 = map2.pathfindDirection(allocator, start, goal, false).?;
    try std.testing.expectEqual(dir3.path_len, 17);

    const safe = map2.findClosestSafeSpot(.{.x = 7, .y = 3}, 6);
    try std.testing.expectEqual(safe.?, .{.x = 3.5, .y = 0.5});
}
