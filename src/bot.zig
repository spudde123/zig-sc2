const std = @import("std");
const assert = std.debug.assert;

const mem = std.mem;
const log = std.log;
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
};

pub const Grid = struct {
    data: []u8,
    w: i32,
    h: i32,

};

pub const OrderType = enum(u8) {
    empty,
    position,
    tag,
};

pub const OrderTarget = union(OrderType) {
    empty: void,
    position: Point2d,
    tag: u64,
};

pub const UnitOrder = struct {
    ability_id: AbilityId,
    target: OrderTarget,
    progress: f32,
};

pub const RallyTarget = struct {
    point: Point2d,
    tag: ?u64,
};

pub const GameInfo = struct {

    pathing_grid: Grid,
    placement_grid: Grid,
    terrain_height: Grid,

    map_name: []const u8,
    enemy_name: []const u8,
    // These can be different for a random opponent
    enemy_requested_race: Race,
    enemy_race: Race,

    map_size: GridSize,
    playable_area: Rectangle,

    start_location: Point2d,
    enemy_start_locations: []Point2d,

    //expansion_locations: []Point2d,
    //allocator: mem.Allocator,

    pub fn fromProto(
        proto_data: sc2p.ResponseGameInfo,
        player_id: u32,
        start_location: Point2d,
        allocator: mem.Allocator
    ) !GameInfo {
        
        var received_map_name = proto_data.map_name.data.?;
        var map_name = try allocator.alloc(u8, received_map_name.len);
        mem.copy(u8, map_name, received_map_name);

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

        var raw_proto = proto_data.start_raw.data.?;

        var map_size_proto = raw_proto.map_size.data.?;
        var map_size = GridSize{.w = map_size_proto.x.data.?, .h = map_size_proto.y.data.?};

        var playable_area_proto = raw_proto.playable_area.data.?;
        var rect_p0 = playable_area_proto.p0.data.?;
        var rect_p1 = playable_area_proto.p1.data.?;

        var playable_area = Rectangle{
            .p0 = .{.x = rect_p0.x.data.?, .y = rect_p0.y.data.?},
            .p1 = .{.x = rect_p1.x.data.?, .y = rect_p1.y.data.?},
        };

        var start_locations = std.ArrayList(Point2d).init(allocator);
        for (raw_proto.start_locations.data.?) |loc_proto| {
            try start_locations.append(.{
                .x = loc_proto.x.data.?,
                .y = loc_proto.y.data.?,
            });
        }

        var terrain_proto = raw_proto.terrain_height.data.?;
        assert(terrain_proto.bits_per_pixel.data.? == 8);
        assert(terrain_proto.size.data.?.x.data.? == map_size.w);
        assert(terrain_proto.size.data.?.y.data.? == map_size.h);
        var terrain_proto_slice = terrain_proto.image.data.?;
        var terrain_slice = try allocator.alloc(u8, terrain_proto_slice.len);
        mem.copy(u8, terrain_slice, terrain_proto_slice);

        var pathing_proto = raw_proto.pathing_grid.data.?;
        assert(pathing_proto.bits_per_pixel.data.? == 1);
        assert(pathing_proto.size.data.?.x.data.? == map_size.w);
        assert(pathing_proto.size.data.?.y.data.? == map_size.h);
        var pathing_proto_slice = pathing_proto.image.data.?;
        var pathing_slice = try allocator.alloc(u8, @intCast(usize, map_size.w * map_size.h));
        
        const packed_int_type = PackedIntIo(u1, .Big);
        
        var index: usize = 0;
        while (index < map_size.w * map_size.h) : (index += 1) {
            pathing_slice[index] = packed_int_type.get(pathing_proto_slice, index, 0);
        }

        var placement_proto = raw_proto.placement_grid.data.?;
        assert(placement_proto.bits_per_pixel.data.? == 1);
        assert(placement_proto.size.data.?.x.data.? == map_size.w);
        assert(placement_proto.size.data.?.y.data.? == map_size.h);
        var placement_proto_slice = placement_proto.image.data.?;
        var placement_slice = try allocator.alloc(u8, @intCast(usize, map_size.w * map_size.h));
        index = 0;
        while (index < map_size.w * map_size.h) : (index += 1) {
            placement_slice[index] = packed_int_type.get(placement_proto_slice, index, 0);
        }

        return GameInfo{
            .map_name = map_name,
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
        };
    }

    //fn generateExpansionLocations() []Point2d {
    //
    //}

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
    result: ?Result,

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

                        var order = UnitOrder{
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
                        var proto_point = proto_target.point.data.?;
                        var rally_target = RallyTarget{
                            .point = .{.x = proto_point.x.data.?, .y = proto_point.y.data.?},
                            .tag = proto_target.tag.data,
                        };
                        rally_targets.appendAssumeCapacity(rally_target);
                    }
                } else {
                    rally_targets = try std.ArrayList(RallyTarget).initCapacity(allocator, 0);
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

pub const Actions = struct {

    const ActionData = struct {
        ability_id: AbilityId,
        target: OrderTarget,
        queue: bool
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
    order_list: std.ArrayList(BotAction),
    chat_messages: std.ArrayList(ChatAction),

    pub fn init(perm_allocator: mem.Allocator, temp_allocator: mem.Allocator) !Actions {

        return Actions{
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

    pub fn train(self: *Actions, structure_tag: u64, unit_type: UnitId, queue: bool) void {
        _ = self;
        _ = structure_tag;
        _ = unit_type;
        _ = queue;
    }

    pub fn build(self: *Actions, unit_tag: u64, structure_to_build: UnitId, pos: Point2d, queue: bool) void {
        _ = self;
        _ = unit_tag;
        _ = structure_to_build;
        _ = pos;
        _ = queue;
    }

    /// This is mainly for building gas structures. target_tag needs to be the geysir tag
    pub fn buildOnUnit(self: *Actions, unit_tag: u64, structure_to_build: UnitId, target_tag: u64, queue: bool) void {
        _ = self;
        _ = unit_tag;
        _ = structure_to_build;
        _ = target_tag;
        _ = queue;
    }

    pub fn moveToPosition(self: *Actions, unit_tag: u64, pos: Point2d, queue: bool) void {
       var action = BotAction{
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
        var action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.Move_Move,
                .target = .{.tag = target_tag},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn attackPosition(self: *Actions, unit_tag: u64, pos: Point2d, queue: bool) void {
        var action = BotAction{
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
       var action = BotAction{
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
        var action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = AbilityId.HoldPosition,
                .target = .{.empty = {}},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn patrol(self: *Actions, unit_tag: u64, target: Point2d, queue: bool) void {
        var action = BotAction{
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
        _ = self;
        _ = structure_tag;
        _ = upgrade;
        _ = queue;
    }

    pub fn stop(self: *Actions, unit_tag: u64, queue: bool) void {
        var action = BotAction{
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
        var action = BotAction{
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
        var action = BotAction{
            .unit = unit_tag,
            .data = .{
                .ability_id = ability,
                .target = .{.empty = {}},
                .queue = queue
            },
        };
        self.addAction(action);
    }

    pub fn useAbilityOnPosition(self: *Actions, unit_tag: u64, ability: AbilityId, target: Point2d, queue: bool) void {
        var action = BotAction{
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
        var action = BotAction{
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
        mem.copy(u8, msg_copy, message);.
        self.chat_messages.append(.{.channel = channel, .message = msg_copy}) catch return;
    }

    pub fn toProto(self: *Actions) ?sc2p.RequestAction {
        if (self.order_list.items.len == 0) return null;

        // Combine repeat orders

        const combined_length = self.order_list.items.len + self.chat_messages.items.len;
        var action_list = std.ArrayList(sc2p.Action).initCapacity(self.temp_allocator, combined_length) catch return null;
        
        for (self.chat_messages.items) |msg| {
            var action_chat = sc2p.ActionChat{
                .channel = .{.data = msg.channel},
                .message = .{.data = msg.message},
            };
            var action = sc2p.Action{.action_chat = .{.data = action_chat}};
            action_list.appendAssumeCapacity(action);
        }

        // Hashing based on the ActionData, value is the index in the next array list
        var action_hashmap = std.AutoHashMap(u64, usize).init(self.temp_allocator);
        var raw_unit_commands = std.ArrayList(sc2p.ActionRawUnitCommand).init(self.temp_allocator);

        for (self.order_list.items) |order| {

            var maybe_index = action_hashmap.get(order.unit);

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
                action_hashmap.put(order.unit, raw_unit_commands.items.len - 1) catch break;
            }
        }

        for (raw_unit_commands.items) |*command| {
            command.unit_tags.data = command.unit_tags.list.?.items;
            var action_raw = sc2p.ActionRaw{.unit_command = .{.data = command.*}};
            var action = sc2p.Action{.action_raw = .{.data = action_raw}};
            action_list.appendAssumeCapacity(action);
        }

        var action_request = sc2p.RequestAction{
            .actions = .{.data = action_list.toOwnedSlice()},
        };

        return action_request;
    }

};