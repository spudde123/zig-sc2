const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const sc2p = @import("sc2proto.zig");
const Unit = sc2p.Unit;
const DisplayType = sc2p.DisplayType;
const Alliance = sc2p.Alliance;
const CloakState = sc2p.CloakState;
const Race = sc2p.Race;
const Attribute = sc2p.Attribute;

const AbilityId = @import("ids/ability_id.zig").AbilityId;
const BuffId = @import("ids/buff_id.zig").BuffId;
const EffectId = @import("ids/effect_id.zig").EffectId;
const UnitId = @import("ids/unit_id.zig").UnitId;
const UpgradeId = @import("ids/upgrade_id.zig").UpgradeId;

const grids = @import("grids.zig");
const Point2 = grids.Point2;
const Point3 = grids.Point3;
const Circle = grids.Circle;

// Helper functions and iterators for collections of units.
// The unit struct itself is defined in sc2proto.zig
// because it's decoded directly from the protobuf
// messages

pub fn getUnitByTag(units: []Unit, tag: u64) ?Unit {
    for (units) |unit| {
        if (unit.tag == tag) return unit;
    }
    return null;
}

pub const UnitDistanceResult = struct {
    unit: Unit,
    distance_squared: f32,
};

pub fn findClosestUnit(units: []Unit, pos: Point2) ?UnitDistanceResult {
    var min_distance: f32 = math.floatMax(f32);
    var closest_unit_result: ?UnitDistanceResult = null;
    for (units) |unit| {
        const dist_sqrd = unit.position.distanceSquaredTo(pos);
        if (dist_sqrd < min_distance) {
            min_distance = dist_sqrd;
            closest_unit_result = .{
                .unit = unit,
                .distance_squared = dist_sqrd,
            };
        }
    }
    return closest_unit_result;
}

pub fn findFurthestUnit(units: []Unit, pos: Point2) ?UnitDistanceResult {
    var max_distance: f32 = 0;
    var furthest_unit_result: ?UnitDistanceResult = null;
    for (units) |unit| {
        const dist_sqrd = unit.position.distanceSquaredTo(pos);
        if (dist_sqrd > max_distance) {
            max_distance = dist_sqrd;
            furthest_unit_result = .{
                .unit = unit,
                .distance_squared = dist_sqrd,
            };
        }
    }
    return furthest_unit_result;
}

pub fn filter(
    units: []Unit,
    allocator: mem.Allocator,
    context: anytype,
    comptime filterFn: fn (context: @TypeOf(context), unit: Unit) bool,
) ![]Unit {
    var list: std.ArrayList(Unit) = .empty;
    errdefer list.deinit(allocator);
    for (units) |unit| {
        if (filterFn(context, unit)) {
            try list.append(allocator, unit);
        }
    }
    return try list.toOwnedSlice(allocator);
}

pub fn amountOfType(
    units: []Unit,
    unit_type: UnitId,
) usize {
    var count: usize = 0;
    for (units) |unit| {
        if (unit.unit_type == unit_type) count += 1;
    }
    return count;
}

pub fn amountOfTypes(
    units: []Unit,
    unit_types: []const UnitId,
) usize {
    var count: usize = 0;
    for (units) |unit| {
        if (mem.indexOfScalar(UnitId, unit_types, unit.unit_type)) |_| {
            count += 1;
        }
    }
    return count;
}

pub fn ofType(
    units: []Unit,
    unit_type: UnitId,
    allocator: mem.Allocator,
) ![]Unit {
    var list: std.ArrayList(Unit) = .empty;
    errdefer list.deinit(allocator);
    for (units) |unit| {
        if (unit.unit_type == unit_type) {
            try list.append(allocator, unit);
        }
    }
    return try list.toOwnedSlice(allocator);
}

pub fn ofTypes(
    units: []Unit,
    unit_types: []const UnitId,
    allocator: mem.Allocator,
) ![]Unit {
    var list: std.ArrayList(Unit) = .empty;
    errdefer list.deinit(allocator);
    for (units) |unit| {
        if (mem.indexOfScalar(UnitId, unit_types, unit.unit_type)) |_| {
            try list.append(allocator, unit);
        }
    }
    return try list.toOwnedSlice(allocator);
}

fn unitTypeMatches(context: UnitId, unit: Unit) bool {
    return context == unit.unit_type;
}

fn unitTypesMatch(context: []const UnitId, unit: Unit) bool {
    for (context) |unit_id| {
        if (unit.unit_type == unit_id) return true;
    }
    return false;
}

fn unitTypesDontMatch(context: []const UnitId, unit: Unit) bool {
    for (context) |unit_id| {
        if (unit.unit_type == unit_id) return false;
    }
    return true;
}

fn tagsMatch(context: []u64, unit: Unit) bool {
    for (context) |tag| {
        if (unit.tag == tag) return true;
    }
    return false;
}

fn tagsDontMatch(context: []u64, unit: Unit) bool {
    for (context) |tag| {
        if (unit.tag == tag) return false;
    }

    return true;
}

fn closerThan(context: Circle, unit: Unit) bool {
    return context.isInside(unit.position);
}

fn furtherThan(context: Circle, unit: Unit) bool {
    return !context.isInside(unit.position);
}

pub fn insideDistance(circle: Circle, units: []Unit) UnitIterator(Circle, closerThan) {
    return UnitIterator(Circle, closerThan){ .buffer = units, .context = circle };
}

pub fn outsideDistance(circle: Circle, units: []Unit) UnitIterator(Circle, furtherThan) {
    return UnitIterator(Circle, furtherThan){ .buffer = units, .context = circle };
}

pub fn includeTags(tags: []u64, units: []Unit) UnitIterator([]u64, tagsMatch) {
    return UnitIterator([]u64, tagsMatch){ .buffer = units, .context = tags };
}

pub fn excludeTags(tags: []u64, units: []Unit) UnitIterator([]u64, tagsDontMatch) {
    return UnitIterator([]u64, tagsDontMatch){ .buffer = units, .context = tags };
}

pub fn includeType(unit_type: UnitId, units: []Unit) UnitIterator(UnitId, unitTypeMatches) {
    return UnitIterator(UnitId, unitTypeMatches){ .buffer = units, .context = unit_type };
}

pub fn includeTypes(unit_types: []const UnitId, units: []Unit) UnitIterator([]const UnitId, unitTypesMatch) {
    return UnitIterator([]const UnitId, unitTypesMatch){ .buffer = units, .context = unit_types };
}

pub fn excludeTypes(unit_types: []const UnitId, units: []Unit) UnitIterator([]const UnitId, unitTypesDontMatch) {
    return UnitIterator([]const UnitId, unitTypesDontMatch){ .buffer = units, .context = unit_types };
}

pub fn UnitIterator(comptime ContextType: type, comptime filterFn: fn (context: ContextType, unit: Unit) bool) type {
    return struct {
        index: usize = 0,
        buffer: []Unit,
        context: ContextType,

        const Self = @This();

        pub fn next(self: *Self) ?Unit {
            if (self.index >= self.buffer.len) return null;

            var current = self.index;
            var result: ?Unit = null;
            while (current < self.buffer.len) {
                if (filterFn(self.context, self.buffer[current])) {
                    result = self.buffer[current];
                    current += 1;
                    break;
                }
                current += 1;
            }
            self.index = current;
            return result;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }

        pub fn count(self: *Self) usize {
            self.index = 0;

            var result: usize = 0;
            while (self.next()) |_| {
                result += 1;
            }
            return result;
        }

        pub fn exists(self: *Self) bool {
            self.index = 0;
            return self.next() != null;
        }

        pub fn findClosest(self: *Self, pos: Point2) ?UnitDistanceResult {
            self.index = 0;
            var min_dist: f32 = math.floatMax(f32);
            var result: ?UnitDistanceResult = null;
            while (self.next()) |unit| {
                const dist = pos.distanceSquaredTo(unit.position);
                if (dist < min_dist) {
                    min_dist = dist;
                    result = .{
                        .distance_squared = dist,
                        .unit = unit,
                    };
                }
            }

            return result;
        }

        pub fn findClosestUsingAbility(self: *Self, pos: Point2, ability: AbilityId) ?UnitDistanceResult {
            self.index = 0;
            var min_dist: f32 = math.floatMax(f32);
            var result: ?UnitDistanceResult = null;
            while (self.next()) |unit| {
                if (!unit.isUsingAbility(ability)) continue;
                const dist = pos.distanceSquaredTo(unit.position);
                if (dist < min_dist) {
                    min_dist = dist;
                    result = .{
                        .distance_squared = dist,
                        .unit = unit,
                    };
                }
            }

            return result;
        }

        pub fn findFurthest(self: *Self, pos: Point2) ?UnitDistanceResult {
            self.index = 0;
            var max_dist: f32 = 0;
            var result: ?UnitDistanceResult = null;
            while (self.next()) |unit| {
                const dist = pos.distanceSquaredTo(unit.position);
                if (dist > max_dist) {
                    max_dist = dist;
                    result = .{
                        .distance_squared = dist,
                        .unit = unit,
                    };
                }
            }

            return result;
        }

        pub fn findFurthestUsingAbility(self: *Self, pos: Point2, ability: AbilityId) ?UnitDistanceResult {
            self.index = 0;
            var max_dist: f32 = 0;
            var result: ?UnitDistanceResult = null;
            while (self.next()) |unit| {
                if (!unit.isUsingAbility(ability)) continue;
                const dist = pos.distanceSquaredTo(unit.position);
                if (dist > max_dist) {
                    max_dist = dist;
                    result = .{
                        .distance_squared = dist,
                        .unit = unit,
                    };
                }
            }

            return result;
        }
    };
}
