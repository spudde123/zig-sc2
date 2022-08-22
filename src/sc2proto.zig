const std = @import("std");
const proto = @import("protobuf.zig");
const ProtoField = proto.ProtoField;

pub const Status = enum(u8) {
    default = 0,
    launched = 1,
    init_game = 2,
    in_game = 3,
    in_replay = 4,
    ended = 5,
    quit = 6,
    unknown = 99,
};

pub const Request = struct {
    create_game: ProtoField(1, RequestCreateGame) = .{},
    join_game: ProtoField(2, RequestJoinGame) = .{},
    leave_game: ProtoField(5, void) = .{},
    quit: ProtoField(8, void) = .{},
    game_info: ProtoField(9, void) = .{},
    observation: ProtoField(10, RequestObservation) = .{},
    action: ProtoField(11, RequestAction) = .{},
    step: ProtoField(12, RequestStep) = .{},
    game_data: ProtoField(13, RequestData) = .{},
    //query: ProtoField(14, RequestQuery) = .{},
    save_replay: ProtoField(15, void) = .{},
    ping: ProtoField(19, void) = .{},
    debug: ProtoField(20, RequestDebug) = .{},

    id: ProtoField(97, u32) = .{},
};

pub const Response = struct {
    create_game: ProtoField(1, ResponseCreateGame) = .{},
    join_game: ProtoField(2, ResponseJoinGame) = .{},
    leave_game: ProtoField(5, void) = .{},
    quit: ProtoField(8, void) = .{},
    game_info: ProtoField(9, ResponseGameInfo) = .{},
    observation: ProtoField(10, ResponseObservation) = .{},
    action: ProtoField(11, ResponseAction) = .{},
    step: ProtoField(12, ResponseStep) = .{},
    game_data: ProtoField(13, ResponseData) = .{},
    //query: ProtoField(14, ResponseQuery) = .{},
    save_replay: ProtoField(15, ResponseSaveReplay) = .{},
    ping: ProtoField(19, ResponsePing) = .{},
    debug: ProtoField(20, void) = .{},

    id: ProtoField(97, u32) = .{},
    errors: ProtoField(98, [][]const u8) = .{},
    status: ProtoField(99, Status) = .{},
};

pub const RequestCreateGame = struct {
    map: ProtoField(1, LocalMap) = .{},
    player_setup: ProtoField(3, []PlayerSetup) = .{},
    disable_fog: ProtoField(4, bool) = .{},
    realtime: ProtoField(6, bool) = .{},
};

pub const ErrorCreateGame = enum(u8) {
    missing_map = 1,
    invalid_map_path = 2,
    invalid_map_data = 3,
    invalid_map_name = 4,
    invalid_map_handle = 5,
    missing_player_setup = 6,
    invalid_player_setup = 7,
    multiplayer_unsupported = 8,
};

pub const ResponseCreateGame = struct {
    error_code: ProtoField(1, ErrorCreateGame) = .{},
    error_details: ProtoField(2, []const u8) = .{},
};

pub const RequestJoinGame = struct {
    race: ProtoField(1, Race) = .{},
    options: ProtoField(3, InterfaceOptions) = .{},
    server_ports: ProtoField(4, PortSet) = .{},
    client_ports: ProtoField(5, PortSet) = .{},
    player_name: ProtoField(7, []const u8) = .{},
    host_ip: ProtoField(8, []const u8) = .{},
};

pub const ErrorJoinGame = enum(u8) {
    missing_participation = 1,
    invalid_observed_player_id = 2,
    missing_options = 3,
    missing_ports = 4,
    game_full = 5,
    launch_error = 6,

    feature_unsupported = 7,
    no_space_for_user = 8,
    map_does_not_exist = 9,
    cannot_open_map = 10,
    checksum_error = 11,
    network_error = 12,
    other_error = 13,
    _
};

pub const ResponseJoinGame = struct {
    player_id: ProtoField(1, u32) = .{},
    error_code: ProtoField(2, ErrorJoinGame) = .{},
    error_details: ProtoField(3, []const u8) = .{},
};

pub const ResponseGameInfo = struct {
    map_name: ProtoField(1, []const u8) = .{},
    local_map_path: ProtoField(2, []const u8) = .{},
    player_info: ProtoField(3, []PlayerInfo) = .{},
    start_raw: ProtoField(4, StartRaw) = .{},
    options: ProtoField(5, InterfaceOptions) = .{},
    mod_names: ProtoField(6, [][]const u8) = .{}
};

pub const RequestAction = struct {
    actions: ProtoField(1, []Action) = .{},
};

pub const ResponseAction = struct {
    results: ProtoField(1, []ActionResult) = .{},
};

pub const RequestObservation = struct {
    disable_fog: ProtoField(1, bool) = .{},
    game_loop: ProtoField(2, u32) = .{},
};

pub const RequestStep = struct {
    count: ProtoField(1, u32) = .{},
};

pub const ResponseStep = struct {
    simulation_loop: ProtoField(1, u32) = .{},
};

pub const ResponsePing = struct {
    game_version: ProtoField(1, []const u8) = .{},
    data_version: ProtoField(2, []const u8) = .{},
    data_build: ProtoField(3, u32) = .{},
    base_build: ProtoField(4, u32) = .{},
};

pub const ResponseSaveReplay = struct {
    bytes: ProtoField(1, []u8) = .{},
};

pub const ResponseObservation = struct {
    actions: ProtoField(1, []Action) = .{},
    action_errors: ProtoField(2, []ActionError) = .{},
    observation: ProtoField(3, Observation) = .{},
    player_result: ProtoField(4, []PlayerResult) = .{},
    chat: ProtoField(5, []ChatReceived) = .{},
};

pub const Observation = struct {
    player_common: ProtoField(1, PlayerCommon) = .{},
    abilities: ProtoField(3, []AvailableAbility) = .{},
    score: ProtoField(4, Score) = .{},

    raw: ProtoField(5, ObservationRaw) = .{},
    //feature_layer: ProtoField(6, ObservationFeatureLayer) = .{},
    //render: ProtoField(7, ObservationRender) = .{},
    //ui: ProtoField(8, ObservationUI) = .{},
    game_loop: ProtoField(9, u32) = .{},
    alerts: ProtoField(10, []Alert) = .{},
};

pub const PlayerCommon = struct {
    player_id: ProtoField(1, u32) = .{},
    minerals: ProtoField(2, u32) = .{},
    vespene: ProtoField(3, u32) = .{},
    food_cap: ProtoField(4, u32) = .{},
    food_used: ProtoField(5, u32) = .{},
    food_army: ProtoField(6, u32) = .{},
    food_workers: ProtoField(7, u32) = .{},
    idle_worker_count: ProtoField(8, u32) = .{},
    army_count: ProtoField(9, u32) = .{},
    warp_gate_count: ProtoField(10, u32) = .{},
    larva_count: ProtoField(11, u32) = .{},
};

pub const ScoreType = enum(u8) {
    curriculum = 1,
    melee = 2,
};

pub const Score = struct {
    score_type: ProtoField(6, ScoreType) = .{},
    score: ProtoField(7, i32) = .{},
    details: ProtoField(8, ScoreDetails) = .{},
};

pub const CategoryScoreDetails = struct {
    none: ProtoField(1, f32) = .{},
    army: ProtoField(2, f32) = .{},
    economy: ProtoField(3, f32) = .{},
    technology: ProtoField(4, f32) = .{},
    upgrade: ProtoField(5, f32) = .{},
};

pub const VitalScoreDetails = struct {
    life: ProtoField(1, f32) = .{},
    shields: ProtoField(2, f32) = .{},
    energy: ProtoField(3, f32) = .{},
};

pub const ScoreDetails = struct {
    idle_production_time: ProtoField(1, f32) = .{},
    idle_worker_time: ProtoField(2, f32) = .{},
    total_value_units: ProtoField(3, f32) = .{},
    total_value_structures: ProtoField(4, f32) = .{},
    killed_value_units: ProtoField(5, f32) = .{},
    killed_value_structures: ProtoField(6, f32) = .{},
    collected_minerals: ProtoField(7, f32) = .{},
    collected_vespene: ProtoField(8, f32) = .{},
    collection_rate_minerals: ProtoField(9, f32) = .{},
    collection_rate_vespene: ProtoField(10, f32) = .{},
    spent_minerals: ProtoField(11, f32) = .{},
    spent_vespene: ProtoField(12, f32) = .{},
    food_used: ProtoField(13, CategoryScoreDetails) = .{},
    killed_minerals: ProtoField(14, CategoryScoreDetails) = .{},
    killed_vespene: ProtoField(15, CategoryScoreDetails) = .{},
    lost_minerals: ProtoField(16, CategoryScoreDetails) = .{},
    lost_vespene: ProtoField(17, CategoryScoreDetails) = .{},
    friendly_fire_minerals: ProtoField(18, CategoryScoreDetails) = .{},
    friendly_fire_vespene: ProtoField(19, CategoryScoreDetails) = .{},
    used_minerals: ProtoField(20, CategoryScoreDetails) = .{},
    used_vespene: ProtoField(21, CategoryScoreDetails) = .{},
    total_used_minerals: ProtoField(22, CategoryScoreDetails) = .{},
    total_used_vespene: ProtoField(23, CategoryScoreDetails) = .{},
    total_damage_dealt: ProtoField(24, VitalScoreDetails) = .{},
    total_damage_taken: ProtoField(25, VitalScoreDetails) = .{},
    total_healed: ProtoField(26, VitalScoreDetails) = .{},
    current_apm: ProtoField(27, f32) = .{},
    current_effective_apm: ProtoField(28, f32) = .{},
};

pub const ObservationRaw = struct {
    player: ProtoField(1, PlayerRaw) = .{},
    units: ProtoField(2, []Unit) = .{},
    map_state: ProtoField(3, MapState) = .{},
    event: ProtoField(4, Event) = .{},
    effects: ProtoField(5, []Effect) = .{},
    radars: ProtoField(6, []RadarRing) = .{},
};

pub const RadarRing = struct {
    pos: ProtoField(1, Point) = .{},
    radius: ProtoField(2, f32) = .{},
};

pub const PowerSource = struct {
    pos: ProtoField(1, Point) = .{},
    radius: ProtoField(2, f32) = .{},
    tag: ProtoField(3, u64) = .{},
};

pub const PlayerRaw = struct {
    power_sources: ProtoField(1, []PowerSource) = .{},
    camera: ProtoField(2, Point) = .{},
    upgrade_ids: ProtoField(3, []u32) = .{},
};

pub const MapState = struct {
    visibility: ProtoField(1, ImageData) = .{},
    creep: ProtoField(2, ImageData) = .{},
};

pub const Event = struct {
    dead_units: ProtoField(1, []u64) = .{},
};

pub const DisplayType = enum(u8) {
    visible = 1,
    snapshot = 2,
    hidden = 3,
    placeholder = 4,
};

pub const Alliance = enum(u8) {
    self = 1,
    ally = 2,
    neutral = 3,
    enemy = 4,
};

pub const CloakState = enum(u8) {
    unknown = 0,
    cloaked = 1,
    cloaked_detected = 2,
    not_cloaked = 3,
    cloaked_allied = 4,
};

pub const Effect = struct {
    effect_id: ProtoField(1, u32) = .{},
    pos: ProtoField(2, []Point2D) = .{},
    alliance: ProtoField(3, Alliance) = .{},
    owner: ProtoField(4, i32) = .{},
    radius: ProtoField(5, f32) = .{},
};

pub const RallyTarget = struct {
    point: ProtoField(1, Point) = .{},
    tag: ProtoField(2, u64) = .{},
};

pub const UnitOrder = struct {
    ability_id: ProtoField(1, u32) = .{},
    target_world_space_pos: ProtoField(2, Point) = .{},
    target_unit_tag: ProtoField(3, u64) = .{},
    progress: ProtoField(4, f32) = .{},
};

pub const PassengerUnit = struct {
    tag: ProtoField(1, u64) = .{},
    health: ProtoField(2, f32) = .{},
    health_max: ProtoField(3, f32) = .{},
    shield: ProtoField(4, f32) = .{},
    shield_max: ProtoField(7, f32) = .{},
    energy: ProtoField(5, f32) = .{},
    energy_max: ProtoField(8, f32) = .{},
    unit_type: ProtoField(6, u32) = .{},
};

pub const Unit = struct {
    display_type: ProtoField(1, DisplayType) = .{},
    alliance: ProtoField(2, Alliance) = .{},
    tag: ProtoField(3, u64) = .{},
    unit_type: ProtoField(4, u32) = .{},
    owner: ProtoField(5, i32) = .{},
    
    pos: ProtoField(6, Point) = .{},
    facing: ProtoField(7, f32) = .{},
    radius: ProtoField(8, f32) = .{},
    build_progress: ProtoField(9, f32) = .{},
    cloak: ProtoField(10, CloakState) = .{},
    buff_ids: ProtoField(27, []u32) = .{},

    detect_range: ProtoField(31, f32) = .{},
    radar_range: ProtoField(32, f32) = .{},

    is_selected: ProtoField(11, bool) = .{},
    is_on_screen: ProtoField(12, bool) = .{},
    is_blip: ProtoField(13, bool) = .{},
    is_powered: ProtoField(35, bool) = .{},
    is_active: ProtoField(39, bool) = .{},

    attack_upgrade_level: ProtoField(40, i32) = .{},
    armor_upgrade_level: ProtoField(41, i32) = .{},
    shield_upgrade_level: ProtoField(42, i32) = .{},

    health: ProtoField(14, f32) = .{},
    health_max: ProtoField(15, f32) = .{},
    shield: ProtoField(16, f32) = .{},
    shield_max: ProtoField(36, f32) = .{},
    energy: ProtoField(17, f32) = .{},
    energy_max: ProtoField(37, f32) = .{},
    mineral_contents: ProtoField(18, i32) = .{},
    vespene_contents: ProtoField(19, i32) = .{},
    is_flying: ProtoField(20, bool) = .{},
    is_burrowed: ProtoField(21, bool) = .{},
    is_hallucination: ProtoField(38, bool) = .{},

    orders: ProtoField(22, []UnitOrder) = .{},
    addon_tag: ProtoField(23, u64) = .{},
    passengers: ProtoField(24, []PassengerUnit) = .{},
    cargo_space_taken: ProtoField(25, i32) = .{},
    cargo_space_max: ProtoField(26, i32) = .{},
    
    assigned_harvesters: ProtoField(28, i32) = .{},
    ideal_harvesters: ProtoField(29, i32) = .{},
    weapon_cooldown: ProtoField(30, f32) = .{},
    engaged_target_tag: ProtoField(34, u64) = .{},
    buff_duration_remain: ProtoField(43, i32) = .{},
    buff_duration_max: ProtoField(44, i32) = .{},
    rally_targets:ProtoField(45, []RallyTarget) = .{},    
};

pub const Action = struct {
    action_raw: ProtoField(1, ActionRaw) = .{},
    //action_feature_layer: ProtoField(2, ActionSpatial) = .{},
    //action_render: ProtoField(3, ActionSpatial) = .{},
    //action_ui: ProtoField(4, ActionUI) = .{},
    action_chat: ProtoField(6, ActionChat) = .{},
    game_loop: ProtoField(7, u32) = .{},
};

pub const ActionError = struct {
    unit_tag: ProtoField(1, u64) = .{},
    ability_id: ProtoField(2, u64) = .{},
    result: ProtoField(3, ActionResult) = .{},
};

pub const PlayerResult = struct {
    player_id: ProtoField(1, u32) = .{},
    result: ProtoField(2, Result) = .{},
};

pub const Result = enum(u8) {
    victory = 1,
    defeat = 2,
    tie = 3,
    undecided = 4,
};

pub const ChatReceived = struct {
    player_id: ProtoField(1, u32) = .{},
    message: ProtoField(2, []const u8) = .{},
};

pub const Channel = enum(u8) {
    broadcast = 1,
    team = 2,
};

pub const ActionChat = struct {
    channel: ProtoField(1, Channel) = .{},
    message: ProtoField(2, []const u8) = .{},
};

pub const ActionRaw = struct {
    unit_command: ProtoField(1, ActionRawUnitCommand) = .{},
    camera_move: ProtoField(2, ActionRawCameraMove) = .{},
    toggle_autocast: ProtoField(3, ActionRawToggleAutocast) = .{},
};

pub const ActionRawUnitCommand = struct {
    ability_id: ProtoField(1, i32) = .{},
    target_world_space_pos: ProtoField(2, Point2D) = .{},
    target_unit_tag: ProtoField(3, u64) = .{},
    unit_tags: ProtoField(4, []u64) = .{},
    queue_command: ProtoField(5, bool) = .{},
};

pub const ActionRawCameraMove = struct {
    point: ProtoField(1, Point) = .{},
};

pub const ActionRawToggleAutocast = struct {
    ability_id: ProtoField(1, i32) = .{},
    unit_tags: ProtoField(2, []u64) = .{},
};

pub const PlayerInfo = struct {
    player_id: ProtoField(1, u32) = .{},
    player_type: ProtoField(2, PlayerType) = .{},
    race_requested: ProtoField(3, Race) = .{},
    race_actual: ProtoField(4, Race) = .{},
    difficulty: ProtoField(5, AiDifficulty) = .{},
    player_name: ProtoField(6, []const u8) = .{},
    ai_build: ProtoField(7, AiBuild) = .{},
};

pub const InterfaceOptions = struct {
    raw: ProtoField(1, bool) = .{},
    score: ProtoField(2, bool) = .{},
    //feature_layer: ProtoField(3, SpatialCameraSetu) = .{},
    //render: ProtoField(4, SpatialCameraSetup) = .{},
    show_cloaked: ProtoField(5, bool) = .{},
    raw_affects_selection: ProtoField(6, bool) = .{},
    raw_crop_to_playable_area: ProtoField(7, bool) = .{},
    show_placeholders: ProtoField(8, bool) = .{},
    show_burrowed_shadows: ProtoField(9, bool) = .{},
};

pub const PortSet = struct {
    game_port: ProtoField(1, i32) = .{},
    base_port: ProtoField(2, i32) = .{},
};

pub const LocalMap = struct {
    map_path: ProtoField(1, []const u8) = .{},
};

pub const PlayerType = enum(u8) {
    participant = 1,
    computer = 2,
    observer = 3,
};

pub const Race = enum(u8) {
    none = 0,
    terran = 1,
    zerg = 2,
    protoss = 3,
    random = 4
};

pub const AiDifficulty = enum(u8) {
    very_easy = 1,
    easy = 2,
    medium = 3,
    medium_hard = 4,
    hard = 5,
    harder = 6,
    very_hard = 7,
    cheat_vision = 8,
    cheat_money = 9,
    cheat_insane = 10
};

pub const AiBuild = enum(u8) {
    random = 1,
    rush = 2,
    timing = 3,
    power = 4,
    macro = 5,
    air = 6
};

pub const PlayerSetup = struct {
    player_type: ProtoField(1, PlayerType) = .{},

    // For computer players
    race: ProtoField(2, Race) = .{},
    difficulty: ProtoField(3, AiDifficulty) = .{},
    name: ProtoField(4, []const u8) = .{},
    ai_build: ProtoField(5, AiBuild) = .{},
};

pub const Size2DI = struct {
    x: ProtoField(1, i32) = .{},
    y: ProtoField(2, i32) = .{},
};

pub const PointI = struct {
    x: ProtoField(1, i32) = .{},
    y: ProtoField(2, i32) = .{},
};

pub const RectangleI = struct {
    p0: ProtoField(1, PointI) = .{},
    p1: ProtoField(2, PointI) = .{},
};

pub const Point2D = struct {
    x: ProtoField(1, f32) = .{},
    y: ProtoField(2, f32) = .{},
};

pub const Point = struct {
    x: ProtoField(1, f32) = .{},
    y: ProtoField(2, f32) = .{},
    z: ProtoField(3, f32) = .{},
};

pub const ImageData = struct {
    bits_per_pixel: ProtoField(1, i32) = .{},
    size: ProtoField(2, Size2DI) = .{},
    image: ProtoField(3, []u8) = .{},
};

pub const AvailableAbility = struct {
    ability_id: ProtoField(1, i32) = .{},
    requires_point: ProtoField(2, bool) = .{},
};

pub const StartRaw = struct {
    map_size: ProtoField(1, Size2DI) = .{},
    pathing_grid: ProtoField(2, ImageData) = .{},
    terrain_height: ProtoField(3, ImageData) = .{},
    placement_grid: ProtoField(4, ImageData) = .{},
    playable_area: ProtoField(5, RectangleI) = .{},
    start_locations: ProtoField(6, []Point2D) = .{},
};

pub const ActionResult = enum(u8) {
    success = 1,
    not_supported = 2,
    _error = 3,
    cant_queue_that_order = 4,
    retry = 5,
    cooldown = 6,
    queue_is_full = 7,
    rally_queue_is_full = 8,
    not_enough_minerals = 9,
    not_enough_vespene = 10,
    not_enough_terrazine = 11,
    not_enough_custom = 12,
    not_enough_food = 13,
    food_usage_impossible = 14,
    not_enough_life = 15,
    not_enough_shields = 16,
    not_enough_energy = 17,
    life_suppressed = 18,
    shields_suppressed = 19,
    energy_suppressed = 20,
    not_enough_charges = 21,
    cant_add_more_charges = 22,
    too_much_minerals = 23,
    too_much_vespene = 24,
    too_much_terrazine = 25,
    too_much_custom = 26,
    too_much_food = 27,
    too_much_life = 28,
    too_much_shields = 29,
    too_much_energy = 30,
    must_target_unit_with_life = 31,
    must_target_unit_with_shields = 32,
    must_target_unit_with_energy = 33,
    cant_trade = 34,
    cant_spend = 35,
    cant_target_that_unit = 36,
    couldnt_allocate_unit = 37,
    unit_cant_move = 38,
    transport_is_holding_position = 39,
    build_tech_requirements_not_met = 40,
    cant_find_placement_location = 41,
    cant_build_on_that = 42,
    cant_build_too_close_to_dropoff = 43,
    cant_build_location_invalid = 44,
    cant_see_build_location = 45,
    cant_build_too_close_to_creep_source = 46,
    cant_build_too_close_to_resources = 47,
    cant_build_too_far_from_water = 48,
    cant_build_too_far_from_creep_source = 49,
    cant_build_too_far_from_build_power_source = 50,
    cant_build_on_dense_terrain = 51,
    cant_train_too_far_from_train_power_source = 52,
    cant_land_location_invalid = 53,
    cant_see_land_location = 54,
    cant_land_too_close_to_creep_source = 55,
    cant_land_too_close_to_resources = 56,
    cant_land_too_far_from_water = 57,
    cant_land_too_far_from_creep_source = 58,
    cant_land_too_far_from_build_power_source = 59,
    cant_land_too_far_from_train_power_source = 60,
    cant_land_on_dense_terrain = 61,
    addon_too_far_from_building = 62,
    must_build_refinery_first = 63,
    building_is_under_construction = 64,
    cant_find_dropoff = 65,
    cant_load_other_players_units = 66,
    not_enough_room_to_load_unit = 67,
    cant_unload_units_there = 68,
    cant_warpin_units_there = 69,
    cant_load_immobile_units = 70,
    cant_recharge_immobile_units = 71,
    cant_recharge_under_construction_units = 72,
    cant_load_that_unit = 73,
    no_cargo_to_unload = 74,
    load_all_no_targets_found = 75,
    not_while_occupied = 76,
    cant_attack_without_ammo = 77,
    cant_hold_any_more_ammo = 78,
    tech_requirements_not_met = 79,
    must_lockdown_unit_first = 80,
    must_target_unit = 81,
    must_target_inventory = 82,
    must_target_visible_unit = 83,
    must_target_visible_location = 84,
    must_target_walkable_location = 85,
    must_target_pawnable_unit = 86,
    you_cant_control_that_unit = 87,
    you_cant_issue_commands_to_that_unit = 88,
    must_target_resources = 89,
    requires_heal_target = 90,
    requires_repair_target = 91,
    no_items_to_drop = 92,
    cant_hold_any_more_items = 93,
    cant_hold_that = 94,
    target_has_no_inventory = 95,
    cant_drop_this_item = 96,
    cant_move_this_item = 97,
    cant_pawn_this_unit = 98,
    must_target_caster = 99,
    cant_target_caster = 100,
    must_target_outer = 101,
    cant_target_outer = 102,
    must_target_your_own_units = 103,
    cant_target_your_own_units = 104,
    must_target_friendly_units = 105,
    cant_target_friendly_units = 106,
    must_target_neutral_units = 107,
    cant_target_neutral_units = 108,
    must_target_enemy_units = 109,
    cant_target_enemy_units = 110,
    must_target_air_units = 111,
    cant_target_air_units = 112,
    must_target_ground_units = 113,
    cant_target_ground_units = 114,
    must_target_structures = 115,
    cant_target_structures = 116,
    must_target_light_units = 117,
    cant_target_light_units = 118,
    must_target_armored_units = 119,
    cant_target_armored_units = 120,
    must_target_biological_units = 121,
    cant_target_biological_units = 122,
    must_target_heroic_units = 123,
    cant_target_heroic_units = 124,
    must_target_robotic_units = 125,
    cant_target_robotic_units = 126,
    must_target_mechanical_units = 127,
    cant_target_mechanical_units = 128,
    must_target_psionic_units = 129,
    cant_target_psionic_units = 130,
    must_target_massive_units = 131,
    cant_target_massive_units = 132,
    must_target_missile = 133,
    cant_target_missile = 134,
    must_target_worker_units = 135,
    cant_target_worker_units = 136,
    must_target_energy_capable_units = 137,
    cant_target_energy_capable_units = 138,
    must_target_shield_capable_units = 139,
    cant_target_shield_capable_units = 140,
    must_target_flyers = 141,
    cant_target_flyers = 142,
    must_target_buried_units = 143,
    cant_target_buried_units = 144,
    must_target_cloaked_units = 145,
    cant_target_cloaked_units = 146,
    must_target_units_in_stasis_field = 147,
    cant_target_units_in_stasis_field = 148,
    must_target_under_construction_units = 149,
    cant_target_under_construction_units = 150,
    must_target_dead_units = 151,
    cant_target_dead_units = 152,
    must_target_revivable_units = 153,
    cant_target_revivable_units = 154,
    must_target_hidden_units = 155,
    cant_target_hidden_Units = 156,
    cant_recharge_other_players_units = 157,
    must_target_hallucinations = 158,
    cant_target_hallucinations = 159,
    must_target_invulnerable_units = 160,
    cant_target_invulnerable_units = 161,
    must_target_detected_units = 162,
    cant_target_detected_units = 163,
    cant_target_unit_with_energy = 164,
    cant_target_unit_with_shields = 165,
    must_target_uncommandable_units = 166,
    cant_target_uncommandable_units = 167,
    must_target_prevent_defeat_units = 168,
    cant_target_prevent_defeat_units = 169,
    must_target_prevent_reveal_units = 170,
    cant_target_prevent_reveal_units = 171,
    must_target_passive_units = 172,
    cant_target_passive_units = 173,
    must_target_stunned_units = 174,
    cant_target_stunned_units = 175,
    must_target_summoned_units = 176,
    cant_Target_summoned_units = 177,
    must_target_user1 = 178,
    cant_targeT_user1 = 179,
    must_target_unstoppable_units = 180,
    cant_target_unstoppable_units = 181,
    must_target_resistant_units = 182,
    cant_target_resistant_units = 183,
    must_target_dazed_units = 184,
    cant_target_dazed_units = 185,
    cant_lockdown = 186,
    cant_mind_control = 187,
    must_target_destructibles = 188,
    cant_target_destructibles = 189,
    must_target_items = 190,
    cant_target_items = 191,
    no_calldown_available = 192,
    waypoint_list_full = 193,
    must_target_race = 194,
    cant_target_race = 195,
    must_target_similar_units = 196,
    cant_target_similar_units = 197,
    cant_find_enough_targets = 198,
    already_spawning_larva = 199,
    cant_target_exhausted_resources = 200,
    cant_use_minimap = 201,
    cant_use_info_panel = 202,
    order_queue_is_full = 203,
    cant_harvest_that_resource = 204,
    harvesters_not_required = 205,
    already_targeted = 206,
    cant_attack_weapons_disabled = 207,
    coudlnt_reach_target = 208,
    target_is_out_of_range = 209,
    target_is_too_close = 210,
    target_is_out_of_arc = 211,
    cant_find_teleport_location = 212,
    invalid_item_class = 213,
    cant_find_cancel_order = 214,
};

pub const Alert = enum(u8) {
    nuclear_launch_detected = 1,
    nydus_worm_detected = 2,
    alert_error = 3,
    addon_complete = 4,
    building_complete = 5,
    building_under_attack = 6,
    larva_hatched = 7,
    marge_complete = 8,
    minerals_exhausted = 9,
    morph_complete = 10,
    mothership_complete = 11,
    mule_expired = 12,
    nuke_complete = 13,
    research_complete = 14,
    train_error = 15,
    train_unit_complete = 16,
    train_worker_complete = 17,
    transformation_complete = 18,
    unit_under_attack = 19,
    upgrade_complete = 20,
    vespene_exhausted = 21,
    warpin_complete = 22,
};

pub const RequestDebug = struct {
    commands: ProtoField(1, []DebugCommand) = .{},
};

pub const DebugCommand = struct {
    draw: ProtoField(1, DebugDraw) = .{},
    game_state: ProtoField(2, DebugGameState) = .{},
    create_unit: ProtoField(3, DebugCreateUnit) = .{},
    kill_unit: ProtoField(4, DebugKillUnit) = .{},
    test_process: ProtoField(5, DebugTestProcess) = .{},
    score: ProtoField(6, DebugSetScore) = .{},
    end_game: ProtoField(7, DebugEndGame) = .{},
    unit_value: ProtoField(8, DebugSetUnitValue) = .{},
};

pub const DebugDraw = struct {
    text: ProtoField(1, []DebugText) = .{},
    lines: ProtoField(2, []DebugLine) = .{},
    boxes: ProtoField(3, []DebugBox) = .{},
    spheres: ProtoField(4, []DebugSphere) = .{},
};

pub const Color = struct {
    r: ProtoField(1, u32) = .{},
    g: ProtoField(2, u32) = .{},
    b: ProtoField(3, u32) = .{},
};

pub const DebugText = struct {
    color: ProtoField(1, Color) = .{},
    text: ProtoField(2, []const u8) = .{},
    virtual_pos: ProtoField(3, Point) = .{},
    world_pos: ProtoField(4, Point) = .{},
    size: ProtoField(5, u32) = .{},
};

pub const Line = struct {
    p0: ProtoField(1, Point) = .{},
    p1: ProtoField(2, Point) = .{},
};

pub const DebugLine = struct {
    color: ProtoField(1, Color) = .{},
    line: ProtoField(2, Line) = .{},
};

pub const DebugBox = struct {
    color: ProtoField(1, Color) = .{},
    min: ProtoField(2, Point) = .{},
    max: ProtoField(3, Point) = .{},
};

pub const DebugSphere = struct {
    color: ProtoField(1, Color) = .{},
    p: ProtoField(2, Point) = .{},
    r: ProtoField(3, f32) = .{},
};

pub const DebugGameState = enum(u8) {
    show_map = 1,
    control_enemy = 2,
    food = 3,
    free = 4,
    all_resources = 5,
    god = 6,
    minerals = 7,
    gas = 8,
    cooldown = 9,
    tech_tree = 10,
    upgrade = 11,
    fast_build = 12,
};

pub const DebugCreateUnit = struct {
    unit_type: ProtoField(1, u32) = .{},
    owner: ProtoField(2, i32) = .{},
    pos: ProtoField(3, Point2D) = .{},
    quantity: ProtoField(4, u32) = .{},
};

pub const DebugKillUnit = struct {
    tags: ProtoField(1, []u64) = .{},
};

pub const TestProcessState = enum(u8) {
    hang = 1,
    crash = 2,
    exit = 3,
};

pub const DebugTestProcess = struct {
    state: ProtoField(1, TestProcessState) = .{},
    delay_ms: ProtoField(2, i32) = .{},
};

pub const DebugSetScore = struct {
    score: ProtoField(1, f32) = .{},
};

pub const EndResult = enum(u8) {
    surrender = 1,
    declare_victory = 2,
};

pub const DebugEndGame = struct {
    end_result: ProtoField(1, EndResult) = .{},
};

pub const UnitValue = enum(u8) {
    energy = 1,
    life = 2,
    shields = 3,
};

pub const DebugSetUnitValue = struct {
    unit_value: ProtoField(1, UnitValue) = .{},
    value: ProtoField(2, f32) = .{},
    unit_tag: ProtoField(3, u64) = .{},
};

pub const RequestData = struct {
    ability_id: ProtoField(1, bool) = .{},
    unit_id: ProtoField(2, bool) = .{},
    upgrade_id: ProtoField(3, bool) = .{},
    buff_id: ProtoField(4, bool) = .{},
    effect_id: ProtoField(5, bool) = .{},
};

pub const ResponseData = struct {
    //abilities: ProtoField(1, []AbilityData) = .{},
    units: ProtoField(2, []UnitTypeData) = .{},
    upgrades: ProtoField(3, []UpgradeData) = .{},
    //buffs: ProtoField(4, []BuffData) = .{},
    //effects: ProtoField(5, []EffectData) = .{},
};

pub const Attribute = enum(u8) {
    light = 1,
    armored = 2,
    biological = 3,
    mechanical = 4,
    robotic = 5,
    psionic = 6,
    massive = 7,
    structure = 8,
    hover = 9,
    heroic = 10,
    summoned = 11,
};

pub const TargetType = enum(u8) {
    ground = 1,
    air = 2,
    any = 3,
};

pub const DamageBonus = struct {
    attribute: ProtoField(1, Attribute) = .{},
    bonus: ProtoField(2, f32) = .{},
};

pub const Weapon = struct {
    target_type: ProtoField(1, TargetType) = .{},
    damage: ProtoField(2, f32) = .{},
    damage_bonus: ProtoField(3, []DamageBonus) = .{},
    attacks: ProtoField(4, u32) = .{},
    range: ProtoField(5, f32) = .{},
    speed: ProtoField(6, f32) = .{},
};

pub const UpgradeData = struct {
    upgrade_id: ProtoField(1, u32) = .{},
    name: ProtoField(2, []const u8) = .{},
    mineral_cost: ProtoField(3, u32) = .{},
    vespene_cost: ProtoField(4, u32) = .{},
    research_time: ProtoField(5, f32) = .{},
    ability_id: ProtoField(6, u32) = .{},
};

pub const UnitTypeData = struct {
    unit_id: ProtoField(1, u32) = .{},
    name: ProtoField(2, []const u8) = .{},
    available: ProtoField(3, bool) = .{},
    cargo_size: ProtoField(4, u32) = .{},
    attributes: ProtoField(8, []Attribute) = .{},
    movement_speed: ProtoField(9, f32) = .{},
    armor: ProtoField(10, f32) = .{},
    weapons: ProtoField(11, []Weapon) = .{},
    mineral_cost: ProtoField(12, u32) = .{},
    vespene_cost: ProtoField(13, u32) = .{},
    food_required: ProtoField(14, f32) = .{},
    ability_id: ProtoField(15, u32) = .{},
    race: ProtoField(16, Race) = .{},
    build_time: ProtoField(17, f32) = .{},
    food_provided: ProtoField(18, f32) = .{},
    has_vespene: ProtoField(19, bool) = .{},
    has_minerals: ProtoField(20, bool) = .{},
    sight_range: ProtoField(25, f32) = .{},
    tech_alias: ProtoField(21, []u32) = .{},
    unit_alias: ProtoField(22, u32) = .{},
    tech_requirement: ProtoField(23, u32) = .{},
    require_attached: ProtoField(24, bool) = .{},
};

