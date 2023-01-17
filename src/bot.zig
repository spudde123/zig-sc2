const std = @import("std");
const assert = std.debug.assert;

const mem = std.mem;
const log = std.log;
const math = std.math;
const PackedIntIo = std.packed_int_array.PackedIntIo;

const ws = @import("client.zig");
const sc2p = @import("sc2proto.zig");
pub const unit_group = @import("units.zig");
pub const grids = @import("grids.zig");

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

pub const Unit = unit_group.Unit;
pub const OrderTarget = unit_group.OrderTarget;
pub const OrderType = unit_group.OrderType;
pub const UnitOrder = unit_group.UnitOrder;
pub const RallyTarget = unit_group.RallyTarget;
pub const Effect = unit_group.Effect;
pub const SensorTower = unit_group.SensorTower;

pub const Grid = grids.Grid;
pub const GridPoint = grids.GridPoint;
pub const Point2 = grids.Point2;
pub const Point3 = grids.Point3;
pub const GridSize = grids.GridSize;
pub const Rectangle = grids.Rectangle;

pub const Color = struct {
    r: u32,
    g: u32,
    b: u32,
};

pub const VisionBlocker = struct {
    points: []GridPoint,
};

pub const Ramp = struct {
    points: []GridPoint,
    top_center: Point2,
    bottom_center: Point2,
    depot_first: ?Point2,
    depot_second: ?Point2,
    // This is the regular barracks placement
    // on top of the ramp
    barracks_middle: ?Point2,
    // This moves the barracks placement if
    // necessary so an addon fits
    barracks_with_addon: ?Point2,
};

const RampsAndVisionBlockers = struct {
    vbs: []VisionBlocker,
    ramps: []Ramp,
};

/// Includes various information
/// about the ongoing match
/// which doesn't change from step to step
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
    vision_blockers: []VisionBlocker,
    ramps: []Ramp,

    const main_base_ramp_size = 16;

    pub fn fromProto(
        proto_data: sc2p.ResponseGameInfo,
        player_id: u32,
        opponent_id: ?[]const u8,
        start_location: Point2,
        minerals: []Unit,
        geysers: []Unit,
        allocator: mem.Allocator,
        temp_alloc: mem.Allocator,
    ) !GameInfo {
        
        const received_map_name = proto_data.map_name.?;
        var map_name = try allocator.alloc(u8, received_map_name.len);
        mem.copy(u8, map_name, received_map_name);

        var copied_opponent_id: ?[]u8 = null;
        if (opponent_id) |received_opponent_id| {
            copied_opponent_id = try allocator.alloc(u8, received_opponent_id.len);
            mem.copy(u8, copied_opponent_id.?, received_opponent_id);
        } 

        var enemy_requested_race: Race = Race.none;
        var enemy_name: ?[]u8 = null;

        for (proto_data.player_info.?) |player_info| {
            if (player_info.player_id.? != player_id) {
                enemy_requested_race = player_info.race_requested.?;

                if (player_info.player_name) |received_enemy_name| {
                    enemy_name = try allocator.alloc(u8, received_enemy_name.len);
                    mem.copy(u8, enemy_name.?, received_enemy_name);
                }

                break;
            }
        }

        const raw_proto = proto_data.start_raw.?;

        const map_size_proto = raw_proto.map_size.?;
        const map_size = GridSize{.w = @intCast(usize, map_size_proto.x.?), .h = @intCast(usize, map_size_proto.y.?)};

        const playable_area_proto = raw_proto.playable_area.?;
        const rect_p0 = playable_area_proto.p0.?;
        const rect_p1 = playable_area_proto.p1.?;

        const playable_area = Rectangle{
            .p0 = .{.x = rect_p0.x.?, .y = rect_p0.y.?},
            .p1 = .{.x = rect_p1.x.?, .y = rect_p1.y.?},
        };

        var start_locations = std.ArrayList(Point2).init(allocator);
        for (raw_proto.start_locations.?) |loc_proto| {
            try start_locations.append(.{
                .x = loc_proto.x.?,
                .y = loc_proto.y.?,
            });
        }

        const terrain_proto = raw_proto.terrain_height.?;
        assert(terrain_proto.bits_per_pixel.? == 8);
        assert(terrain_proto.size.?.x.? == map_size.w);
        assert(terrain_proto.size.?.y.? == map_size.h);
        const terrain_proto_slice = terrain_proto.image.?;
        var terrain_slice = try allocator.alloc(u8, terrain_proto_slice.len);
        mem.copy(u8, terrain_slice, terrain_proto_slice);
        const terrain_height = Grid{.data = terrain_slice, .w = map_size.w, .h = map_size.h};

        const pathing_proto = raw_proto.pathing_grid.?;
        assert(pathing_proto.bits_per_pixel.? == 1);
        assert(pathing_proto.size.?.x.? == map_size.w);
        assert(pathing_proto.size.?.y.? == map_size.h);
        const pathing_proto_slice = pathing_proto.image.?;
        var pathing_slice = try allocator.alloc(u8, @intCast(usize, map_size.w * map_size.h));
        
        const PackedIntType = PackedIntIo(u1, .Big);
        
        var index: usize = 0;
        while (index < map_size.w * map_size.h) : (index += 1) {
            pathing_slice[index] = PackedIntType.get(pathing_proto_slice, index, 0);
        }
        const pathing_grid = Grid{.data = pathing_slice, .w = map_size.w, .h = map_size.h};
        const placement_proto = raw_proto.placement_grid.?;
        assert(placement_proto.bits_per_pixel.? == 1);
        assert(placement_proto.size.?.x.? == map_size.w);
        assert(placement_proto.size.?.y.? == map_size.h);
        const placement_proto_slice = placement_proto.image.?;
        var placement_slice = try allocator.alloc(u8, @intCast(usize, map_size.w * map_size.h));
        index = 0;
        while (index < map_size.w * map_size.h) : (index += 1) {
            placement_slice[index] = PackedIntType.get(placement_proto_slice, index, 0);
        }
        const placement_grid = Grid{.data = placement_slice, .w = map_size.w, .h = map_size.h};

        const ramps_and_vbs = try generateRamps(
            pathing_grid,
            placement_grid,
            terrain_height,
            allocator,
            temp_alloc,
        );

        return GameInfo{
            .map_name = map_name,
            .opponent_id = copied_opponent_id,
            .enemy_name = enemy_name orelse "Unknown",
            .enemy_requested_race = enemy_requested_race,
            .enemy_race = enemy_requested_race,
            .map_size = map_size,
            .playable_area = playable_area,
            .start_location = start_location,
            .enemy_start_locations = start_locations.toOwnedSlice(),
            .terrain_height = terrain_height,
            .pathing_grid = pathing_grid,
            .placement_grid = placement_grid,
            .expansion_locations = generateExpansionLocations(minerals, geysers, allocator),
            .vision_blockers = ramps_and_vbs.vbs,
            .ramps = ramps_and_vbs.ramps,
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

        return result;
    }

    fn generateRamps(
        pathing: Grid,
        placement: Grid,
        terrain_height: Grid,
        perm_alloc: mem.Allocator,
        temp_alloc: mem.Allocator,
    ) !RampsAndVisionBlockers {
        //@TODO: Need to remove rocks and minerals from ramps
        //in the pathing grid
        var groups = try temp_alloc.alloc(u8, pathing.data.len);
        mem.set(u8, groups, 0);

        var flood_fill_list = std.ArrayList(usize).init(temp_alloc);
        var group_count: u8 = 0;

        var current_group = std.BoundedArray(usize, 256){};

        var vbs = std.ArrayList(VisionBlocker).init(perm_alloc);
        var ramps = std.ArrayList(Ramp).init(perm_alloc);

        for (pathing.data) |pathing_val, i| {
            const placement_val = placement.data[i];
            // If we find a legitimate starting point do a flood fill
            // from there
            if (pathing_val == 1 and placement_val == 0 and groups[i] == 0) {
                group_count += 1;
                groups[i] = group_count;

                try flood_fill_list.append(i);
                try current_group.resize(0);
                try current_group.append(i);

                while (flood_fill_list.items.len > 0) {
                    const cur = flood_fill_list.pop();
                    const neighbors = [_]usize{
                        cur + 1,
                        cur - 1,
                        cur - pathing.w,
                        cur - pathing.w - 1,
                        cur - pathing.w + 1,
                        cur + pathing.w,
                        cur + pathing.w - 1,
                        cur + pathing.w + 1,
                    };
                    for (neighbors) |neighbor| {
                        const neighbor_pathing = pathing.data[neighbor];
                        const neighbor_placement = placement.data[neighbor];
                        const neighbor_group = groups[neighbor];
                        if (neighbor_pathing == 1 and neighbor_placement == 0 and neighbor_group == 0) {
                            try current_group.append(neighbor);
                            groups[neighbor] = group_count;
                            try flood_fill_list.append(neighbor);
                        }
                    }
                }

                // Check if this group has points in uneven terrain indicating a ramp

                const current_group_slice = current_group.slice();
                const terrain_reference = terrain_height.data[current_group.get(0)];
                var same_height = true;
                var max_height = terrain_reference;
                var min_height = terrain_reference;

                for (current_group_slice) |point| {
                    const height_val = terrain_height.data[point];

                    if (height_val > max_height) {
                        same_height = false;
                        max_height = height_val;
                    } else if (height_val < min_height) {
                        same_height = false;
                        min_height = height_val;
                    }
                }

                const grid_width = terrain_height.w;

                if (same_height) {
                    var points = try perm_alloc.alloc(GridPoint, current_group.len);
                    for (current_group_slice) |point, j| {
                        const x = @intCast(i32, @mod(point, grid_width));
                        const y = @intCast(i32, @divFloor(point, grid_width));
                        points[j] = GridPoint{.x = x, .y = y};
                    }
                    const vision_blocker = VisionBlocker{.points = points};
                    try vbs.append(vision_blocker);
                } else {
                    if (current_group.len < 8) continue;
                    var points = try perm_alloc.alloc(GridPoint, current_group.len);

                    var max_count: f32 = 0;
                    var min_count: f32 = 0;
                    var x_max: f32 = 0;
                    var y_max: f32 = 0;
                    var x_min: f32 = 0;
                    var y_min: f32 = 0;

                    for (current_group_slice) |point, j| {
                        const x = @intCast(i32, @mod(point, grid_width));
                        const y = @intCast(i32, @divFloor(point, grid_width));
                        points[j] = GridPoint{.x = x, .y = y};

                        const height_val = terrain_height.data[point];
                        if (height_val == max_height) {
                            max_count += 1;
                            x_max += @intToFloat(f32, x) + 0.5;
                            y_max += @intToFloat(f32, y) + 0.5;
                        } else if (height_val == min_height) {
                            min_count += 1;
                            x_min += @intToFloat(f32, x) + 0.5;
                            y_min += @intToFloat(f32, y) + 0.5;
                        }
                    }
                    
                    const bottom_center = Point2{.x = x_min / min_count, .y = y_min / min_count};
                    const top_center = Point2{.x = x_max / max_count, .y = y_max / max_count};

                    var depot_first: ?Point2 = null;
                    var depot_second: ?Point2 = null;
                    var barracks_middle: ?Point2 = null;
                    var barracks_with_addon: ?Point2 = null;

                    // Only main base ramps will have depot
                    // and barracks locations set
                    if (points.len == main_base_ramp_size) {
                        const ramp_dir = top_center.subtract(bottom_center).normalize();

                        const depot_candidate1 = top_center.add(ramp_dir.rotate(math.pi / 2.0).multiply(2)).floor();
                        const depot_index1 = placement.pointToIndex(depot_candidate1);
                        depot_first = searchDepotPosition(placement, points, depot_index1);                        

                        const depot_candidate2 = top_center.add(ramp_dir.rotate(-math.pi / 2.0).multiply(2)).floor();
                        const depot_index2 = placement.pointToIndex(depot_candidate2);
                        depot_second = searchDepotPosition(placement, points, depot_index2); 
                        
                        barracks_middle = top_center.add(ramp_dir.multiply(2)).floor().add(.{.x = 0.5, .y = 0.5});
                        
                        const depot_max_x = math.max(depot_first.?.x, depot_second.?.x);
                        
                        const can_fit_addon = barracks_middle.?.x + 1 > depot_max_x;
                        barracks_with_addon = if (can_fit_addon) barracks_middle else barracks_middle.?.add(.{.x = -2, .y = 0});
                    }

                    const ramp = Ramp{
                        .points = points,
                        .top_center = top_center,
                        .bottom_center = bottom_center,
                        .depot_first = depot_first,
                        .depot_second = depot_second,
                        .barracks_middle = barracks_middle,
                        .barracks_with_addon = barracks_with_addon,
                    };

                    try ramps.append(ramp);
                }
            }    
        }

        return RampsAndVisionBlockers{
            .vbs = vbs.toOwnedSlice(),
            .ramps = ramps.toOwnedSlice(),
        };
    }

    fn searchDepotPosition(placement: Grid, ramp_points: []const GridPoint, depot_index: usize) Point2 {
        var res = Point2{.x = 0, .y = 0};
        var max_blocked_neighbors: u64 = 0;

        const grid_width = placement.w;
        const grid_width_i32 = @intCast(i32, placement.w);
        const offsets = [_]i32{
            0,
            1,
            -1,
            grid_width_i32,
            -grid_width_i32,
            grid_width_i32 + 1,
            grid_width_i32 - 1,
            -grid_width_i32 - 1,
            -grid_width_i32 + 1
        };
        
        assert(ramp_points.len == main_base_ramp_size);
        var ramp_points_usize: [main_base_ramp_size]usize = undefined;
        for (ramp_points) |point, i| {
            const x = @intCast(usize, point.x);
            const y = @intCast(usize, point.y);
            ramp_points_usize[i] = x + y*grid_width;
        }

        for (offsets) |offset| {
            const current_index = @intCast(usize, @intCast(i32, depot_index) + offset);
            var depot_points = [_]usize{
                current_index,
                current_index + 1,
                current_index + grid_width,
                current_index + grid_width + 1,
            };
            var edge = [_]usize{
                current_index - grid_width - 1,
                current_index - grid_width,
                current_index - grid_width + 1,
                current_index - grid_width + 2,
                current_index + 2,
                current_index + grid_width + 2,
                current_index + 2*grid_width + 2,
                current_index + 2*grid_width + 1,
                current_index + 2*grid_width,
                current_index + 2*grid_width - 1,
                current_index + grid_width - 1,
                current_index - 1,
            };
            var ramp_neighbors: u64 = 0;
            for (edge) |edge_point| {
                if (mem.indexOfScalar(usize, &ramp_points_usize, edge_point)) |_| ramp_neighbors += 1;
            }
            if (placement.allEqual(depot_points[0..], 1) and ramp_neighbors > max_blocked_neighbors) {
                max_blocked_neighbors = ramp_neighbors;
                res = placement.indexToPoint(current_index + grid_width + 1);
            }
        }
        return res;
    }

    pub fn update(bot: Bot) void {
        _ = bot;
    }

    pub fn getTerrainZ(self: GameInfo, pos: Point2) f32 {
        const x = @floatToInt(usize, math.floor(pos.x));
        const y = @floatToInt(usize, math.floor(pos.y));
        
        assert(x >= 0 and x < self.terrain_height.w);
        assert(y >= 0 and y < self.terrain_height.h);

        const terrain_grid_width = self.terrain_height.w;
        const grid_index = x + y * terrain_grid_width;
        const terrain_value = @intToFloat(f32, self.terrain_height.data[grid_index]);
        return -16 + 32*terrain_value / 255;
    }

    pub fn getMainBaseRamp(self: GameInfo) Ramp {
        var closest_dist: f32 = math.f32_max;
        var main_base_ramp: Ramp = undefined;
        for (self.ramps) |ramp| {
            const dist = self.start_location.distanceSquaredTo(ramp.top_center);
            if(ramp.points.len == main_base_ramp_size and dist < closest_dist) {
                closest_dist = dist;
                main_base_ramp = ramp;
            }
        }
        return main_base_ramp;
    }

    pub fn getEnemyMainBaseRamp(self: GameInfo) Ramp {
        var closest_dist: f32 = math.f32_max;
        var main_base_ramp: Ramp = undefined;
        for (self.ramps) |ramp| {
            const dist = self.enemy_start_locations[0].distanceSquaredTo(ramp.top_center);
            if(ramp.points.len == main_base_ramp_size and dist < closest_dist) {
                closest_dist = dist;
                main_base_ramp = ramp;
            }
        }
        return main_base_ramp;
    }

    
};

/// Includes all the step by step information
/// in the game. Your own and enemy units are
/// held in an ArrayHashMap, so we can both
/// iterate through them quickly and
/// quickly identify units with their tags
pub const Bot = struct {
    units: std.AutoArrayHashMap(u64, Unit),
    enemy_units: std.AutoArrayHashMap(u64, Unit),
    placeholders: []Unit,
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

    pending_units: std.AutoHashMap(UnitId, usize),
    pending_upgrades: std.AutoHashMap(UpgradeId, f32),

    visibility: Grid,
    creep: Grid,

    // Giving the previous unit structs
    // if we don't keep the data in the current frame
    // anymore. Otherwise the tag is enough.
    dead_units: []Unit,
    units_created: []u64,
    damaged_units: []u64,
    construction_complete: []u64,
    enemies_entered_vision: []u64,
    enemies_left_vision: []Unit,

    effects: []Effect,
    sensor_towers: []SensorTower,

    result: ?Result,

    pub fn fromProto(
        prev_units: *std.AutoArrayHashMap(u64, Unit),
        prev_enemy: *std.AutoArrayHashMap(u64, Unit),
        response: sc2p.ResponseObservation,
        game_data: GameData,
        player_id: u32,
        allocator: mem.Allocator
    ) !Bot {

        const game_loop: u32 = response.observation.?.game_loop.?;
        
        const time = @intToFloat(f32, game_loop) / 22.4;

        const obs: sc2p.ObservationRaw = response.observation.?.raw.?;
        
        var placeholders = std.ArrayList(Unit).init(allocator);
        var destructables = std.ArrayList(Unit).init(allocator);
        var mineral_patches = std.ArrayList(Unit).init(allocator);
        var vespene_geysers = std.ArrayList(Unit).init(allocator);
        var watch_towers = std.ArrayList(Unit).init(allocator);
        var pending_units = std.AutoHashMap(UnitId, usize).init(allocator);
        var pending_upgrades = std.AutoHashMap(UpgradeId, f32).init(allocator);
        var units_created = std.ArrayList(u64).init(allocator);
        var damaged_units = std.ArrayList(u64).init(allocator);
        var construction_complete = std.ArrayList(u64).init(allocator);
        var enemies_entered_vision = std.ArrayList(u64).init(allocator);
        var enemies_left_vision = std.ArrayList(Unit).init(allocator); 
        var dead_units = std.ArrayList(Unit).init(allocator);

        if (obs.units) |units| {
            for (units) |unit| {
                const proto_pos = unit.pos.?;
                const position = Point2{
                    .x = proto_pos.x.?, 
                    .y = proto_pos.y.?
                };
                const z: f32 = proto_pos.z.?;
                
                var buff_ids: std.ArrayList(BuffId) = undefined;
                
                if (unit.buff_ids) |buffs| {
                    buff_ids = try std.ArrayList(BuffId).initCapacity(allocator, buffs.len);
                    for (buffs) |buff| {
                        buff_ids.appendAssumeCapacity(@intToEnum(BuffId, buff));
                    }
                } else {
                    buff_ids = try std.ArrayList(BuffId).initCapacity(allocator, 0);
                }
                
                var passenger_tags: std.ArrayList(u64) = undefined;
                
                if (unit.passengers) |passengers| {
                    passenger_tags = try std.ArrayList(u64).initCapacity(allocator, passengers.len);
                    for (passengers) |passenger| {
                        passenger_tags.appendAssumeCapacity(passenger.tag.?);
                    }
                } else {
                    passenger_tags = try std.ArrayList(u64).initCapacity(allocator, 0);
                }

                var orders: std.ArrayList(UnitOrder) = undefined;

                if (unit.orders) |orders_proto| {
                    orders = try std.ArrayList(UnitOrder).initCapacity(allocator, orders_proto.len);
                    for (orders_proto) |order_proto| {
                        var target: OrderTarget = undefined;
                        if (order_proto.target_world_space_pos) |pos_target| {
                            target = OrderTarget{
                                .position = .{.x = pos_target.x.?, .y = pos_target.y.?},
                            };
                        } else if (order_proto.target_unit_tag) |tag_target| {
                            target = OrderTarget{
                                .tag = tag_target,
                            };
                        } else {
                            target = OrderTarget{
                                .empty = {},
                            };
                        }

                        const order = UnitOrder{
                            .ability_id = @intToEnum(AbilityId, order_proto.ability_id orelse 0),
                            .target = target,
                            .progress = order_proto.progress orelse 0,
                        };
                        orders.appendAssumeCapacity(order);
                    }
                } else {
                    orders = try std.ArrayList(UnitOrder).initCapacity(allocator, 0);
                }

                var rally_targets: std.ArrayList(RallyTarget) = undefined;
                if (unit.rally_targets) |proto_rally_targets| {
                    rally_targets = try std.ArrayList(RallyTarget).initCapacity(allocator, proto_rally_targets.len);

                    for (proto_rally_targets) |proto_target| {
                        const proto_point = proto_target.point.?;
                        const rally_target = RallyTarget{
                            .point = .{.x = proto_point.x.?, .y = proto_point.y.?},
                            .tag = proto_target.tag,
                        };
                        rally_targets.appendAssumeCapacity(rally_target);
                    }
                } else {
                    rally_targets = try std.ArrayList(RallyTarget).initCapacity(allocator, 0);
                }

                const unit_type = @intToEnum(UnitId, unit.unit_type.?);
                const unit_data = game_data.units.get(unit_type).?;

                const u = Unit{
                    .display_type = unit.display_type.?,
                    .alliance = unit.alliance.?,
                    .tag = unit.tag orelse 0,
                    .unit_type = unit_type,
                    .owner = unit.owner orelse 0,
                    .prev_seen_loop = game_loop,

                    .position = position,
                    .z = z,
                    .facing = unit.facing orelse 0,
                    .radius = unit.radius orelse 0,
                    .build_progress = unit.build_progress orelse 0,
                    .cloak = unit.cloak orelse CloakState.unknown,
                    .buff_ids = buff_ids.toOwnedSlice(),

                    .detect_range = unit.detect_range orelse 0,
                    .radar_range = unit.radar_range orelse 0,

                    .is_blip = unit.is_blip orelse false,
                    .is_powered = unit.is_powered orelse false,
                    .is_active = unit.is_powered orelse false,
                    .is_structure = unit_data.attributes.contains(.structure),

                    .attack_upgrade_level = unit.attack_upgrade_level orelse 0,
                    .armor_upgrade_level = unit.armor_upgrade_level orelse 0,
                    .shield_upgrade_level = unit.shield_upgrade_level orelse 0,
                    
                    .health = unit.health orelse 0,
                    .health_max = unit.health_max orelse 10,
                    .shield = unit.shield orelse 0,
                    .shield_max = unit.shield_max orelse 10,
                    .energy = unit.energy orelse 0,
                    .energy_max = unit.energy_max orelse 10,

                    .mineral_contents = unit.mineral_contents orelse 0,
                    .vespene_contents = unit.vespene_contents orelse 0,
                    .is_flying = unit.is_flying orelse false,
                    .is_burrowed = unit.is_burrowed orelse false,
                    .is_hallucination = unit.is_hallucination orelse false,

                    .orders = orders.toOwnedSlice(),
                    .addon_tag = unit.addon_tag orelse 0,
                    .passengers = passenger_tags.toOwnedSlice(),
                    .cargo_space_taken = unit.cargo_space_taken orelse 0,
                    .cargo_space_max = unit.cargo_space_max orelse 0,

                    .assigned_harvesters = unit.assigned_harvesters orelse 0,
                    .ideal_harvesters = unit.ideal_harvesters orelse 0,
                    .weapon_cooldown = unit.weapon_cooldown orelse 0,
                    .engaged_target_tag = unit.engaged_target_tag orelse 0,
                    .buff_duration_remain = unit.buff_duration_remain orelse 0,
                    .buff_duration_max = unit.buff_duration_max orelse 0,
                    .rally_targets = rally_targets.toOwnedSlice(),
                    .available_abilities = &[_]AbilityId{},
                };
                
                if (u.display_type == DisplayType.placeholder) {
                    try placeholders.append(u);
                    continue;
                }

                // Add both buildings and units under construction/morph
                // to a map so we can see how many we are producing
                switch (u.alliance) {
                    .self, .ally => {
                        const prev = try prev_units.getOrPut(u.tag);
                        if (!prev.found_existing) {
                            try units_created.append(u.tag);
                        } else {
                            if (u.build_progress >= 1 and prev.value_ptr.build_progress < 1) {
                                try construction_complete.append(u.tag);
                            }
                            if (u.health < prev.value_ptr.health) {
                                try damaged_units.append(u.tag);
                            }
                        }
                        prev.value_ptr.* = u;

                        if (u.is_structure) {
                            // Terran buildings are already calculated via
                            // scv orders below
                            if (u.build_progress < 1 and unit_data.race != .terran) {
                                if (pending_units.get(u.unit_type)) |pending_count| {
                                    try pending_units.put(u.unit_type, pending_count + 1);
                                } else {
                                    try pending_units.put(u.unit_type, 1);
                                }
                            } else {
                                for (u.orders) |order| {
                                    if (game_data.build_map.get(order.ability_id)) |training_unit_id| {
                                        if (pending_units.get(training_unit_id)) |pending_count| {
                                            try pending_units.put(training_unit_id, pending_count + 1);
                                        } else {
                                            try pending_units.put(training_unit_id, 1);
                                        }
                                    }

                                    if (game_data.upgrade_map.get(order.ability_id)) |ongoing_upgrade_id| {
                                        try pending_upgrades.put(ongoing_upgrade_id, order.progress);
                                    }
                                }
                            }
                        } else {
                            if (u.build_progress < 1) {
                                if (pending_units.get(u.unit_type)) |pending_count| {
                                    try pending_units.put(u.unit_type, pending_count + 1);
                                } else {
                                    try pending_units.put(u.unit_type, 1);
                                }
                            } else {
                                for (u.orders) |order| {
                                    if (game_data.build_map.get(order.ability_id)) |training_unit_id| {
                                        if (pending_units.get(training_unit_id)) |pending_count| {
                                            try pending_units.put(training_unit_id, pending_count + 1);
                                        } else {
                                            try pending_units.put(training_unit_id, 1);
                                        }
                                    }
                                }
                            }
                            
                        }
                    },
                    .enemy => {
                        const prev = try prev_enemy.getOrPut(u.tag);
                        prev.value_ptr.* = u;
                        if (!prev.found_existing) {
                            try enemies_entered_vision.append(u.tag);
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
        if (response.player_result) |result_slice| {
            for (result_slice) |result_proto| {
                if (result_proto.player_id.? == player_id) {
                    result = result_proto.result.?;
                    break;
                }
            }
        }

        const upgrade_proto = obs.player.?.upgrade_ids;
        if (upgrade_proto) |upgrade_slice| {
            for (upgrade_slice) |upgrade| {
                const upgrade_id = @intToEnum(UpgradeId, upgrade);
                try pending_upgrades.put(upgrade_id, 1);
            }
        }

        const visibility_proto = obs.map_state.?.visibility.?;
        assert(visibility_proto.bits_per_pixel.? == 8);

        const grid_size_proto = visibility_proto.size.?;
        const grid_width = @intCast(usize, grid_size_proto.x.?);
        const grid_height = @intCast(usize, grid_size_proto.y.?);

        var visibility_data = try allocator.dupe(u8, visibility_proto.image.?);
        const visibility_grid = Grid{.data = visibility_data, .w = grid_width, .h = grid_height};

        const creep_proto = obs.map_state.?.creep.?;
        assert(creep_proto.bits_per_pixel.? == 1);
        const creep_proto_slice = creep_proto.image.?;
        var creep_data = try allocator.alloc(u8, grid_width*grid_height);
        const PackedIntType = PackedIntIo(u1, .Big);
        
        var index: usize = 0;
        while (index < grid_width * grid_height) : (index += 1) {
            creep_data[index] = PackedIntType.get(creep_proto_slice, index, 0);
        }
        const creep_grid = Grid{.data = creep_data, .w = grid_width, .h = grid_height};

        const effects_proto = obs.effects;
        var effects: []Effect = &[_]Effect{};
        if (effects_proto) |effect_proto_slice| {
            effects = try allocator.alloc(Effect, effect_proto_slice.len);
            for (effect_proto_slice) |effect_proto, effect_index| {
                var points = try allocator.alloc(Point2, effect_proto.pos.?.len);
                for (effect_proto.pos.?) |pos_proto, pos_index| {
                    points[pos_index] = Point2{.x = pos_proto.x.?, .y = pos_proto.y.?};
                }
                effects[effect_index] = Effect{
                    .id = @intToEnum(EffectId, effect_proto.effect_id.?),
                    .alliance = effect_proto.alliance.?,
                    .positions = points,
                    .radius = effect_proto.radius.?,
                };
            }
        }

        var sensor_towers: []SensorTower = &[_]SensorTower{};
        if (obs.radars) |sensor_towers_proto| {
            sensor_towers = try allocator.alloc(SensorTower, sensor_towers_proto.len);
            for (sensor_towers_proto) |tower_proto, tower_index| {
                sensor_towers[tower_index] = SensorTower{
                    .position = Point2{.x = tower_proto.pos.?.x.?, .y = tower_proto.pos.?.y.?},
                    .radius = tower_proto.radius.?,
                };
            }
        }

        var dead_unit_tags: []u64 = &[_]u64{};
        if (obs.event) |events_proto| {
            if (events_proto.dead_units) |dead_unit_slice| {
                dead_unit_tags = dead_unit_slice;
            }
        }

        const player_common = response.observation.?.player_common.?;

        var enemy_iter = prev_enemy.iterator();
        while (enemy_iter.next()) |enemy_val| {
            if (enemy_val.value_ptr.prev_seen_loop == game_loop) continue;
            if (mem.indexOfScalar(u64, dead_unit_tags, enemy_val.value_ptr.tag)) |_| {
                try dead_units.append(enemy_val.value_ptr.*);
            } else {
                try enemies_left_vision.append(enemy_val.value_ptr.*);
            }

            prev_enemy.swapRemoveAt(enemy_iter.index - 1);
            enemy_iter.index -= 1;
            enemy_iter.len -= 1;
        }

        var units_iter = prev_units.iterator();
        while (units_iter.next()) |unit_val| {
            if (unit_val.value_ptr.prev_seen_loop == game_loop) continue;
            if (mem.indexOfScalar(u64, dead_unit_tags, unit_val.value_ptr.tag)) |_| {
                try dead_units.append(unit_val.value_ptr.*);
            }
            prev_units.swapRemoveAt(units_iter.index - 1);
            units_iter.index -= 1;
            units_iter.len -= 1;
        }

        return Bot{
            .units = prev_units.*,
            .enemy_units = prev_enemy.*,
            .placeholders = placeholders.toOwnedSlice(),
            .destructables = destructables.toOwnedSlice(),
            .vespene_geysers = vespene_geysers.toOwnedSlice(),
            .mineral_patches = mineral_patches.toOwnedSlice(),
            .watch_towers = watch_towers.toOwnedSlice(),
            .game_loop = game_loop,
            .time = time,
            .result = result,
            .minerals = @intCast(i32, player_common.minerals orelse 0),
            .vespene = @intCast(i32, player_common.vespene orelse 0),
            .food_cap = player_common.food_cap orelse 0,
            .food_used = player_common.food_used orelse 0,
            .food_army = player_common.food_army orelse 0,
            .food_workers = player_common.food_workers orelse 0,
            .idle_worker_count = player_common.idle_worker_count orelse 0,
            .army_count = player_common.army_count orelse 0,
            .warp_gate_count = player_common.warp_gate_count orelse 0,
            .larva_count = player_common.larva_count orelse 0,
            .pending_units = pending_units,
            .pending_upgrades = pending_upgrades,
            .visibility = visibility_grid,
            .creep = creep_grid,
            .dead_units = dead_units.toOwnedSlice(),
            .units_created = units_created.toOwnedSlice(),
            .damaged_units = damaged_units.toOwnedSlice(),
            .construction_complete = construction_complete.toOwnedSlice(),
            .enemies_entered_vision = enemies_entered_vision.toOwnedSlice(),
            .enemies_left_vision = enemies_left_vision.toOwnedSlice(),
            .effects = effects,
            .sensor_towers = sensor_towers,
        };
    }

    pub fn setUnitAbilitiesFromProto(self: *Bot, proto: []sc2p.ResponseQueryAvailableAbilities, allocator: mem.Allocator) void {
        
        // These should be in the same order as the tags were given
        // using keys()
        var unit_slice = self.units.values();
        for (proto) |query_proto, i| {
            if (query_proto.abilities) |ability_slice_proto| {
                var ability_slice = allocator.alloc(AbilityId, ability_slice_proto.len) catch continue;
                
                for (ability_slice_proto) |ability_proto, j| {
                    ability_slice[j] = @intToEnum(AbilityId, ability_proto.ability_id orelse 0);
                }

                unit_slice[i].available_abilities = ability_slice;
            }
        }
    }

    pub fn unitsPending(self: Bot, id: UnitId) usize {
        return self.pending_units.get(id) orelse 0;
    }

    pub fn upgradePending(self: Bot, id: UpgradeId) f32 {
        return self.pending_upgrades.get(id) orelse 0;
    }
    
};

/// Call functions in this struct to
/// interact with the sc2 client by giving
/// unit orders, finding building placements,
/// making debug queries
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
    debug_texts: std.ArrayList(sc2p.DebugText),
    debug_lines: std.ArrayList(sc2p.DebugLine),
    debug_boxes: std.ArrayList(sc2p.DebugBox),
    debug_spheres: std.ArrayList(sc2p.DebugSphere),
    debug_create_unit: std.ArrayList(sc2p.DebugCreateUnit),
    // Couldn't use an EnumSet due to the enum being non-exhaustive
    // And even if we make it exhaustive it was a problem seemingly
    // due to the size of the underlying enum
    combinable_abilities: std.AutoHashMap(AbilityId, void),
    leave_game: bool = false,
    client: *ws.WebSocketClient,

    pub fn init(game_data: GameData, client: *ws.WebSocketClient, perm_allocator: mem.Allocator, temp_allocator: mem.Allocator) !Actions {

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
            .client = client,
            .combinable_abilities = ca,
            .temp_allocator = temp_allocator,
            .order_list = try std.ArrayList(BotAction).initCapacity(perm_allocator, 400),
            .chat_messages = try std.ArrayList(ChatAction).initCapacity(perm_allocator, 10),
            .debug_texts = std.ArrayList(sc2p.DebugText).init(temp_allocator),
            .debug_lines = std.ArrayList(sc2p.DebugLine).init(temp_allocator),
            .debug_boxes = std.ArrayList(sc2p.DebugBox).init(temp_allocator),
            .debug_spheres = std.ArrayList(sc2p.DebugSphere).init(temp_allocator),
            .debug_create_unit = std.ArrayList(sc2p.DebugCreateUnit).init(temp_allocator),
        };
    }

    pub fn clear(self: *Actions) void {
        self.order_list.clearRetainingCapacity();
        self.chat_messages.clearRetainingCapacity();
        self.debug_texts.clearAndFree();
        self.debug_lines.clearAndFree();
        self.debug_boxes.clearAndFree();
        self.debug_spheres.clearAndFree();
        self.debug_create_unit.clearAndFree();
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
        if (self.game_data.units.get(unit_type)) |unit_data| {
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
        if (self.game_data.units.get(structure_to_build)) |structure_data| {
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
        if (self.game_data.units.get(structure_to_build)) |structure_data| {
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
        if (self.game_data.upgrades.get(upgrade)) |upgrade_data| {
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

    pub fn tagGame(self: *Actions, tag: []const u8) void {
        const msg = std.fmt.allocPrint(self.temp_allocator, "Tag:{s}", .{tag}) catch return;
        self.chat_messages.append(.{.channel = .broadcast, .message = msg}) catch return;
    }

    pub fn toProto(self: *Actions) ?sc2p.RequestAction {
        if (self.order_list.items.len == 0 and self.chat_messages.items.len == 0) return null;

        const combined_length = self.order_list.items.len + self.chat_messages.items.len;
        var action_list = std.ArrayList(sc2p.Action).initCapacity(self.temp_allocator, combined_length) catch return null;
        
        for (self.chat_messages.items) |msg| {
            const action_chat = sc2p.ActionChat{
                .channel = msg.channel,
                .message = msg.message,
            };
            const action = sc2p.Action{.action_chat = action_chat};
            action_list.appendAssumeCapacity(action);
        }

        // Combine repeat orders
        // Hashing based on the ActionData, value is the index in the next array list
        var action_hashmap = std.AutoHashMap(ActionData.HashableActionData, usize).init(self.temp_allocator);
        var raw_unit_commands = std.ArrayList(sc2p.ActionRawUnitCommand).init(self.temp_allocator);
        var unit_lists = std.ArrayList(std.ArrayList(u64)).initCapacity(self.temp_allocator, self.order_list.items.len) catch return null;
        
        for (self.order_list.items) |order| {
            
            const hashable = order.data.toHashable();

            if (action_hashmap.get(hashable)) |index| {
                unit_lists.items[index].append(order.unit) catch break;
            } else {
                var unit_command = sc2p.ActionRawUnitCommand{
                    .ability_id = @intCast(i32, @enumToInt(order.data.ability_id)),
                    .queue_command = order.data.queue,
                };
                switch (order.data.target) {
                    .position => |pos| {
                        unit_command.target_world_space_pos = .{
                            .x = pos.x,
                            .y = pos.y,
                        };
                    },
                    .tag => |tag| {
                        unit_command.target_unit_tag = tag;
                    },
                    else => {}
                }

                var new_list = std.ArrayList(u64).initCapacity(self.temp_allocator, 1) catch break;
                new_list.appendAssumeCapacity(order.unit);
                unit_lists.appendAssumeCapacity(new_list);
                raw_unit_commands.append(unit_command) catch break;
                
                if (self.combinable_abilities.contains(order.data.ability_id)) {
                    action_hashmap.put(hashable, raw_unit_commands.items.len - 1) catch break;
                }
            }
        }

        for (raw_unit_commands.items) |*command, i| {
            command.unit_tags = unit_lists.items[i].items;
            const action_raw = sc2p.ActionRaw{.unit_command = command.*};
            const action = sc2p.Action{.action_raw = action_raw};
            action_list.appendAssumeCapacity(action);
        }

        const action_request = sc2p.RequestAction{
            .actions = action_list.toOwnedSlice(),
        };

        return action_request;
    }

    pub fn debugTextWorld(self: *Actions, text: []const u8, pos: Point3, color: Color, size: u32) void {
        const color_proto = sc2p.Color{
            .r = color.r,
            .g = color.g,
            .b = color.b,
        };
        const pos_proto = sc2p.Point{
            .x = pos.x,
            .y = pos.y,
            .z = pos.z,
        };
        var proto = sc2p.DebugText{
            .color = color_proto,
            .text = text,
            .world_pos = pos_proto,
            .size = size,
        };
        self.debug_texts.append(proto) catch return;
    }

    pub fn debugTextScreen(self: *Actions, text: []const u8, pos: Point2, color: Color, size: u32) void {
        const color_proto = sc2p.Color{
            .r = color.r,
            .g = color.g,
            .b = color.b,
        };
        const pos_proto = sc2p.Point{
            .x = pos.x,
            .y = pos.y,
            .z = 0,
        };
        const proto = sc2p.DebugText{
            .color = color_proto,
            .text = text,
            .virtual_pos = pos_proto,
            .size = size,
        };
        self.debug_texts.append(proto) catch return;
    }

    pub fn debugLine(self: *Actions, start: Point3, end: Point3, color: Color) void {
        const line = sc2p.Line{
            .p0 = .{
                .x = start.x,
                .y = start.y,
                .z = start.z,
            },
            .p1 = .{
                .x = end.x,
                .y = end.y,
                .z = end.z,
            }
        };
        const debug_line = sc2p.DebugLine{
            .line = line,
            .color = .{
                .r = color.r,
                .g = color.g,
                .b = color.b
            },
        };
        self.debug_lines.append(debug_line) catch return;
    }

    pub fn debugBox(self: *Actions, min: Point3, max: Point3, color: Color) void {
        const proto = sc2p.DebugBox{
            .min = .{
                .x = min.x,
                .y = min.y,
                .z = min.z,
            },
            .max = .{
                .x = max.x,
                .y = max.y,
                .z = max.z,
            },
            .color = .{
                .r = color.r,
                .g = color.g,
                .b = color.b,
            },
        };
        self.debug_boxes.append(proto) catch return;
    }

    pub fn debugSphere(self: *Actions, center: Point3, radius: f32, color: Color) void {
        const proto = sc2p.DebugSphere{
            .p = .{
                .x = center.x,
                .y = center.y,
                .z = center.z,
            },
            .r = radius,
            .color = .{
                .r = color.r,
                .g = color.g,
                .b = color.b,
            }
        };
        self.debug_spheres.append(proto) catch return;        
    }

    pub fn debugCommandsToProto(self: *Actions) ?sc2p.RequestDebug {
        var command_list = std.ArrayList(sc2p.DebugCommand).init(self.temp_allocator);

        var debug_draw = sc2p.DebugDraw{};
        var add_draw_command = false;

        if (self.debug_texts.items.len > 0) {
            add_draw_command = true;
            debug_draw.text = self.debug_texts.items;
        }

        if (self.debug_lines.items.len > 0) {
            add_draw_command = true;
            debug_draw.lines = self.debug_lines.items;
        }

        if (self.debug_boxes.items.len > 0) {
            add_draw_command = true;
            debug_draw.boxes = self.debug_boxes.items;
        }

        if (self.debug_spheres.items.len > 0) {
            add_draw_command = true;
            debug_draw.spheres = self.debug_spheres.items;
        }

        if (add_draw_command) {
            const command = sc2p.DebugCommand{
                .draw = debug_draw,
            };
            command_list.append(command) catch return null;
        }

        for (self.debug_create_unit.items) |debug_create_unit| {
            const command = sc2p.DebugCommand{
                .create_unit = debug_create_unit,
            };
            command_list.append(command) catch return null;
        }

        if (command_list.items.len == 0) return null;

        const debug_proto = sc2p.RequestDebug{
            .commands = command_list.items,
        };

        return debug_proto;
    }

    pub fn findPlacement(self: *Actions, structure_to_build: UnitId, near: Point2, max_distance: f32) ?Point2 {
        assert(max_distance >= 1 and max_distance <= 30);
        const structure_data = self.game_data.units.get(structure_to_build);
        if (structure_data == null) {
            log.debug("Did not find {d} in game data\n", .{structure_to_build});
            return null;
        }

        const ability = structure_data.?.train_ability_id;
        const ability_int = @intCast(i32, @enumToInt(ability));
        
        var options: [256]sc2p.RequestQueryBuildingPlacement = undefined;
        var outer_dist: f32 = 1;
        while (outer_dist <= max_distance) : (outer_dist += 1) {
            var option_count: usize = 0;
            var inner_dist: f32 = -outer_dist;
            while (inner_dist <= outer_dist) : (inner_dist += 1) {
                options[option_count] = .{
                    .ability_id = ability_int,
                    .target_pos = .{.x = near.x + inner_dist, .y = near.y + outer_dist},
                };
                options[option_count + 1] = .{
                    .ability_id = ability_int,
                    .target_pos = .{.x = near.x + inner_dist, .y = near.y - outer_dist},
                };
                options[option_count + 2] = .{
                    .ability_id = ability_int,
                    .target_pos = .{.x = near.x + outer_dist, .y = near.y + inner_dist},
                };
                options[option_count + 3] = .{
                    .ability_id = ability_int,
                    .target_pos = .{.x = near.x - outer_dist, .y = near.y + inner_dist},
                };
                option_count += 4;
            }
            const query = sc2p.RequestQuery{
                .placements = options[0..option_count],    
                .ignore_resource_requirements = true,
            };
            const result = self.client.sendPlacementQuery(query);
            var min_dist: f32 = math.f32_max;
            var min_index: usize = options.len;
            if (result) |query_res| {
                for (query_res) |option, i| {
                    if (option.result.? == .success) {
                        const dist = near.distanceSquaredTo(.{.x = options[i].target_pos.?.x.?, .y = options[i].target_pos.?.y.?});
                        if (dist < min_dist) {
                            min_dist = dist;
                            min_index = i;
                        }
                    }
                }
                if (min_index < options.len) return .{
                    .x = options[min_index].target_pos.?.x.?, .y = options[min_index].target_pos.?.y.?,
                };
            }
        }

        return null;
    }

    pub fn queryPlacement(self: *Actions, structure_to_build: UnitId, spot: Point2) bool {
        if (self.game_data.units.get(structure_to_build)) |structure_data| {
            const ability = structure_data.train_ability_id;
            var placements = [_]sc2p.RequestQueryBuildingPlacement{.{
                .ability_id = @intCast(i32, @enumToInt(ability)),
                .target_pos = .{.x = spot.x, .y = spot.y},
            }};
            const query = sc2p.RequestQuery{
                .placements = placements[0..],    
                .ignore_resource_requirements = true,
            };
            const result = self.client.sendPlacementQuery(query);
            if (result) |query_res| {
                return query_res[0].result.? == .success;
            }
            return false;
        } else {
            log.debug("Did not find {d} in game data\n", .{structure_to_build});
            return false;
        }
    }

    /// owner should be 1 if creating a unit for yourself
    /// and 2 if creating for the opponent
    pub fn debugCreateUnit(self: *Actions, unit_type: UnitId, owner: i32, pos: Point2, quantity: u32) void {
        const debug_unit = sc2p.DebugCreateUnit{
            .unit_type = @enumToInt(unit_type),
            .owner = owner,
            .pos = .{.x = pos.x, .y = pos.y},
            .quantity = quantity,
        };

        self.debug_create_unit.append(debug_unit) catch return;
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
        air_range: f32,
        ground_range: f32,
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
    build_map: std.AutoHashMap(AbilityId, UnitId),
    upgrade_map: std.AutoHashMap(AbilityId, UpgradeId),

    pub fn fromProto(
        proto:sc2p.ResponseData,
        allocator: mem.Allocator
    ) !GameData {

        var gd = GameData{
            .upgrades = std.AutoHashMap(UpgradeId, UpgradeData).init(allocator),
            .units = std.AutoHashMap(UnitId, UnitData).init(allocator),
            .build_map = std.AutoHashMap(AbilityId, UnitId).init(allocator),
            .upgrade_map = std.AutoHashMap(AbilityId, UpgradeId).init(allocator),
        };

        const proto_upgrades = proto.upgrades.?;

        for (proto_upgrades) |proto_upgrade| {
            const upg = UpgradeData{
                .id = @intToEnum(UpgradeId, proto_upgrade.upgrade_id.?),
                .mineral_cost = @intCast(i32, proto_upgrade.mineral_cost orelse 0),
                .vespene_cost = @intCast(i32, proto_upgrade.vespene_cost orelse 0),
                .research_time = proto_upgrade.research_time orelse 0,
                .research_ability_id = @intToEnum(AbilityId, proto_upgrade.ability_id orelse 0),
            };

            try gd.upgrades.put(upg.id, upg);
            try gd.upgrade_map.put(upg.research_ability_id, upg.id);
        }

        const proto_units = proto.units.?;

        for (proto_units) |proto_unit| {
            const available = proto_unit.available orelse false;
            if (!available) continue;

            var attributes = std.EnumSet(Attribute){};
            
            if (proto_unit.attributes) |proto_attrs| {
                for (proto_attrs) |attr| {
                    attributes.insert(attr);
                }
            }

            var air_dps: f32 = 0;
            var ground_dps: f32 = 0;
            var air_range: f32 = 0;
            var ground_range: f32 = 0;

            //@TODO: May need to do something with battlecruisers
            //and oracles if their weapons don't show up here
            if (proto_unit.weapons) |weapons_proto| {
                for (weapons_proto) |weapon_proto| {
                    const target_type = weapon_proto.target_type.?;
                    const range = weapon_proto.range.?;
                    const speed = weapon_proto.speed.?;
                    const attacks: f32 = @intToFloat(f32, weapon_proto.attacks.?);
                    const damage = weapon_proto.damage.?;
                    const dps = (damage*attacks) / speed;
                    switch (target_type) {
                        .ground => {
                            ground_dps = dps;
                            ground_range = range;
                        },
                        .air => {
                            air_dps = dps;
                            air_range = range;
                        },
                        .any => {
                            air_dps = dps;
                            ground_dps = dps;
                            air_range = range;
                            ground_range = range;
                        },
                    }
                }
            }

            const unit = UnitData{
                .id = @intToEnum(UnitId, proto_unit.unit_id.?),
                .cargo_size = @intCast(i32, proto_unit.cargo_size orelse 0),
                .movement_speed = proto_unit.movement_speed orelse 0,
                .armor = proto_unit.armor orelse 0,
                .air_dps = air_dps,
                .ground_dps = ground_dps,
                .air_range = air_range,
                .ground_range = ground_range,
                .mineral_cost = @intCast(i32, proto_unit.mineral_cost orelse 0),
                .vespene_cost = @intCast(i32, proto_unit.vespene_cost orelse 0),
                .food_required = proto_unit.food_required orelse 0,
                .food_provided = proto_unit.food_provided orelse 0,
                .train_ability_id = @intToEnum(AbilityId, proto_unit.ability_id orelse 0),
                .race = proto_unit.race orelse Race.none,
                .build_time = proto_unit.build_time orelse 0,
                .sight_range = proto_unit.sight_range orelse 0,
                .attributes = attributes,
            };

            try gd.units.put(unit.id, unit);
            try gd.build_map.put(unit.train_ability_id, unit.id);
        }

        return gd;
    }

};