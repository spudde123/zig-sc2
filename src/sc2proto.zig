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
    pub const field_nums = .{
        .{"create_game", 1},
        .{"join_game", 2},
        .{"leave_game", 5},
        .{"quit", 8},
        .{"game_info", 9},
        .{"observation", 10},
        .{"action", 11},
        .{"step", 12},
        .{"game_data", 13},
        .{"query", 14},
        .{"save_replay", 15},
        .{"ping", 19},
        .{"debug", 20},
        .{"id", 97},
    };
    create_game: ?RequestCreateGame = null,
    join_game: ?RequestJoinGame = null,
    leave_game: ?void = null,
    quit: ?void = null,
    game_info: ?void = null,
    observation: ?RequestObservation = null,
    action: ?RequestAction = null,
    step: ?RequestStep = null,
    game_data: ?RequestData = null,
    query: ?RequestQuery = null,
    save_replay: ?void = null,
    ping: ?void = null,
    debug: ?RequestDebug = null,
    id: ?u32 = null,
};

pub const Response = struct {
    pub const field_nums = .{
        .{"create_game", 1},
        .{"join_game", 2},
        .{"leave_game", 5},
        .{"quit", 8},
        .{"game_info", 9},
        .{"observation", 10},
        .{"action", 11},
        .{"step", 12},
        .{"game_data", 13},
        .{"query", 14},
        .{"save_replay", 15},
        .{"ping", 19},
        .{"debug", 20},
        .{"id", 97},
        .{"errors", 98},
        .{"status", 99},
    };
    create_game: ?ResponseCreateGame = null,
    join_game: ?ResponseJoinGame = null,
    leave_game: ?void = null,
    quit: ?void = null,
    game_info: ?ResponseGameInfo = null,
    observation: ?ResponseObservation = null,
    action: ?ResponseAction = null,
    step: ?ResponseStep = null,
    game_data: ?ResponseData = null,
    query: ?ResponseQuery = null,
    save_replay: ?ResponseSaveReplay = null,
    ping: ?ResponsePing = null,
    debug: ?void = null,

    id: ?u32 = null,
    errors: ?[][]const u8 = null,
    status: ?Status = null,
};

pub const RequestCreateGame = struct {
    pub const field_nums = .{
        .{"map", 1},
        .{"player_setup", 3},
        .{"disable_fog", 4},
        .{"random_seed", 5},
        .{"realtime", 6},
    };
    map: ?LocalMap = null,
    player_setup: ?[]PlayerSetup = null,
    disable_fog: ?bool = null,
    random_seed: ?u32 = null,
    realtime: ?bool = null,
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
    pub const field_nums = .{
        .{"error_code", 1},
        .{"error_details", 2},
    };
    error_code: ?ErrorCreateGame = null,
    error_details: ?[]const u8 = null,
};

pub const RequestJoinGame = struct {
    pub const field_nums = .{
        .{"race", 1},
        .{"options", 3},
        .{"server_ports", 4},
        .{"client_ports", 5},
        .{"player_name", 7},
        .{"host_ip", 8},
    };
    race: ?Race = null,
    options: ?InterfaceOptions = null,
    server_ports: ?PortSet = null,
    client_ports: ?PortSet = null,
    player_name: ?[]const u8 = null,
    host_ip: ?[]const u8 = null,
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
    pub const field_nums = .{
        .{"player_id", 1},
        .{"error_code", 2},
        .{"error_details", 3},
    };
    player_id: ?u32 = null,
    error_code: ?ErrorJoinGame = null,
    error_details: ?[]const u8 = null,
};

pub const ResponseGameInfo = struct {
    pub const field_nums = .{
        .{"map_name", 1},
        .{"local_map_path", 2},
        .{"player_info", 3},
        .{"start_raw", 4},
        .{"options", 5},
        .{"mod_names", 6},
    };
    map_name: ?[]const u8 = null,
    local_map_path: ?[]const u8 = null,
    player_info: ?[]PlayerInfo = null,
    start_raw: ?StartRaw = null,
    options: ?InterfaceOptions = null,
    mod_names: ?[][]const u8 = null,
};

pub const RequestAction = struct {
    pub const field_nums = .{
        .{"actions", 1},
    };
    actions: ?[]Action = null,
};

pub const ResponseAction = struct {
    pub const field_nums = .{
        .{"results", 1},
    };
    results: ?[]ActionResult = null,
};

pub const RequestObservation = struct {
    pub const field_nums = .{
        .{"disable_fog", 1},
        .{"game_loop", 2},
    };
    disable_fog: ?bool = null,
    game_loop: ?u32 = null,
};

pub const RequestStep = struct {
    pub const field_nums = .{
        .{"count", 1},
    };
    count: ?u32 = null,
};

pub const ResponseStep = struct {
    pub const field_nums = .{
        .{"simulation_loop", 1},
    };
    simulation_loop: ?u32 = null,
};

pub const ResponsePing = struct {
    pub const field_nums = .{
        .{"game_version", 1},
        .{"data_version", 2},
        .{"data_build", 3},
        .{"base_build", 4},
    };
    game_version: ?[]const u8 = null,
    data_version: ?[]const u8 = null,
    data_build: ?u32 = null,
    base_build: ?u32 = null,
};

pub const ResponseSaveReplay = struct {
    pub const field_nums = .{
        .{"bytes", 1},
    };
    bytes: ?[]u8 = null,
};

pub const ResponseObservation = struct {
    pub const field_nums = .{
        .{"actions", 1},
        .{"action_errors", 2},
        .{"observation", 3},
        .{"player_result", 4},
        .{"chat", 5},
    };
    actions: ?[]Action = null,
    action_errors: ?[]ActionError = null,
    observation: ?Observation = null,
    player_result: ?[]PlayerResult = null,
    chat: ?[]ChatReceived = null,
};

pub const Observation = struct {
    pub const field_nums = .{
        .{"player_common", 1},
        .{"abilities", 3},
        .{"score", 4},
        .{"raw", 5},
        //.{"feature_layer", 6},
        //.{"render", 7},
        //.{"ui", 8},
        .{"game_loop", 9},
        .{"alerts", 10},
    };
    player_common: ?PlayerCommon = null,
    abilities: ?[]AvailableAbility = null,
    score: ?Score = null,

    raw: ?ObservationRaw = null,
    //feature_layer: ?ObservationFeatureLayer = null,
    //render: ?ObservationRender = null,
    //ui: ?ObservationUI = null,
    game_loop: ?u32 = null,
    alerts: ?[]Alert = null,
};

pub const PlayerCommon = struct {
    pub const field_nums = .{
        .{"player_id", 1},
        .{"minerals", 2},
        .{"vespene", 3},
        .{"food_cap", 4},
        .{"food_used", 5},
        .{"food_army", 6},
        .{"food_workers", 7},
        .{"idle_worker_count", 8},
        .{"army_count", 9},
        .{"warp_gate_count", 10},
        .{"larva_count", 11},
    };
    player_id: ?u32 = null,
    minerals: ?u32 = null,
    vespene: ?u32 = null,
    food_cap: ?u32 = null,
    food_used: ?u32 = null,
    food_army: ?u32 = null,
    food_workers: ?u32 = null,
    idle_worker_count: ?u32 = null,
    army_count: ?u32 = null,
    warp_gate_count: ?u32 = null,
    larva_count: ?u32 = null,
};

pub const ScoreType = enum(u8) {
    curriculum = 1,
    melee = 2,
};

pub const Score = struct {
    pub const field_nums = .{
        .{"score_type", 6},
        .{"score", 7},
        .{"details", 8},
    };
    score_type: ?ScoreType = null,
    score: ?i32 = null,
    details: ?ScoreDetails = null,
};

pub const CategoryScoreDetails = struct {
    pub const field_nums = .{
        .{"none", 1},
        .{"army", 2},
        .{"economy", 3},
        .{"technology", 4},
        .{"upgrade", 5},
    };
    none: ?f32 = null,
    army: ?f32 = null,
    economy: ?f32 = null,
    technology: ?f32 = null,
    upgrade: ?f32 = null,
};

pub const VitalScoreDetails = struct {
    pub const field_nums = .{
        .{"life", 1},
        .{"shields", 2},
        .{"energy", 3},
    };
    life: ?f32 = null,
    shields: ?f32 = null,
    energy: ?f32 = null,
};

pub const ScoreDetails = struct {
    pub const field_nums = .{
        .{"idle_production_time", 1},
        .{"idle_worker_time", 2},
        .{"total_value_units", 3},
        .{"total_value_structures", 4},
        .{"killed_value_units", 5},
        .{"killed_value_structures", 6},
        .{"collected_minerals", 7},
        .{"collected_vespene", 8},
        .{"collection_rate_minerals", 9},
        .{"collection_rate_vespene", 10},
        .{"spent_minerals", 11},
        .{"spent_vespene", 12},
        .{"food_used", 13},
        .{"killed_minerals", 14},
        .{"killed_vespene", 15},
        .{"lost_minerals", 16},
        .{"lost_vespene", 17},
        .{"friendly_fire_minerals", 18},
        .{"friendly_fire_vespene", 19},
        .{"used_minerals", 20},
        .{"used_vespene", 21},
        .{"total_used_minerals", 22},
        .{"total_used_vespene", 23},
        .{"total_damage_dealt", 24},
        .{"total_damage_taken", 25},
        .{"total_healed", 26},
        .{"current_apm", 27},
        .{"current_effective_apm", 28},
    };
    idle_production_time: ?f32 = null,
    idle_worker_time: ?f32 = null,
    total_value_units: ?f32 = null,
    total_value_structures: ?f32 = null,
    killed_value_units: ?f32 = null,
    killed_value_structures: ?f32 = null,
    collected_minerals: ?f32 = null,
    collected_vespene: ?f32 = null,
    collection_rate_minerals: ?f32 = null,
    collection_rate_vespene: ?f32 = null,
    spent_minerals: ?f32 = null,
    spent_vespene: ?f32 = null,
    food_used: ?CategoryScoreDetails = null,
    killed_minerals: ?CategoryScoreDetails = null,
    killed_vespene: ?CategoryScoreDetails = null,
    lost_minerals: ?CategoryScoreDetails = null,
    lost_vespene: ?CategoryScoreDetails = null,
    friendly_fire_minerals: ?CategoryScoreDetails = null,
    friendly_fire_vespene: ?CategoryScoreDetails = null,
    used_minerals: ?CategoryScoreDetails = null,
    used_vespene: ?CategoryScoreDetails = null,
    total_used_minerals: ?CategoryScoreDetails = null,
    total_used_vespene: ?CategoryScoreDetails = null,
    total_damage_dealt: ?VitalScoreDetails = null,
    total_damage_taken: ?VitalScoreDetails = null,
    total_healed: ?VitalScoreDetails = null,
    current_apm: ?f32 = null,
    current_effective_apm: ?f32 = null,
};

pub const ObservationRaw = struct {
    pub const field_nums = .{
        .{"player", 1},
        .{"units", 2},
        .{"map_state", 3},
        .{"event", 4},
        .{"effects", 5},
        .{"radars", 6},
    };
    player: ?PlayerRaw = null,
    units: ?[]Unit = null,
    map_state: ?MapState = null,
    event: ?Event = null,
    effects: ?[]Effect = null,
    radars: ?[]RadarRing = null,
};

pub const RadarRing = struct {
    pub const field_nums = .{
        .{"pos", 1},
        .{"radius", 2},
    };
    pos: ?Point = null,
    radius: ?f32 = null,
};

pub const PowerSource = struct {
    pub const field_nums = .{
        .{"pos", 1},
        .{"radius", 2},
        .{"tag", 3},
    };
    pos: ?Point = null,
    radius: ?f32 = null,
    tag: ?u64 = null,
};

pub const PlayerRaw = struct {
    pub const field_nums = .{
        .{"power_sources", 1},
        .{"camera", 2},
        .{"upgrade_ids", 3},
    };
    power_sources: ?[]PowerSource = null,
    camera: ?Point = null,
    upgrade_ids: ?[]u32 = null,
};

pub const MapState = struct {
    pub const field_nums = .{
        .{"visibility", 1},
        .{"creep", 2},
    };
    visibility: ?ImageData = null,
    creep: ?ImageData = null,
};

pub const Event = struct {
    pub const field_nums = .{
        .{"dead_units", 1},
    };
    dead_units: ?[]u64 = null,
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
    pub const field_nums = .{
        .{"effect_id", 1},
        .{"pos", 2},
        .{"alliance", 3},
        .{"owner", 4},
        .{"radius", 5},
    };
    effect_id: ?u32 = null,
    pos: ?[]Point2D = null,
    alliance: ?Alliance = null,
    owner: ?i32 = null,
    radius: ?f32 = null,
};

pub const RallyTarget = struct {
    pub const field_nums = .{
        .{"point", 1},
        .{"tag", 2},
    };
    point: ?Point = null,
    tag: ?u64 = null,
};

pub const UnitOrder = struct {
    pub const field_nums = .{
        .{"ability_id", 1},
        .{"target_world_space_pos", 2},
        .{"target_unit_tag", 3},
        .{"progress", 4},
    };
    ability_id: ?u32 = null,
    target_world_space_pos: ?Point = null,
    target_unit_tag: ?u64 = null,
    progress: ?f32 = null,
};

pub const PassengerUnit = struct {
    pub const field_nums = .{
        .{"tag", 1},
        .{"health", 2},
        .{"health_max", 3},
        .{"shield", 4},
        .{"shield_max", 7},
        .{"energy", 5},
        .{"energy_max", 8},
        .{"unit_type", 6},
    };
    tag: ?u64 = null,
    health: ?f32 = null,
    health_max: ?f32 = null,
    shield: ?f32 = null,
    shield_max: ?f32 = null,
    energy: ?f32 = null,
    energy_max: ?f32 = null,
    unit_type: ?u32 = null,
};

pub const Unit = struct {
    pub const field_nums = .{
        .{"display_type", 1},
        .{"alliance", 2},
        .{"tag", 3},
        .{"unit_type", 4},
        .{"owner", 5},
        .{"pos", 6},
        .{"facing", 7},
        .{"radius", 8},
        .{"build_progress", 9},
        .{"cloak", 10},
        .{"buff_ids", 27},
        .{"detect_range", 31},
        .{"radar_range", 32},
        .{"is_selected", 11},
        .{"is_on_screen", 12},
        .{"is_blip", 13},
        .{"is_powered", 35},
        .{"is_active", 39},
        .{"attack_upgrade_level", 40},
        .{"armor_upgrade_level", 41},
        .{"shield_upgrade_level", 42},
        .{"health", 14},
        .{"health_max", 15},
        .{"shield", 16},
        .{"shield_max", 36},
        .{"energy", 17},
        .{"energy_max", 37},
        .{"mineral_contents", 18},
        .{"vespene_contents", 19},
        .{"is_flying", 20},
        .{"is_burrowed", 21},
        .{"is_hallucination", 38},
        .{"orders", 22},
        .{"addon_tag", 23},
        .{"passengers", 24},
        .{"cargo_space_taken", 25},
        .{"cargo_space_max", 26},
        .{"assigned_harvesters", 28},
        .{"ideal_harvesters", 29},
        .{"weapon_cooldown", 30},
        .{"engaged_target_tag", 34},
        .{"buff_duration_remain", 43},
        .{"buff_duration_max", 44},
        .{"rally_targets", 45},
    };
    display_type: ?DisplayType = null,
    alliance: ?Alliance = null,
    tag: ?u64 = null,
    unit_type: ?u32 = null,
    owner: ?i32 = null,
    
    pos: ?Point = null,
    facing: ?f32 = null,
    radius: ?f32 = null,
    build_progress: ?f32 = null,
    cloak: ?CloakState = null,
    buff_ids: ?[]u32 = null,

    detect_range: ?f32 = null,
    radar_range: ?f32 = null,

    is_selected: ?bool = null,
    is_on_screen: ?bool = null,
    is_blip: ?bool = null,
    is_powered: ?bool = null,
    is_active: ?bool = null,

    attack_upgrade_level: ?i32 = null,
    armor_upgrade_level: ?i32 = null,
    shield_upgrade_level: ?i32 = null,

    health: ?f32 = null,
    health_max: ?f32 = null,
    shield: ?f32 = null,
    shield_max: ?f32 = null,
    energy: ?f32 = null,
    energy_max: ?f32 = null,
    mineral_contents: ?i32 = null,
    vespene_contents: ?i32 = null,
    is_flying: ?bool = null,
    is_burrowed: ?bool = null,
    is_hallucination: ?bool = null,

    orders: ?[]UnitOrder = null,
    addon_tag: ?u64 = null,
    passengers: ?[]PassengerUnit = null,
    cargo_space_taken: ?i32 = null,
    cargo_space_max: ?i32 = null,
    
    assigned_harvesters: ?i32 = null,
    ideal_harvesters: ?i32 = null,
    weapon_cooldown: ?f32 = null,
    engaged_target_tag: ?u64 = null,
    buff_duration_remain: ?i32 = null,
    buff_duration_max: ?i32 = null,
    rally_targets:?[]RallyTarget = null,    
};

pub const Action = struct {
    pub const field_nums = .{
        .{"action_raw", 1},
        //.{"action_feature_layer", 2},
        //.{"action_render", 3},
        //.{"action_ui", 4},
        .{"action_chat", 6},
        .{"game_loop", 7}
    };
    action_raw: ?ActionRaw = null,
    //action_feature_layer: ?ActionSpatial = null,
    //action_render: ?ActionSpatial = null,
    //action_ui: ?ActionUI = null,
    action_chat: ?ActionChat = null,
    game_loop: ?u32 = null,
};

pub const ActionError = struct {
    pub const field_nums = .{
        .{"unit_tag", 1},
        .{"ability_id", 2},
        .{"result", 3},
    };
    unit_tag: ?u64 = null,
    ability_id: ?u64 = null,
    result: ?ActionResult = null,
};

pub const PlayerResult = struct {
    pub const field_nums = .{
        .{"player_id", 1},
        .{"result", 2},
    };
    player_id: ?u32 = null,
    result: ?Result = null,
};

pub const Result = enum(u8) {
    victory = 1,
    defeat = 2,
    tie = 3,
    undecided = 4,
};

pub const ChatReceived = struct {
    pub const field_nums = .{
        .{"player_id", 1},
        .{"message", 2},
    };
    player_id: ?u32 = null,
    message: ?[]const u8 = null,
};

pub const Channel = enum(u8) {
    broadcast = 1,
    team = 2,
};

pub const ActionChat = struct {
    pub const field_nums = .{
        .{"channel", 1},
        .{"message", 2},
    };
    channel: ?Channel = null,
    message: ?[]const u8 = null,
};

pub const ActionRaw = struct {
    pub const field_nums = .{
        .{"unit_command", 1},
        .{"camera_move", 2},
        .{"toggle_autocast", 3},
    };
    unit_command: ?ActionRawUnitCommand = null,
    camera_move: ?ActionRawCameraMove = null,
    toggle_autocast: ?ActionRawToggleAutocast = null,
};

pub const ActionRawUnitCommand = struct {
    pub const field_nums = .{
        .{"ability_id", 1},
        .{"target_world_space_pos", 2},
        .{"target_unit_tag", 3},
        .{"unit_tags", 4},
        .{"queue_command", 5},
    };
    ability_id: ?i32 = null,
    target_world_space_pos: ?Point2D = null,
    target_unit_tag: ?u64 = null,
    unit_tags: ?[]u64 = null,
    queue_command: ?bool = null,
};

pub const ActionRawCameraMove = struct {
    pub const field_nums = .{
        .{"point", 1},
    };
    point: ?Point = null,
};

pub const ActionRawToggleAutocast = struct {
    pub const field_nums = .{
        .{"ability_id", 1},
        .{"unit_tags", 2},
    };
    ability_id: ?i32 = null,
    unit_tags: ?[]u64 = null,
};

pub const PlayerInfo = struct {
    pub const field_nums = .{
        .{"player_id", 1},
        .{"player_type", 2},
        .{"race_requested", 3},
        .{"race_actual", 4},
        .{"difficulty", 5},
        .{"player_name", 6},
        .{"ai_build", 7},
    };
    player_id: ?u32 = null,
    player_type: ?PlayerType = null,
    race_requested: ?Race = null,
    race_actual: ?Race = null,
    difficulty: ?AiDifficulty = null,
    player_name: ?[]const u8 = null,
    ai_build: ?AiBuild = null,
};

pub const InterfaceOptions = struct {
    pub const field_nums = .{
        .{"raw", 1},
        .{"score", 2},
        //.{"feature_layer", 3},
        //.{"render", 4},
        .{"show_cloaked", 5},
        .{"raw_affects_selection", 6},
        .{"raw_crop_to_playable_area", 7},
        .{"show_placeholders", 8},
        .{"show_burrowed_shadows", 9},
    };
    raw: ?bool = null,
    score: ?bool = null,
    //feature_layer: ?SpatialCameraSetu = null,
    //render: ?SpatialCameraSetup = null,
    show_cloaked: ?bool = null,
    raw_affects_selection: ?bool = null,
    raw_crop_to_playable_area: ?bool = null,
    show_placeholders: ?bool = null,
    show_burrowed_shadows: ?bool = null,
};

pub const PortSet = struct {
    pub const field_nums = .{
        .{"game_port", 1},
        .{"base_port", 2},
    };
    game_port: ?i32 = null,
    base_port: ?i32 = null,
};

pub const LocalMap = struct {
    pub const field_nums = .{
        .{"map_path", 1},
    };
    map_path: ?[]const u8 = null,
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
    pub const field_nums = .{
        .{"player_type", 1},
        .{"race", 2},
        .{"difficulty", 3},
        .{"name", 4},
        .{"ai_build", 5},
    };
    player_type: ?PlayerType = null,

    // For computer players
    race: ?Race = null,
    difficulty: ?AiDifficulty = null,
    name: ?[]const u8 = null,
    ai_build: ?AiBuild = null,
};

pub const Size2DI = struct {
    pub const field_nums = .{
        .{"x", 1},
        .{"y", 2},
    };
    x: ?i32 = null,
    y: ?i32 = null,
};

pub const PointI = struct {
    pub const field_nums = .{
        .{"x", 1},
        .{"y", 2},
    };
    x: ?i32 = null,
    y: ?i32 = null,
};

pub const RectangleI = struct {
    pub const field_nums = .{
        .{"p0", 1},
        .{"p1", 2},
    };
    p0: ?PointI = null,
    p1: ?PointI = null,
};

pub const Point2D = struct {
    pub const field_nums = .{
        .{"x", 1},
        .{"y", 2},
    };
    x: ?f32 = null,
    y: ?f32 = null,
};

pub const Point = struct {
    pub const field_nums = .{
        .{"x", 1},
        .{"y", 2},
        .{"z", 3},
    };
    x: ?f32 = null,
    y: ?f32 = null,
    z: ?f32 = null,
};

pub const ImageData = struct {
    pub const field_nums = .{
        .{"bits_per_pixel", 1},
        .{"size", 2},
        .{"image", 3},
    };
    bits_per_pixel: ?i32 = null,
    size: ?Size2DI = null,
    image: ?[]u8 = null,
};

pub const AvailableAbility = struct {
    pub const field_nums = .{
        .{"ability_id", 1},
        .{"requires_point", 2},
    };
    ability_id: ?i32 = null,
    requires_point: ?bool = null,
};

pub const StartRaw = struct {
    pub const field_nums = .{
        .{"map_size", 1},
        .{"pathing_grid", 2},
        .{"terrain_height", 3},
        .{"placement_grid", 4},
        .{"playable_area", 5},
        .{"start_locations", 6},
    };
    map_size: ?Size2DI = null,
    pathing_grid: ?ImageData = null,
    terrain_height: ?ImageData = null,
    placement_grid: ?ImageData = null,
    playable_area: ?RectangleI = null,
    start_locations: ?[]Point2D = null,
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
    cant_target_summoned_units = 177,
    must_target_user1 = 178,
    cant_target_user1 = 179,
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
    pub const field_nums = .{
        .{"commands", 1},
    };
    commands: ?[]DebugCommand = null,
};

pub const DebugCommand = struct {
    pub const field_nums = .{
        .{"draw", 1},
        .{"game_state", 2},
        .{"create_unit", 3},
        .{"kill_unit", 4},
        .{"test_process", 5},
        .{"score", 6},
        .{"end_game", 7},
        .{"unit_value", 8},
    };
    draw: ?DebugDraw = null,
    game_state: ?DebugGameState = null,
    create_unit: ?DebugCreateUnit = null,
    kill_unit: ?DebugKillUnit = null,
    test_process: ?DebugTestProcess = null,
    score: ?DebugSetScore = null,
    end_game: ?DebugEndGame = null,
    unit_value: ?DebugSetUnitValue = null,
};

pub const DebugDraw = struct {
    pub const field_nums = .{
        .{"text", 1},
        .{"lines", 2},
        .{"boxes", 3},
        .{"spheres", 4},
    };
    text: ?[]DebugText = null,
    lines: ?[]DebugLine = null,
    boxes: ?[]DebugBox = null,
    spheres: ?[]DebugSphere = null,
};

pub const Color = struct {
    pub const field_nums = .{
        .{"r", 1},
        .{"g", 2},
        .{"b", 3},
    };
    r: ?u32 = null,
    g: ?u32 = null,
    b: ?u32 = null,
};

pub const DebugText = struct {
    pub const field_nums = .{
        .{"color", 1},
        .{"text", 2},
        .{"virtual_pos", 3},
        .{"world_pos", 4},
        .{"size", 5},
    };
    color: ?Color = null,
    text: ?[]const u8 = null,
    virtual_pos: ?Point = null,
    world_pos: ?Point = null,
    size: ?u32 = null,
};

pub const Line = struct {
    pub const field_nums = .{
        .{"p0", 1},
        .{"p1", 2},
    };
    p0: ?Point = null,
    p1: ?Point = null,
};

pub const DebugLine = struct {
    pub const field_nums = .{
        .{"color", 1},
        .{"line", 2},
    };
    color: ?Color = null,
    line: ?Line = null,
};

pub const DebugBox = struct {
    pub const field_nums = .{
        .{"color", 1},
        .{"min", 2},
        .{"max", 3},
    };
    color: ?Color = null,
    min: ?Point = null,
    max: ?Point = null,
};

pub const DebugSphere = struct {
    pub const field_nums = .{
        .{"color", 1},
        .{"p", 2},
        .{"r", 3},
    };
    color: ?Color = null,
    p: ?Point = null,
    r: ?f32 = null,
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
    pub const field_nums = .{
        .{"unit_type", 1},
        .{"owner", 2},
        .{"pos", 3},
        .{"quantity", 4},
    };
    unit_type: ?u32 = null,
    owner: ?i32 = null,
    pos: ?Point2D = null,
    quantity: ?u32 = null,
};

pub const DebugKillUnit = struct {
    pub const field_nums = .{
        .{"tags", 1},
    };
    tags: ?[]u64 = null,
};

pub const TestProcessState = enum(u8) {
    hang = 1,
    crash = 2,
    exit = 3,
};

pub const DebugTestProcess = struct {
    pub const field_nums = .{
        .{"state", 1},
        .{"delay_ms", 2},
    };
    state: ?TestProcessState = null,
    delay_ms: ?i32 = null,
};

pub const DebugSetScore = struct {
    pub const field_nums = .{
        .{"score", 1},
    };
    score: ?f32 = null,
};

pub const EndResult = enum(u8) {
    surrender = 1,
    declare_victory = 2,
};

pub const DebugEndGame = struct {
    pub const field_nums = .{
        .{"end_result", 1},
    };
    end_result: ?EndResult = null,
};

pub const UnitValue = enum(u8) {
    energy = 1,
    life = 2,
    shields = 3,
};

pub const DebugSetUnitValue = struct {
    pub const field_nums = .{
        .{"unit_value", 1},
        .{"value", 2},
        .{"unit_tag", 3},
    };
    unit_value: ?UnitValue = null,
    value: ?f32 = null,
    unit_tag: ?u64 = null,
};

pub const RequestData = struct {
    pub const field_nums = .{
        .{"ability_id", 1},
        .{"unit_id", 2},
        .{"upgrade_id", 3},
        .{"buff_id", 4},
        .{"effect_id", 5},
    };
    ability_id: ?bool = null,
    unit_id: ?bool = null,
    upgrade_id: ?bool = null,
    buff_id: ?bool = null,
    effect_id: ?bool = null,
};

pub const ResponseData = struct {
    pub const field_nums = .{
        //.{"abilities", 1},
        .{"units", 2},
        .{"upgrades", 3},
        //.{"buffs", 4},
        //.{"effects", 5},
    };
    //abilities: ?[]AbilityData = null,
    units: ?[]UnitTypeData = null,
    upgrades: ?[]UpgradeData = null,
    //buffs: ?[]BuffData = null,
    //effects: ?[]EffectData = null,
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
    pub const field_nums = .{
        .{"attribute", 1},
        .{"bonus", 2},
    };
    attribute: ?Attribute = null,
    bonus: ?f32 = null,
};

pub const Weapon = struct {
    pub const field_nums = .{
        .{"target_type", 1},
        .{"damage", 2},
        .{"damage_bonus", 3},
        .{"attacks", 4},
        .{"range", 5},
        .{"speed", 6},
    };
    target_type: ?TargetType = null,
    damage: ?f32 = null,
    damage_bonus: ?[]DamageBonus = null,
    attacks: ?u32 = null,
    range: ?f32 = null,
    speed: ?f32 = null,
};

pub const UpgradeData = struct {
    pub const field_nums = .{
        .{"upgrade_id", 1},
        .{"name", 2},
        .{"mineral_cost", 3},
        .{"vespene_cost", 4},
        .{"research_time", 5},
        .{"ability_id", 6},
    };
    upgrade_id: ?u32 = null,
    name: ?[]const u8 = null,
    mineral_cost: ?u32 = null,
    vespene_cost: ?u32 = null,
    research_time: ?f32 = null,
    ability_id: ?u32 = null,
};

pub const UnitTypeData = struct {
    pub const field_nums = .{
        .{"unit_id", 1},
        .{"name", 2},
        .{"available", 3},
        .{"cargo_size", 4},
        .{"attributes", 8},
        .{"movement_speed", 9},
        .{"armor", 10},
        .{"weapons", 11},
        .{"mineral_cost", 12},
        .{"vespene_cost", 13},
        .{"food_required", 14},
        .{"ability_id", 15},
        .{"race", 16},
        .{"build_time", 17},
        .{"food_provided", 18},
        .{"has_vespene", 19},
        .{"has_minerals", 20},
        .{"sight_range", 25},
        .{"tech_alias", 21},
        .{"unit_alias", 22},
        .{"tech_requirement", 23},
        .{"require_attached", 24},
    };
    unit_id: ?u32 = null,
    name: ?[]const u8 = null,
    available: ?bool = null,
    cargo_size: ?u32 = null,
    attributes: ?[]Attribute = null,
    movement_speed: ?f32 = null,
    armor: ?f32 = null,
    weapons: ?[]Weapon = null,
    mineral_cost: ?u32 = null,
    vespene_cost: ?u32 = null,
    food_required: ?f32 = null,
    ability_id: ?u32 = null,
    race: ?Race = null,
    build_time: ?f32 = null,
    food_provided: ?f32 = null,
    has_vespene: ?bool = null,
    has_minerals: ?bool = null,
    sight_range: ?f32 = null,
    tech_alias: ?[]u32 = null,
    unit_alias: ?u32 = null,
    tech_requirement: ?u32 = null,
    require_attached: ?bool = null,
};

pub const RequestQuery = struct {
    pub const field_nums = .{
        .{"pathing", 1},
        .{"abilities", 2},
        .{"placements", 3},
        .{"ignore_resource_requirements", 4},
    };
    pathing: ?[]RequestQueryPathing = null,
    abilities: ?[]RequestQueryAvailableAbilities = null,
    placements: ?[]RequestQueryBuildingPlacement = null,
    ignore_resource_requirements: ?bool = null,
};

pub const ResponseQuery = struct {
    pub const field_nums = .{
        .{"pathing", 1},
        .{"abilities", 2},
        .{"placements", 3},
    };
    pathing: ?[]ResponseQueryPathing = null,
    abilities: ?[]ResponseQueryAvailableAbilities = null,
    placements: ?[]ResponseQueryBuildingPlacement = null,
};

pub const RequestQueryPathing = struct {
    pub const field_nums = .{
        .{"start_pos", 1},
        .{"unit_tag", 2},
        .{"end_pos", 3},
    };
    start_pos: ?Point2D = null,
    unit_tag: ?u64 = null,
    end_pos: ?Point2D = null,
};

pub const ResponseQueryPathing = struct {
    pub const field_nums = .{
        .{"distance", 1},
    };
    distance: ?f32 = null,
};

pub const RequestQueryAvailableAbilities = struct {
    pub const field_nums = .{
        .{"unit_tag", 1},
    };
    unit_tag: ?u64 = null,
};

pub const ResponseQueryAvailableAbilities = struct {
    pub const field_nums = .{
        .{"abilities", 1},
        .{"unit_tag", 2},
        .{"unit_type_id", 3},
    };
    abilities: ?[]AvailableAbility = null,
    unit_tag: ?u64 = null,
    unit_type_id: ?u32 = null
};

pub const RequestQueryBuildingPlacement = struct {
    pub const field_nums = .{
        .{"ability_id", 1},
        .{"target_pos", 2},
        .{"placing_unit_tag", 3},
    };
    ability_id: ?i32 = null,
    target_pos: ?Point2D = null,
    placing_unit_tag: ?u64 = null,
};

pub const ResponseQueryBuildingPlacement = struct {
    pub const field_nums = .{
        .{"result", 1},
    };
    result: ?ActionResult = null,
};
