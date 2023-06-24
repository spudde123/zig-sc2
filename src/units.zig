const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const sc2p = @import("sc2proto.zig");
const AbilityId = @import("ids/ability_id.zig").AbilityId;
const BuffId = @import("ids/buff_id.zig").BuffId;
const EffectId = @import("ids/effect_id.zig").EffectId;
const UnitId = @import("ids/unit_id.zig").UnitId;
const UpgradeId = @import("ids/upgrade_id.zig").UpgradeId;

const DisplayType = sc2p.DisplayType;
const Alliance = sc2p.Alliance;
const CloakState = sc2p.CloakState;
const Race = sc2p.Race;
const Attribute = sc2p.Attribute;

const Point2 = @import("grids.zig").Point2;

pub const PowerSource = struct {
    position: Point2,
    radius: f32,
    tag: u64,
};

pub const Effect = struct {
    id: EffectId,
    alliance: Alliance,
    positions: []Point2,
    radius: f32,
};

pub const SensorTower = struct {
    position: Point2,
    radius: f32,
};

pub const OrderType = enum(u8) {
    empty,
    position,
    tag,
};

pub const OrderTarget = union(OrderType) {
    empty: void,
    position: Point2,
    tag: u64,
};

pub const UnitOrder = struct {
    ability_id: AbilityId,
    target: OrderTarget,
    progress: f32,
};

pub const RallyTarget = struct {
    point: Point2,
    tag: ?u64,
};

pub const Unit = struct {
    display_type: DisplayType,
    alliance: Alliance,
    tag: u64,
    unit_type: UnitId,
    owner: i32,
    prev_seen_loop: u32,

    position: Point2,
    z: f32,
    facing: f32,
    radius: f32,
    build_progress: f32,
    cloak: CloakState,
    buff_ids: []BuffId,

    detect_range: f32,
    radar_range: f32,

    is_blip: bool,
    is_powered: bool,
    is_active: bool,
    is_structure: bool,

    attack_upgrade_level: i32,
    armor_upgrade_level: i32,
    shield_upgrade_level: i32,

    health: f32,
    health_max: f32,
    shield: f32,
    shield_max: f32,
    energy: f32,
    energy_max: f32,
    mineral_contents: i32,
    vespene_contents: i32,
    is_flying: bool,
    is_burrowed: bool,
    is_hallucination: bool,

    orders: []UnitOrder,
    addon_tag: u64,
    passengers: []u64,
    cargo_space_taken: i32,
    cargo_space_max: i32,

    assigned_harvesters: i32,
    ideal_harvesters: i32,
    weapon_cooldown: f32,
    engaged_target_tag: u64,
    buff_duration_remain: i32,
    buff_duration_max: i32,
    rally_targets: []RallyTarget,

    available_abilities: []AbilityId,

    pub fn isIdle(self: Unit) bool {
        return self.orders.len == 0;
    }

    pub fn isCollecting(self: Unit) bool {
        if (self.orders.len == 0) return false;
        const order = self.orders[0];
        
        return (
            order.ability_id == .Harvest_Gather_SCV
            or order.ability_id == .Harvest_Return_SCV
            or order.ability_id == .Harvest_Gather_Drone
            or order.ability_id == .Harvest_Return_Drone
            or order.ability_id == .Harvest_Gather_Probe
            or order.ability_id == .Harvest_Return_Probe
            or order.ability_id == .Harvest_Gather_Mule
            or order.ability_id == .Harvest_Return_Mule
        );
    }

    pub fn isRepairing(self: Unit) bool {
        if (self.orders.len == 0) return false;
        const order = self.orders[0];
        
        return (
            order.ability_id == .Effect_Repair
            or order.ability_id == .Effect_Repair_Mule
            or order.ability_id == .Effect_Repair_SCV
        );
    }

    pub fn isUsingAbility(self: Unit, ability: AbilityId) bool {
        if (self.orders.len == 0) return false;
        const order = self.orders[0];
        
        return order.ability_id == ability;
    }

    pub fn hasBuff(self: Unit, buff: BuffId) bool {
        for (self.buff_ids) |b| {
            if (b == buff) return true;
        }
        return false;
    }

    pub fn hasAbilityAvailable(self: Unit, ability: AbilityId) bool {
        for (self.available_abilities) |available_ability| {
            if (available_ability == ability) return true;
        }
        return false;
    }

    pub fn isReady(self: Unit) bool {
        return self.build_progress >= 1;
    } 
};

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
) []Unit {
    var list = std.ArrayList(Unit).init(allocator);
    for (units) |unit| {
        if (filterFn(context, unit)) {
            list.append(unit) catch continue;
        }
    }
    return list.toOwnedSlice() catch &[_]Unit{};
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
) []Unit {
    var list = std.ArrayList(Unit).init(allocator);
    for (units) |unit| {
        if (unit.unit_type == unit_type) {
            list.append(unit) catch continue;
        }
    }
    return list.toOwnedSlice() catch &[_]Unit{};
}

pub fn ofTypes(
    units: []Unit,
    unit_types: []const UnitId,
    allocator: mem.Allocator,
) []Unit {
    var list = std.ArrayList(Unit).init(allocator);
    for (units) |unit| {
        if (mem.indexOf(UnitId, unit_types, unit.unit_type)) |_| {
            list.append(unit) catch continue;
        }
    }
    return list.toOwnedSlice() catch &[_]Unit{};
}

fn unitTypeMatches(context: UnitId, unit: Unit) bool {
    return context == unit.unit_type;
}

fn unitTypesMatch(context: []const UnitId, unit: Unit) bool {
    for (context) |unit_id| {
        if(unit.unit_type == unit_id) return true;
    }
    return false;
}

fn unitTypesDontMatch(context: []const UnitId, unit: Unit) bool {
    for (context) |unit_id| {
        if(unit.unit_type == unit_id) return false;
    }
    return true;
}

fn tagsMatch(context: []u64, unit: Unit) bool {
    for (context) |tag| {
        if(unit.tag == tag) return true;
    }
    return false;
}

fn tagsDontMatch(context: []u64, unit: Unit) bool {
    for (context) |tag| {
        if(unit.tag == tag) return false;
    }
    
    return true;
}

pub fn includeTags(tags: []u64, units: []Unit) UnitIterator([]u64, tagsMatch) {
    return UnitIterator([]u64, tagsMatch){.buffer = units, .context = tags};
}

pub fn excludeTags(tags: []u64, units: []Unit) UnitIterator([]u64, tagsDontMatch) {
    return UnitIterator([]u64, tagsDontMatch){.buffer = units, .context = tags};
}

pub fn includeType(unit_type: UnitId, units: []Unit) UnitIterator(UnitId, unitTypeMatches) {
    return UnitIterator(UnitId, unitTypeMatches){.buffer = units, .context = unit_type};
}

pub fn includeTypes(unit_types: []const UnitId, units: []Unit) UnitIterator([]const UnitId, unitTypesMatch) {
    return UnitIterator([]const UnitId, unitTypesMatch){.buffer = units, .context = unit_types};
}

pub fn excludeTypes(unit_types: []const UnitId, units: []Unit) UnitIterator([]const UnitId, unitTypesDontMatch) {
    return UnitIterator([]const UnitId, unitTypesDontMatch){.buffer = units, .context = unit_types};
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
    };
}