const std = @import("std");
const mem = std.mem;
const log = std.log;

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

pub const GridSize = struct {
    w: i32,
    h: i32,
};

pub const Rectangle = struct {
    // Left bottom
    p0: GridPoint,
    // Top right
    p1: GridPoint,

    pub fn width(self: *Rectangle) i32 {
        return self.p1.x - self.p0.x + 1;
    }

    pub fn height(self: *Rectangle) i32 {
        return self.p1.y - self.p0.y + 1;
    }

    pub fn pointIsInside(self: *Rectangle, point: GridPoint) bool {
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

pub const Point2d = struct {
    x: f32,
    y: f32,
};

pub const Point3d = struct {
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

    position: Point2d,
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

    //orders: []UnitOrder,
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
    //rally_targets: []RallyTarget
};

pub const Grid = struct {
    data: []u8,
    width: i32,
    height: i32,

};

pub const MapData = struct {

    //pathing_grid: Grid,
    //placement_grid: Grid,
    //terrain_height: Grid,

    //allocator: mem.Allocator,

    pub fn fromProto(proto_data: sc2p.StartRaw, allocator: mem.Allocator) MapData {
        _ = proto_data;
        _ = allocator;
        
        return .{};
    }

    pub fn deinit() void {

    }

    pub fn update(bot: Bot) void {
        _ = bot;
    }
};

pub const Bot = struct {
    own_units: []Unit,
    enemy_units: []Unit,
    destructables: []Unit,
    minerals: []Unit,
    geysers: []Unit,
    watch_towers: []Unit,

    game_loop: u32,
    time: f32,
    result: ?Result = null,

    pub fn fromProto(response: sc2p.ResponseObservation, player_id: u32, allocator: mem.Allocator) !Bot {

        var game_loop: u32 = response.observation.data.?.game_loop.data.?;
        
        var time = @intToFloat(f32, game_loop) / 22.4;

        var obs: sc2p.ObservationRaw = response.observation.data.?.raw.data.?;
        
        var own_units = std.ArrayList(Unit).init(allocator);
        var enemy_units = std.ArrayList(Unit).init(allocator);
        var destructables = std.ArrayList(Unit).init(allocator);
        var minerals = std.ArrayList(Unit).init(allocator);
        var geysers = std.ArrayList(Unit).init(allocator);
        var watch_towers = std.ArrayList(Unit).init(allocator);

        if (obs.units.data) |units| {
            for (units) |unit| {
                var proto_pos = unit.pos.data.?;
                var position = Point2d{
                    .x = proto_pos.x.data.?, 
                    .y = proto_pos.y.data.?
                };
                var z: f32 = proto_pos.z.data.?;
                
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

                var u = Unit{
                    .display_type = unit.display_type.data.?,
                    .alliance = unit.alliance.data.?,
                    .tag = unit.tag.data.?,
                    .unit_type = @intToEnum(UnitId, unit.unit_type.data.?),
                    .owner = unit.owner.data.?,

                    .position = position,
                    .z = z,
                    .facing = unit.facing.data orelse 0,
                    .radius = unit.radius.data orelse 0,
                    .build_progress = unit.build_progress.data orelse 0,
                    .cloak = unit.cloak.data.?,
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

                    //.orders =
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
                    //.rally_targets = unit.rally_targets.data orelse 0,
                };
                
                switch (u.alliance) {
                    .self, .ally => {
                        try own_units.append(u);
                    },
                    .enemy => {
                        try enemy_units.append(u);
                    },
                    else => {
                        var mineral_ids = [_]UnitId{
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

                        var geyser_ids = [_]UnitId{
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
                            try minerals.append(u);
                        } else if (mem.indexOfScalar(UnitId, geyser_ids[0..], u.unit_type)) |_| {
                            try geysers.append(u);
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

        return Bot{
            .own_units = own_units.toOwnedSlice(),
            .enemy_units = enemy_units.toOwnedSlice(),

            .destructables = destructables.toOwnedSlice(),
            .geysers = geysers.toOwnedSlice(),
            .minerals = minerals.toOwnedSlice(),
            .watch_towers = watch_towers.toOwnedSlice(),
            .game_loop = game_loop,
            .time = time,
            .result = result,
        };
    }
    
};