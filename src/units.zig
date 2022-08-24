const std = @import("std");
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
};

pub fn getUnitByTag(units: []Unit, tag: u64) ?Unit {
    for (units) |unit| {
        if (unit.tag == tag) return unit;
    }
    return null;
}

pub fn findClosestUnit(units: []Unit, pos: Point2) Unit {
    assert(units.len > 0);
    var min_distance: f32 = math.f32_max;
    var closest_unit: Unit = undefined;
    for (units) |unit| {
        const dist_sqrd = unit.position.distanceSquaredTo(pos);
        if (dist_sqrd < min_distance) {
            min_distance = dist_sqrd;
            closest_unit = unit;
        }
    }
    return closest_unit;
}