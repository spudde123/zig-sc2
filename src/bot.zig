const std = @import("std");
const assert = std.debug.assert;

const mem = std.mem;
const log = std.log;
const math = std.math;
const PackedIntIo = std.packed_int_array.PackedIntIo;

const ws = @import("client.zig");
const sc2p = @import("sc2proto.zig");
pub const AbilityId = @import("ids/ability_id.zig").AbilityId;
pub const BuffId = @import("ids/buff_id.zig").BuffId;
pub const EffectId = @import("ids/effect_id.zig").EffectId;
pub const UnitId = @import("ids/unit_id.zig").UnitId;
pub const UpgradeId = @import("ids/upgrade_id.zig").UpgradeId;

pub const Result = sc2p.Result;
pub const DisplayType = sc2p.DisplayType;
pub const Alliance = sc2p.Alliance;
pub const CloakState = sc2p.CloakState;
pub const Race = sc2p.Race;
pub const Channel = sc2p.Channel;
pub const Attribute = sc2p.Attribute;

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
    x: f32,
    y: f32,

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

};

pub const Point3 = struct {
    x: f32,
    y: f32,
    z: f32,
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
        return order.ability_id == .Harvest_Gather_SCV or order.ability_id == .Harvest_Return_SCV;
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

pub const Grid = struct {
    data: []u8,
    w: usize,
    h: usize,

    pub fn getF(self: Grid, point: Point2) u8 {
        const x: usize = @floatToInt(usize, math.floor(point.x));
        const y: usize = @floatToInt(usize, math.floor(point.y));

        assert(x >= 0 and x < self.w);
        assert(y >= 0 and y < self.h);
        
        return self.data[y + x*self.h];
    }

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

pub const GameInfo = struct {

    pathing_grid: Grid,
    placement_grid: Grid,
    terrain_height: Grid,

    map_name: []const u8,
    enemy_name: []const u8,
    opponent_id: ?[]const u8,
    // These can be different for a random opponent
    enemy_requested_race: Race,
    enemy_race: Race,

    map_size: GridSize,
    playable_area: Rectangle,

    start_location: Point2,
    enemy_start_locations: []Point2,

    expansion_locations: []Point2,
    //allocator: mem.Allocator,

    pub fn fromProto(
        proto_data: sc2p.ResponseGameInfo,
        player_id: u32,
        opponent_id: ?[]const u8,
        start_location: Point2,
        minerals: []Unit,
        geysers: []Unit,
        allocator: mem.Allocator
    ) !GameInfo {
        
        const received_map_name = proto_data.map_name.data.?;
        var map_name = try allocator.alloc(u8, received_map_name.len);
        mem.copy(u8, map_name, received_map_name);

        var opp_id: ?[]u8 = null;
        if (opponent_id) |received_opponent_id| {
            opp_id = try allocator.alloc(u8, received_opponent_id.len);
            mem.copy(u8, opp_id.?, received_opponent_id);
        } 

        var enemy_requested_race: Race = Race.none;
        var enemy_name: ?[]u8 = null;

        for (proto_data.player_info.data.?) |player_info| {
            if (player_info.player_id.data.? != player_id) {
                enemy_requested_race = player_info.race_requested.data.?;

                if (player_info.player_name.data) |received_enemy_name| {
                    enemy_name = try allocator.alloc(u8, received_enemy_name.len);
                    mem.copy(u8, enemy_name.?, received_enemy_name);
                }

                break;
            }
        }

        const raw_proto = proto_data.start_raw.data.?;

        const map_size_proto = raw_proto.map_size.data.?;
        const map_size = GridSize{.w = @intCast(usize, map_size_proto.x.data.?), .h = @intCast(usize, map_size_proto.y.data.?)};

        const playable_area_proto = raw_proto.playable_area.data.?;
        const rect_p0 = playable_area_proto.p0.data.?;
        const rect_p1 = playable_area_proto.p1.data.?;

        const playable_area = Rectangle{
            .p0 = .{.x = rect_p0.x.data.?, .y = rect_p0.y.data.?},
            .p1 = .{.x = rect_p1.x.data.?, .y = rect_p1.y.data.?},
        };

        var start_locations = std.ArrayList(Point2).init(allocator);
        for (raw_proto.start_locations.data.?) |loc_proto| {
            try start_locations.append(.{
                .x = loc_proto.x.data.?,
                .y = loc_proto.y.data.?,
            });
        }

        const terrain_proto = raw_proto.terrain_height.data.?;
        assert(terrain_proto.bits_per_pixel.data.? == 8);
        assert(terrain_proto.size.data.?.x.data.? == map_size.w);
        assert(terrain_proto.size.data.?.y.data.? == map_size.h);
        const terrain_proto_slice = terrain_proto.image.data.?;
        var terrain_slice = try allocator.alloc(u8, terrain_proto_slice.len);
        mem.copy(u8, terrain_slice, terrain_proto_slice);

        const pathing_proto = raw_proto.pathing_grid.data.?;
        assert(pathing_proto.bits_per_pixel.data.? == 1);
        assert(pathing_proto.size.data.?.x.data.? == map_size.w);
        assert(pathing_proto.size.data.?.y.data.? == map_size.h);
        const pathing_proto_slice = pathing_proto.image.data.?;
        var pathing_slice = try allocator.alloc(u8, @intCast(usize, map_size.w * map_size.h));
        
        const packed_int_type = PackedIntIo(u1, .Big);
        
        var index: usize = 0;
        while (index < map_size.w * map_size.h) : (index += 1) {
            pathing_slice[index] = packed_int_type.get(pathing_proto_slice, index, 0);
        }

        const placement_proto = raw_proto.placement_grid.data.?;
        assert(placement_proto.bits_per_pixel.data.? == 1);
        assert(placement_proto.size.data.?.x.data.? == map_size.w);
        assert(placement_proto.size.data.?.y.data.? == map_size.h);
        const placement_proto_slice = placement_proto.image.data.?;
        var placement_slice = try allocator.alloc(u8, @intCast(usize, map_size.w * map_size.h));
        index = 0;
        while (index < map_size.w * map_size.h) : (index += 1) {
            placement_slice[index] = packed_int_type.get(placement_proto_slice, index, 0);
        }

        return GameInfo{
            .map_name = map_name,
            .opponent_id = opponent_id,
            .enemy_name = enemy_name orelse "Unknown",
            .enemy_requested_race = enemy_requested_race,
            .enemy_race = enemy_requested_race,
            .map_size = map_size,
            .playable_area = playable_area,
            .start_location = start_location,
            .enemy_start_locations = start_locations.toOwnedSlice(),
            .terrain_height = Grid{.data = terrain_slice, .w = map_size.w, .h = map_size.h},
            .pathing_grid = Grid{.data = pathing_slice, .w = map_size.w, .h = map_size.h},
            .placement_grid = Grid{.data = placement_slice, .w = map_size.w, .h = map_size.h},
            .expansion_locations = generateExpansionLocations(minerals, geysers, allocator),
        };
    }

    fn generateExpansionLocations(
        minerals: []Unit,
        geysers: []Unit,
        allocator: mem.Allocator
    ) []Point2 {
        const ResourceData = struct {
            tag: u64,
            pos: Point2,
            is_geyser: bool,
        };

        var resources = std.ArrayList(ResourceData).initCapacity(allocator, minerals.len + geysers.len) catch return &[_]Point2{};
        defer resources.deinit();
        for (minerals) |patch| {
            // Don't use minerals that mainly block pathways and
            // are not meant for bases
            if (patch.unit_type != UnitId.MineralField450) {
                resources.appendAssumeCapacity(.{.tag = patch.tag, .pos = patch.position, .is_geyser = false});
            }
        }
        for (geysers) |geyser| {
            resources.appendAssumeCapacity(.{.tag = geyser.tag, .pos = geyser.position, .is_geyser = true});
        }

        const ResourceGroup = struct {
            resources: [16]ResourceData = undefined,
            count: usize = 0,
        };

        var groups = std.ArrayList(ResourceGroup).init(allocator);
        defer groups.deinit();
        // Group resources
        var i: usize = 0;

        outer: while (i < resources.items.len) : (i += 1){
            var cur: ResourceData = resources.items[i];
            for (groups.items) |*group| {
                var close_found: bool = false;
                for (group.resources) |member| {
                    if (cur.pos.distanceSquaredTo(member.pos) < 140) {
                        close_found = true;
                        break;
                    }
                }
                if (close_found) {
                    group.resources[group.count] = cur;
                    group.count += 1;
                    continue :outer;
                }
            }

            var new_group = ResourceGroup{};
            new_group.count = 1;
            new_group.resources[0] = cur;
            groups.append(new_group) catch return &[_]Point2{};
        }

        var result = allocator.alloc(Point2, groups.items.len) catch return &[_]Point2{};
        for (groups.items) |group, group_index| {
            var center = Point2{.x = 0, .y = 0};
            for(group.resources[0..group.count]) |resource| {
                center.x += resource.pos.x;
                center.y += resource.pos.y;
            }
            center.x = center.x / @intToFloat(f32, group.count);
            center.y = center.y / @intToFloat(f32, group.count);
            center.x = math.floor(center.x) + 0.5;
            center.y = math.floor(center.y) + 0.5;

            var min_total_distance: f32 = math.f32_max;
            var x_offset: f32 = -7;
            while (x_offset < 8) : (x_offset += 1) {
                var y_offset: f32 = -7;
                test_point: while (y_offset < 8) : (y_offset += 1) {
                    const offset_len_sqrd = y_offset * y_offset + x_offset * x_offset;
                    if (offset_len_sqrd <= 16 or offset_len_sqrd > 64) continue;

                    var point = Point2{
                        .x = center.x + x_offset,
                        .y = center.y + y_offset,
                    };

                    var total_distance: f32 = 0;
                    for(group.resources[0..group.count]) |resource| {
                        const req_distance: f32 = if(resource.is_geyser) 49 else 36;
                        const cur_dist = resource.pos.distanceSquaredTo(point);
                        if (cur_dist < req_distance) {
                            continue :test_point;
                        } else {
                            total_distance += cur_dist;
                        }
                    }
                    if (total_distance < min_total_distance) {
                        result[group_index] = point;
                        min_total_distance = total_distance;
                    }
                    
                }
            }

        }

        //for (result) |loc, j| {
        //    std.debug.print("Group size: {d}\n", .{groups.items[j].count});
        //    std.debug.print("{d} {d}\n", .{loc.x, loc.y});
        //}

        return result;
    }

    pub fn update(bot: Bot) void {
        _ = bot;
    }

    pub fn getTerrainZ(self: GameInfo, pos: Point2) f32 {
        const x = @floatToInt(i32, math.floor(pos.x));
        const y = @floatToInt(i32, math.floor(pos.y));
        
        assert(x >= 0 and x < self.terrain_height.w);
        assert(y >= 0 and y < self.terrain_height.h);

        const terrain_grid_height = self.terrain_height.h;
        const grid_index = y + x * terrain_grid_height;
        const terrain_value = @intToFloat(f32, self.terrain_height.data[grid_index]);
        return -16 + 32*terrain_value / 255;
    }
};

pub const Bot = struct {
    units: []Unit,
    structures: []Unit,
    placeholders: []Unit,
    enemy_units: []Unit,
    enemy_structures: []Unit,
    destructables: []Unit,
    mineral_patches: []Unit,
    vespene_geysers: []Unit,
    watch_towers: []Unit,

    // Using signed integers for these so we
    // can comfortably subtract from them towards zero
    minerals: i32,
    vespene: i32,

    food_cap: u32,
    food_used: u32,
    food_army: u32,
    food_workers: u32,
    idle_worker_count: u32,
    army_count: u32,
    warp_gate_count: u32,
    larva_count: u32,

    game_loop: u32,
    time: f32,
    result: ?Result,

    pub fn fromProto(
        response: sc2p.ResponseObservation,
        game_data: GameData,
        player_id: u32,
        allocator: mem.Allocator
    ) !Bot {

        const game_loop: u32 = response.observation.data.?.game_loop.data.?;
        
        const time = @intToFloat(f32, game_loop) / 22.4;

        const obs: sc2p.ObservationRaw = response.observation.data.?.raw.data.?;
        
        var own_units = std.ArrayList(Unit).init(allocator);
        var own_structures = std.ArrayList(Unit).init(allocator);
        var placeholders = std.ArrayList(Unit).init(allocator);
        var enemy_units = std.ArrayList(Unit).init(allocator);
        var enemy_structures = std.ArrayList(Unit).init(allocator);
        var destructables = std.ArrayList(Unit).init(allocator);
        var mineral_patches = std.ArrayList(Unit).init(allocator);
        var vespene_geysers = std.ArrayList(Unit).init(allocator);
        var watch_towers = std.ArrayList(Unit).init(allocator);

        if (obs.units.data) |units| {
            for (units) |unit| {
                const proto_pos = unit.pos.data.?;
                const position = Point2{
                    .x = proto_pos.x.data.?, 
                    .y = proto_pos.y.data.?
                };
                const z: f32 = proto_pos.z.data.?;
                
                var buff_ids: std.ArrayList(BuffId) = undefined;
                
                if (unit.buff_ids.data) |buffs| {
                    buff_ids = try std.ArrayList(BuffId).initCapacity(allocator, buffs.len);
                    for (buffs) |buff| {
                        buff_ids.appendAssumeCapacity(@intToEnum(BuffId, buff));
                    }
                } else {
                    buff_ids = try std.ArrayList(BuffId).initCapacity(allocator, 0);
                }
                
                var passenger_tags: std.ArrayList(u64) = undefined;
                
                if (unit.passengers.data) |passengers| {
                    passenger_tags = try std.ArrayList(u64).initCapacity(allocator, passengers.len);
                    for (passengers) |passenger| {
                        passenger_tags.appendAssumeCapacity(passenger.tag.data.?);
                    }
                } else {
                    passenger_tags = try std.ArrayList(u64).initCapacity(allocator, 0);
                }

                var orders: std.ArrayList(UnitOrder) = undefined;

                if (unit.orders.data) |orders_proto| {
                    orders = try std.ArrayList(UnitOrder).initCapacity(allocator, orders_proto.len);
                    for (orders_proto) |order_proto| {
                        var target: OrderTarget = undefined;
                        if (order_proto.target_world_space_pos.data) |pos_target| {
                            target = OrderTarget{
                                .position = .{.x = pos_target.x.data.?, .y = pos_target.y.data.?},
                            };
                        } else if (order_proto.target_unit_tag.data) |tag_target| {
                            target = OrderTarget{
                                .tag = tag_target,
                            };
                        } else {
                            target = OrderTarget{
                                .empty = {},
                            };
                        }

                        const order = UnitOrder{
                            .ability_id = @intToEnum(AbilityId, order_proto.ability_id.data orelse 0),
                            .target = target,
                            .progress = order_proto.progress.data orelse 0,
                        };
                        orders.appendAssumeCapacity(order);
                    }
                } else {
                    orders = try std.ArrayList(UnitOrder).initCapacity(allocator, 0);
                }

                var rally_targets: std.ArrayList(RallyTarget) = undefined;
                if (unit.rally_targets.data) |proto_rally_targets| {
                    rally_targets = try std.ArrayList(RallyTarget).initCapacity(allocator, proto_rally_targets.len);

                    for (proto_rally_targets) |proto_target| {
                        const proto_point = proto_target.point.data.?;
                        const rally_target = RallyTarget{
                            .point = .{.x = proto_point.x.data.?, .y = proto_point.y.data.?},
                            .tag = proto_target.tag.data,
                        };
                        rally_targets.appendAssumeCapacity(rally_target);
                    }
                } else {
                    rally_targets = try std.ArrayList(RallyTarget).initCapacity(allocator, 0);
                }

                const u = Unit{
                    .display_type = unit.display_type.data.?,
                    .alliance = unit.alliance.data.?,
                    .tag = unit.tag.data orelse 0,
                    .unit_type = @intToEnum(UnitId, unit.unit_type.data.?),
                    .owner = unit.owner.data orelse 0,

                    .position = position,
                    .z = z,
                    .facing = unit.facing.data orelse 0,
                    .radius = unit.radius.data orelse 0,
                    .build_progress = unit.build_progress.data orelse 0,
                    .cloak = unit.cloak.data orelse CloakState.unknown,
                    .buff_ids = buff_ids.toOwnedSlice(),

                    .detect_range = unit.detect_range.data orelse 0,
                    .radar_range = unit.radar_range.data orelse 0,

                    .is_blip = unit.is_blip.data orelse false,
                    .is_powered = unit.is_powered.data orelse false,
                    .is_active = unit.is_powered.data orelse false,

                    .attack_upgrade_level = unit.attack_upgrade_level.data orelse 0,
                    .armor_upgrade_level = unit.armor_upgrade_level.data orelse 0,
                    .shield_upgrade_level = unit.shield_upgrade_level.data orelse 0,
                    
                    .health = unit.health.data orelse 0,
                    .health_max = unit.health_max.data orelse 10,
                    .shield = unit.shield.data orelse 0,
                    .shield_max = unit.shield_max.data orelse 10,
                    .energy = unit.energy.data orelse 0,
                    .energy_max = unit.energy_max.data orelse 10,

                    .mineral_contents = unit.mineral_contents.data orelse 0,
                    .vespene_contents = unit.vespene_contents.data orelse 0,
                    .is_flying = unit.is_flying.data orelse false,
                    .is_burrowed = unit.is_burrowed.data orelse false,
                    .is_hallucination = unit.is_hallucination.data orelse false,

                    .orders = orders.toOwnedSlice(),
                    .addon_tag = unit.addon_tag.data orelse 0,
                    .passengers = passenger_tags.toOwnedSlice(),
                    .cargo_space_taken = unit.cargo_space_taken.data orelse 0,
                    .cargo_space_max = unit.cargo_space_max.data orelse 0,

                    .assigned_harvesters = unit.assigned_harvesters.data orelse 0,
                    .ideal_harvesters = unit.ideal_harvesters.data orelse 0,
                    .weapon_cooldown = unit.weapon_cooldown.data orelse 0,
                    .engaged_target_tag = unit.engaged_target_tag.data orelse 0,
                    .buff_duration_remain = unit.buff_duration_remain.data orelse 0,
                    .buff_duration_max = unit.buff_duration_max.data orelse 0,
                    .rally_targets = rally_targets.toOwnedSlice(),
                    .available_abilities = &[_]AbilityId{},
                };
                
                const unit_data = game_data.units.get(u.unit_type).?;

                if (u.display_type == DisplayType.placeholder) {
                    try placeholders.append(u);
                    continue;
                }

                switch (u.alliance) {
                    .self, .ally => {
                        if (unit_data.attributes.contains(.structure)) {
                            try own_structures.append(u);
                        } else {
                            try own_units.append(u);
                        }
                    },
                    .enemy => {
                        if (unit_data.attributes.contains(.structure)) {
                            try enemy_structures.append(u);
                        } else {
                            try enemy_units.append(u);
                        }
                    },
                    else => {
                        const mineral_ids = [_]UnitId{
                            .RichMineralField,
                            .RichMineralField750,
                            .MineralField,
                            .MineralField450,
                            .MineralField750,
                            .LabMineralField,
                            .LabMineralField750,
                            .PurifierRichMineralField,
                            .PurifierRichMineralField750,
                            .PurifierMineralField,
                            .PurifierMineralField750,
                            .BattleStationMineralField,
                            .BattleStationMineralField750,
                            .MineralFieldOpaque,
                            .MineralFieldOpaque900,
                        };

                        const geyser_ids = [_]UnitId{
                            .VespeneGeyser,
                            .SpacePlatformGeyser,
                            .RichVespeneGeyser,
                            .ProtossVespeneGeyser,
                            .PurifierVespeneGeyser,
                            .ShakurasVespeneGeyser,
                        };

                        if (u.unit_type == .XelNagaTower) {
                            try watch_towers.append(u);
                        } else if (mem.indexOfScalar(UnitId, mineral_ids[0..], u.unit_type)) |_| {
                            try mineral_patches.append(u);
                        } else if (mem.indexOfScalar(UnitId, geyser_ids[0..], u.unit_type)) |_| {
                            try vespene_geysers.append(u);
                        } else {
                            try destructables.append(u);
                        }
                    }
                }
            }
        }

        var result: ?Result = null;
        if (response.player_result.data) |result_slice| {
            for (result_slice) |result_proto| {
                if (result_proto.player_id.data.? == player_id) {
                    result = result_proto.result.data.?;
                    break;
                }
            }
        }

        const player_common = response.observation.data.?.player_common.data.?;

        return Bot{
            .units = own_units.toOwnedSlice(),
            .structures = own_structures.toOwnedSlice(),
            .placeholders = placeholders.toOwnedSlice(),
            .enemy_units = enemy_units.toOwnedSlice(),
            .enemy_structures = enemy_structures.toOwnedSlice(),
            .destructables = destructables.toOwnedSlice(),
            .vespene_geysers = vespene_geysers.toOwnedSlice(),
            .mineral_patches = mineral_patches.toOwnedSlice(),
            .watch_towers = watch_towers.toOwnedSlice(),
            .game_loop = game_loop,
            .time = time,
            .result = result,
            .minerals = @intCast(i32, player_common.minerals.data orelse 0),
            .vespene = @intCast(i32, player_common.vespene.data orelse 0),
            .food_cap = player_common.food_cap.data orelse 0,
            .food_used = player_common.food_used.data orelse 0,
            .food_army = player_common.food_army.data orelse 0,
            .food_workers = player_common.food_workers.data orelse 0,
            .idle_worker_count = player_common.idle_worker_count.data orelse 0,
            .army_count = player_common.army_count.data orelse 0,
            .warp_gate_count = player_common.warp_gate_count.data orelse 0,
            .larva_count = player_common.larva_count.data orelse 0,
        };
    }

    pub fn getAllOwnUnitTags(self: *Bot, allocator: mem.Allocator) []u64 {
        var tag_slice = allocator.alloc(u64, self.units.len + self.structures.len) catch return &[_]u64{};
        
        for (self.units) |unit, i| {
            tag_slice[i] = unit.tag;
        }

        const unit_count = self.units.len;
        
        for (self.structures) |structure, i| {
            tag_slice[unit_count + i] = structure.tag;
        }

        return tag_slice;
    }

    pub fn setUnitAbilitiesFromProto(self: *Bot, proto: []sc2p.ResponseQueryAvailableAbilities, allocator: mem.Allocator) void {
        
        // These should be in the same order as the tags were given
        // using getAllOwnUnitTags
        const units_count = self.units.len;
        for (proto) |query_proto, i| {
            if (query_proto.abilities.data) |ability_slice_proto| {
                var ability_slice = allocator.alloc(AbilityId, ability_slice_proto.len) catch continue;
                
                for (ability_slice_proto) |ability_proto, j| {
                    ability_slice[j] = @intToEnum(AbilityId, ability_proto.ability_id.data orelse 0);
                }

                if (i < units_count) {
                    self.units[i].available_abilities = ability_slice;
                } else {
                    self.structures[i - units_count].available_abilities = ability_slice;
                }

            }
        }
    }
    
};

pub const Actions = struct {

    const ActionData = struct {
        ability_id: AbilityId,
        target: OrderTarget,
        queue: bool,

        const HashablePoint2 = struct {
            x: i32,
            y: i32,
        };
        
        const HashableOrderTarget = union(OrderType) {
            empty: void,
            position: HashablePoint2,
            tag: u64,
        };

        const HashableActionData = struct {
            ability_id: AbilityId,
            target: HashableOrderTarget,
            queue: bool
        };

        fn toHashable(self: ActionData) HashableActionData {
            
            var target: HashableOrderTarget = undefined;
            switch (self.target) {
                .empty => {
                    target = .{.empty = {}};
                },
                .tag => |tag| {
                    target = .{.tag = tag};
                },
                .position => |pos| {
                    var point = HashablePoint2{
                        .x = @floatToInt(i32, math.round(pos.x * 100)),
                        .y = @floatToInt(i32, math.round(pos.y * 100)),
                    };
                    target = .{.position = point};
                }
            }

            return HashableActionData{
                .ability_id = self.ability_id,
                .target = target,
                .queue = self.queue,
            };
        }
    };

    const BotAction = struct {
        unit: u64,
        data: ActionData,
    };

    const ChatAction = struct {
        message: []const u8,
        channel: Channel,
    };

    temp_allocator: mem.Allocator,
    game_data: GameData,
    order_list: std.ArrayList(BotAction),
    chat_messages: std.ArrayList(ChatAction),
    // Couldn't use an EnumSet due to the enum being non-exhaustive
    // And even if we make it exhaustive it was a problem seemingly
    // due to the size of the underlying enum
    combinable_abilities: std.AutoHashMap(AbilityId, void),
    leave_game: bool = false,

    pub fn init(game_data: GameData, perm_allocator: mem.Allocator, temp_allocator: mem.Allocator) !Actions {

        var ca = std.AutoHashMap(AbilityId, void).init(perm_allocator);
        
        try ca.put(AbilityId.Move, {});
        try ca.put(AbilityId.Move_Move, {});
        try ca.put(AbilityId.Attack, {});
        try ca.put(AbilityId.Scan_Move, {});
        try ca.put(AbilityId.Smart, {});
        try ca.put(AbilityId.Stop, {});
        try ca.put(AbilityId.HoldPosition, {});
        try ca.put(AbilityId.Patrol, {});
        try ca.put(AbilityId.Harvest_Gather, {});
        try ca.put(AbilityId.Harvest_Return, {});
        try ca.put(AbilityId.Effect_Repair, {});
        try ca.put(AbilityId.Rally_Building, {});
        try ca.put(AbilityId.Rally_Units, {});
        try ca.put(AbilityId.Rally_Workers, {});
        try ca.put(AbilityId.Rally_Morphing_Unit, {});
        try ca.put(AbilityId.Lift, {});
        try ca.put(AbilityId.BurrowDown, {});
        try ca.put(AbilityId.BurrowUp, {});
        try ca.put(AbilityId.SiegeMode_SiegeMode, {});
        try ca.put(AbilityId.Unsiege_Unsiege, {});
        try ca.put(AbilityId.Morph_LiberatorAAMode, {});
        try ca.put(AbilityId.Effect_Stim, {});
        try ca.put(AbilityId.Effect_Stim_Marine, {});
        try ca.put(AbilityId.Effect_Stim_Marauder, {});
        try ca.put(AbilityId.Morph_Uproot, {});
        try ca.put(AbilityId.Morph_Archon, {});
        
        return Actions{
            .game_data = game_data,
            .combinable_abilities = ca,
            .temp_allocator = temp_allocator,
            .order_list = try std.ArrayList(BotAction).initCapacity(perm_allocator, 400),
            .chat_messages = try std.ArrayList(ChatAction).initCapacity(perm_allocator, 10),
        };
    }

    pub fn clear(self: *Actions) void {
        self.order_list.clearRetainingCapacity();
        self.chat_messages.clearRetainingCapacity();
    }

    fn addAction(self: *Actions, order: BotAction) void {
        self.order_list.append(order) catch {
            log.err("Failed to add bot action\n", .{});
            return;
        };
    }

    pub fn leaveGame(self: *Actions) void {
        self.leave_game = true;
    }

    pub fn train(self: *Actions, structure_tag: u64, unit_type: UnitId, queue: bool) void {
        const maybe_unit_data = self.game_data.units.get(unit_type);
        if (maybe_unit_data) |unit_data| {
            const action = BotAction{
                .unit = structure_tag,
                .data = .{
                    .ability_id = unit_data.train_ability_id,
                    .target = .{.empty = {}},
                    .queue = queue
                },
            };
            self.addAction(action);
        } else {
            log.debug("Did not find {d} in game data\n", .{unit_type});
        }
    }

    pub fn build(self: *Actions, unit_tag: u64, structure_to_build: UnitId, pos: Point2, queue: bool) void {
        const maybe_structure_data = self.game_data.units.get(structure_to_build);
        if (maybe_structure_data) |structure_data| {
            const action = BotAction{
                .unit = unit_tag,
                .data = .{
                    .ability_id = structure_data.train_ability_id,
                    .target = .{.position = pos},
                    .queue = queue
                },
            };
            self.addAction(action);
        } else {
            log.debug("Did not find {d} in game data\n", .{structure_to_build});
        }
    }

    /// This is mainly for building gas structures. target_tag needs to be the geysir tag
    pub fn buildOnUnit(self: *Actions, unit_tag: u64, structure_to_build: UnitId, target_tag: u64, queue: bool) void {
        const maybe_structure_data = self.game_data.units.get(structure_to_build);
        if (maybe_structure_data) |structure_data| {
            const action = BotAction{
                .unit = unit_tag,
                .data = .{
                    .ability_id = structure_data.train_ability_id,
                    .target = .{.tag = target_tag},
                    .queue = queue
                },
            };
            self.addAction(action);
        } else {
            log.debug("Did not find {d} in game data\n", .{structure_to_build});
        }
    }

    pub fn moveToPosition(self: *Actions, unit_tag: u64, pos: Point2, queue: bool) void {
       const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Move_Move,
                .target = .{.position = pos},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn moveToUnit(self: *Actions, unit_tag: u64, target_tag: u64, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Move_Move,
                .target = .{.tag = target_tag},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn attackPosition(self: *Actions, unit_tag: u64, pos: Point2, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Attack,
                .target = .{.position = pos},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn attackUnit(self: *Actions, unit_tag: u64, target_tag: u64, queue: bool) void {
       const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Attack,
                .target = .{.tag = target_tag},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn holdPosition(self: *Actions, unit_tag: u64, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.HoldPosition,
                .target = .{.empty = {}},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn patrol(self: *Actions, unit_tag: u64, target: Point2, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Patrol,
                .target = .{.position = target},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn research(self: *Actions, structure_tag: u64, upgrade: UpgradeId, queue: bool) void {
        const maybe_upgrade_data = self.game_data.upgrades.get(upgrade);
        if (maybe_upgrade_data) |upgrade_data| {
            const action = BotAction{
                .unit = structure_tag,
                .data = .{
                    .ability_id = upgrade_data.research_ability_id,
                    .target = .{.empty = {}},
                    .queue = queue
                },
            };
            self.addAction(action);
        } else {
            log.debug("Did not find {d} in game data\n", .{upgrade});
        }
    }

    pub fn stop(self: *Actions, unit_tag: u64, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Stop,
                .target = .{.empty = {}},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn repair(self: *Actions, unit_tag: u64, target_tag: u64, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Effect_Repair,
                .target = .{.tag = target_tag},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn useAbility(self: *Actions, unit_tag: u64, ability: AbilityId, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = ability,
                .target = .{.empty = {}},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn useAbilityOnPosition(self: *Actions, unit_tag: u64, ability: AbilityId, target: Point2, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = ability,
                .target = .{.position = target},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn useAbilityOnUnit(self: *Actions, unit_tag: u64, ability: AbilityId, target: u64, queue: bool) void {
        const action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = ability,
                .target = .{.tag = target},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn chat(self: *Actions, channel: Channel, message: []const u8) void {
        var msg_copy = self.temp_allocator.alloc(u8, message.len) catch return;
        mem.copy(u8, msg_copy, message);
        self.chat_messages.append(.{.channel = channel, .message = msg_copy}) catch return;
    }

    pub fn toProto(self: *Actions) ?sc2p.RequestAction {
        if (self.order_list.items.len == 0) return null;

        const combined_length = self.order_list.items.len + self.chat_messages.items.len;
        var action_list = std.ArrayList(sc2p.Action).initCapacity(self.temp_allocator, combined_length) catch return null;
        
        for (self.chat_messages.items) |msg| {
            const action_chat = sc2p.ActionChat{
                .channel = .{.data = msg.channel},
                .message = .{.data = msg.message},
            };
            const action = sc2p.Action{.action_chat = .{.data = action_chat}};
            action_list.appendAssumeCapacity(action);
        }

        // Combine repeat orders
        // Hashing based on the ActionData, value is the index in the next array list
        var action_hashmap = std.AutoHashMap(ActionData.HashableActionData, usize).init(self.temp_allocator);
        var raw_unit_commands = std.ArrayList(sc2p.ActionRawUnitCommand).init(self.temp_allocator);

        for (self.order_list.items) |order| {
            
            const hashable = order.data.toHashable();
            const maybe_index = action_hashmap.get(hashable);

            if (maybe_index) |index| {
                raw_unit_commands.items[index].unit_tags.list.?.append(order.unit) catch break;
            } else {
                var unit_command = sc2p.ActionRawUnitCommand{
                    .ability_id = .{.data = @intCast(i32, @enumToInt(order.data.ability_id))},
                    .queue_command = .{.data = order.data.queue},
                };
                switch (order.data.target) {
                    .position => |pos| {
                        unit_command.target_world_space_pos.data = .{
                            .x = .{.data = pos.x},
                            .y = .{.data = pos.y},
                        };
                    },
                    .tag => |tag| {
                        unit_command.target_unit_tag.data = tag;
                    },
                    else => {}
                }

                unit_command.unit_tags.list = std.ArrayList(u64).initCapacity(self.temp_allocator, 1) catch break;
                unit_command.unit_tags.list.?.appendAssumeCapacity(order.unit);
                raw_unit_commands.append(unit_command) catch break;
                
                if (self.combinable_abilities.contains(order.data.ability_id)) {
                    action_hashmap.put(hashable, raw_unit_commands.items.len - 1) catch break;
                }
            }
        }

        for (raw_unit_commands.items) |*command| {
            command.unit_tags.data = command.unit_tags.list.?.items;
            const action_raw = sc2p.ActionRaw{.unit_command = .{.data = command.*}};
            const action = sc2p.Action{.action_raw = .{.data = action_raw}};
            action_list.appendAssumeCapacity(action);
        }

        const action_request = sc2p.RequestAction{
            .actions = .{.data = action_list.toOwnedSlice()},
        };

        return action_request;
    }

};

pub const GameData = struct {

    pub const UpgradeData = struct {
        id: UpgradeId,
        mineral_cost: i32,
        vespene_cost: i32,
        research_time: f32,
        research_ability_id: AbilityId,
    };

    pub const UnitData = struct {
        id: UnitId,
        cargo_size: i32,
        movement_speed: f32,
        armor: f32,
        air_dps: f32,
        ground_dps: f32,
        mineral_cost: i32,
        vespene_cost: i32,
        food_required: f32,
        train_ability_id: AbilityId,
        race: Race,
        build_time: f32,
        food_provided: f32,
        sight_range: f32,
        attributes: std.EnumSet(Attribute),
    };

    upgrades: std.AutoHashMap(UpgradeId, UpgradeData),
    units: std.AutoHashMap(UnitId, UnitData),

    pub fn fromProto(
        proto:sc2p.ResponseData,
        allocator: mem.Allocator
    ) !GameData {

        var gd = GameData{
            .upgrades = std.AutoHashMap(UpgradeId, UpgradeData).init(allocator),
            .units = std.AutoHashMap(UnitId, UnitData).init(allocator),
        };

        const proto_upgrades = proto.upgrades.data.?;

        for (proto_upgrades) |proto_upgrade| {
            const upg = UpgradeData{
                .id = @intToEnum(UpgradeId, proto_upgrade.upgrade_id.data.?),
                .mineral_cost = @intCast(i32, proto_upgrade.mineral_cost.data orelse 0),
                .vespene_cost = @intCast(i32, proto_upgrade.vespene_cost.data orelse 0),
                .research_time = proto_upgrade.research_time.data orelse 0,
                .research_ability_id = @intToEnum(AbilityId, proto_upgrade.ability_id.data orelse 0),
            };

            try gd.upgrades.put(upg.id, upg);
        }

        const proto_units = proto.units.data.?;

        for (proto_units) |proto_unit| {
            const available = proto_unit.available.data orelse false;
            if (!available) continue;

            var attributes = std.EnumSet(Attribute){};
            
            if (proto_unit.attributes.data) |proto_attrs| {
                for (proto_attrs) |attr| {
                    attributes.insert(attr);
                }
            }

            var air_dps: f32 = 0;
            var ground_dps: f32 = 0;

            //@TODO: May need to do something with battlecruisers
            //and oracles if their weapons don't show up here
            if (proto_unit.weapons.data) |weapons_proto| {
                for (weapons_proto) |weapon_proto| {
                    const target_type = weapon_proto.target_type.data.?;
                    const speed = weapon_proto.speed.data.?;
                    const attacks: f32 = @intToFloat(f32, weapon_proto.attacks.data.?);
                    const damage = weapon_proto.damage.data.?;
                    const dps = (damage*attacks) / speed;
                    switch (target_type) {
                        .ground => {
                            ground_dps = dps;
                        },
                        .air => {
                            air_dps = dps;
                        },
                        .any => {
                            air_dps = dps;
                            ground_dps = dps;
                        },
                    }
                }
            }

            const unit = UnitData{
                .id = @intToEnum(UnitId, proto_unit.unit_id.data.?),
                .cargo_size = @intCast(i32, proto_unit.cargo_size.data orelse 0),
                .movement_speed = proto_unit.movement_speed.data orelse 0,
                .armor = proto_unit.armor.data orelse 0,
                .air_dps = air_dps,
                .ground_dps = ground_dps,
                .mineral_cost = @intCast(i32, proto_unit.mineral_cost.data orelse 0),
                .vespene_cost = @intCast(i32, proto_unit.vespene_cost.data orelse 0),
                .food_required = proto_unit.food_required.data orelse 0,
                .food_provided = proto_unit.food_provided.data orelse 0,
                .train_ability_id = @intToEnum(AbilityId, proto_unit.ability_id.data orelse 0),
                .race = proto_unit.race.data orelse Race.none,
                .build_time = proto_unit.build_time.data orelse 0,
                .sight_range = proto_unit.sight_range.data orelse 0,
                .attributes = attributes,
            };

            try gd.units.put(unit.id, unit);
        }

        return gd;
    }

};