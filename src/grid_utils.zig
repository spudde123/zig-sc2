const std = @import("std");
const mem = std.mem;

const UnitId = @import("ids/unit_id.zig").UnitId;
const Unit = @import("units.zig").Unit;
const grids = @import("grids.zig");
const Grid = grids.Grid;
const Point2 = grids.Point2;
const GridSize = grids.GridSize;

const buildings_2x2 = [_]UnitId{
    .SupplyDepot,
    .Pylon,
    .DarkShrine,
    .PhotonCannon,
    .ShieldBattery,
    .MissileTurret,
    .TechLab,
    .StarportTechLab,
    .FactoryTechLab,
    .BarracksTechLab,
    .Reactor,
    .StarportReactor,
    .FactoryReactor,
    .BarracksReactor,
    .SporeCrawler,
    .Spire,
    .GreaterSpire,
    .SpineCrawler,
};

const buildings_3x3 = [_]UnitId{
    .Gateway,
    .WarpGate,
    .CyberneticsCore,
    .Forge,
    .RoboticsFacility,
    .RoboticsBay,
    .TemplarArchive,
    .TwilightCouncil,
    .Stargate,
    .FleetBeacon,
    .Assimilator,
    .AssimilatorRich,
    .SpawningPool,
    .RoachWarren,
    .HydraliskDen,
    .BanelingNest,
    .EvolutionChamber,
    .NydusNetwork,
    .NydusCanal,
    .Extractor,
    .ExtractorRich,
    .InfestationPit,
    .UltraliskCavern,
    .Barracks,
    .EngineeringBay,
    .Factory,
    .GhostAcademy,
    .Starport,
    .FusionReactor,
    .Bunker,
    .Armory,
    .Refinery,
    .RefineryRich,
};

const buildings_5x5 = [_]UnitId{
    .Nexus,
    .Hatchery,
    .Hive,
    .Lair,
    .CommandCenter,
    .OrbitalCommand,
    .PlanetaryFortress,
};

const destructible_2x1 = [_]UnitId{
    .MineralField450,
};

const destructible_2x2 = [_]UnitId{
    .Rocks2x2NonConjoined,
    .Debris2x2NonConjoined,
};

const destructible_4x4 = [_]UnitId{
    .DestructibleCityDebris4x4,
    .DestructibleDebris4x4,
    .DestructibleIce4x4,
    .DestructibleRock4x4,
    .DestructibleRockEx14x4,
};

const destructible_4x2 = [_]UnitId{
    .DestructibleCityDebris2x4Horizontal,
    .DestructibleIce2x4Horizontal,
    .DestructibleRock2x4Horizontal,
    .DestructibleRockEx12x4Horizontal,
};

const destructible_2x4 = [_]UnitId{
    .DestructibleCityDebris2x4Vertical,
    .DestructibleIce2x4Vertical,
    .DestructibleRock2x4Vertical,
    .DestructibleRockEx12x4Vertical,
};

const destructible_6x2 = [_]UnitId{
    .DestructibleCityDebris2x6Horizontal,
    .DestructibleIce2x6Horizontal,
    .DestructibleRock2x6Horizontal,
    .DestructibleRockEx12x6Horizontal,
};

const destructible_2x6 = [_]UnitId{
    .DestructibleCityDebris2x6Vertical,
    .DestructibleIce2x6Vertical,
    .DestructibleRock2x6Vertical,
    .DestructibleRockEx12x6Vertical,
};

const destructible_4x12 = [_]UnitId{
    .DestructibleRockEx1VerticalHuge,
    .DestructibleIceVerticalHuge,
    // What map includes this, should be the same size
    // according to the name??
    .DestructibleRampVerticalHuge
};

const destructible_12x4 = [_]UnitId{
    .DestructibleRockEx1HorizontalHuge,
    .DestructibleIceHorizontalHuge,
    .DestructibleRampHorizontalHuge,
};

const destructible_6x6 = [_]UnitId{
    .DestructibleCityDebris6x6,
    .DestructibleDebris6x6,
    .DestructibleIce6x6,
    .DestructibleRock6x6,
    .DestructibleRockEx16x6,
    .DestructibleRock6x6Weak,
    .DestructibleExpeditionGate6x6,
};

const destructible_blur = [_]UnitId{
    .DestructibleCityDebrisHugeDiagonalBLUR,
    .DestructibleDebrisRampDiagonalHugeBLUR,
    .DestructibleIceDiagonalHugeBLUR,
    .DestructibleRockEx1DiagonalHugeBLUR,
    .DestructibleRampDiagonalHugeBLUR,
};

const destructible_ulbr = [_]UnitId{
    .DestructibleCityDebrisHugeDiagonalULBR,
    .DestructibleDebrisRampDiagonalHugeULBR,
    .DestructibleIceDiagonalHugeULBR,
    .DestructibleRockEx1DiagonalHugeULBR,
    .DestructibleRampDiagonalHugeULBR
};

/// Used for getting the building footprint when we are trying to place it
/// on a placement grid
pub fn getBuildableSize(unit_type: UnitId) GridSize {
    // These are normally of 2x2 size, but when you try to place them
    // it means you are placing both the main building
    // and the addon. Let's make it so that we also leave 2 space
    // on the left side of the main building so units have space
    // to move around in the base (and it allows us to also
    // test the footprint the same way as symmetrical sizes)
    const exceptions = [_]UnitId{
        .BarracksTechLab,
        .BarracksReactor,
        .FactoryTechLab,
        .FactoryReactor,
        .StarportTechLab,
        .StarportReactor,
    };
    if (mem.indexOfScalar(UnitId, &exceptions, unit_type)) |_| return .{.w = 7, .h = 3};
    if (mem.indexOfScalar(UnitId, &buildings_2x2, unit_type)) |_| return .{.w = 2, .h = 2};
    if (mem.indexOfScalar(UnitId, &buildings_3x3, unit_type)) |_| return .{.w = 3, .h = 3};
    if (mem.indexOfScalar(UnitId, &buildings_5x5, unit_type)) |_| return .{.w = 5, .h = 5};
    return .{.w = 1, .h = 1};
}

pub fn findPlacement(placement_grid: Grid, unit: UnitId, near: Point2, max_distance: f32) ?Point2 {
    std.debug.assert(max_distance >= 1 and max_distance <= 30);
    const size = getBuildableSize(unit);
    var pos = near.floor();
    if (@mod(size.w, 2) == 1) pos.x += 0.5;
    if (@mod(size.h, 2) == 1) pos.y += 0.5;
    
    var options: [256]Point2 = undefined;
    var outer_dist: f32 = 1;
    while (outer_dist <= max_distance) : (outer_dist += 1) {
        var option_count: usize = 0;
        var inner_dist: f32 = -outer_dist;
        while (inner_dist <= outer_dist) : (inner_dist += 1) {
            const pos1 = .{.x = pos.x + inner_dist, .y = pos.y + outer_dist};
            if (queryPlacementSize(placement_grid, size, pos1)) {
                options[option_count] = pos1;
                option_count += 1;
            }
            const pos2 = .{.x = pos.x + inner_dist, .y = pos.y - outer_dist};
            if (queryPlacementSize(placement_grid, size, pos2)) {
                options[option_count] = pos2;
                option_count += 1;
            }
            const pos3 = .{.x = pos.x + outer_dist, .y = pos.y + inner_dist};
            if (queryPlacementSize(placement_grid, size, pos3)) {
                options[option_count] = pos3;
                option_count += 1;
            }
            const pos4 = .{.x = pos.x - outer_dist, .y = pos.y + inner_dist};
            if (queryPlacementSize(placement_grid, size, pos4)) {
                options[option_count] = pos4;
                option_count += 1;
            }
        }
        var min_dist: f32 = std.math.f32_max;
        var min_index: usize = options.len;
        for (options[0..option_count]) |point, i| {
            const dist = pos.distanceSquaredTo(point);
            if (dist < min_dist) {
                min_dist = dist;
                min_index = i;
            }
        }
        if (min_index < options.len) return options[min_index];
    }
    return null;
}

fn queryPlacementSize(placement_grid: Grid, size: GridSize, pos: Point2) bool {
    const pos_x = @floatToInt(usize, pos.x);
    const start_x = pos_x - @divFloor(size.w, 2);

    const pos_y = @floatToInt(usize, pos.y);
    var y = pos_y - @divFloor(size.h, 2);
    const end_y = y + size.h;

    while (y < end_y) : (y += 1) {
        const start = start_x + y*placement_grid.w;
        const end = start + size.w;
        if(!mem.allEqual(u8, placement_grid.data[start..end], 1)) return false;
    }
    return true;
}

pub fn queryPlacement(placement_grid: Grid, unit: UnitId, pos: Point2) ?Point2 {
    const size = getBuildableSize(unit);
    // Doing this adjustment because when we build according to the grid we are
    // keeping we seem to have problems if we start placing buildings not exactly
    // at a grid cell intersection or exactly in the middle. Not sure
    // what the reason is exactly
    var adjusted_pos = pos.floor();
    if (@mod(size.w, 2) == 1) adjusted_pos.x += 0.5;
    if (@mod(size.h, 2) == 1) adjusted_pos.y += 0.5;
    if (queryPlacementSize(placement_grid, size, adjusted_pos)) return adjusted_pos else return null;
}

pub fn setBuildingToValue(grid: Grid, unit: Unit, value: u8) void {
    const index = grid.pointToIndex(unit.position);
    if (mem.indexOfScalar(UnitId, &buildings_2x2, unit.unit_type)) |_| {
        grid.data[index - 1] = value;
        grid.data[index] = value;
        grid.data[index - 1 - grid.w] = value;
        grid.data[index - grid.w] = value;
        return;
    }

    if (mem.indexOfScalar(UnitId, &buildings_3x3, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 1;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 1 + grid.w*y;
            const end = unit_x + 2 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &buildings_5x5, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        // These have the corners cut off
        // in the pathing grid but let's just keep it a
        // square so the placement grid is also
        // guaranteed to handle it properly
        var y: usize = unit_y - 2;
        while (y < unit_y + 3) : (y += 1) {
            const start = unit_x - 2 + grid.w*y;
            const end = unit_x + 3 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    // If we have a 1x1 sized building (sensor tower?)
    grid.data[index] = value;
}

pub fn setMineralToValue(grid: Grid, unit: Unit, value: u8) void {
    const index = grid.pointToIndex(unit.position);
    grid.data[index - 1] = value;
    grid.data[index] = value;
}

pub fn setDestructibleToValue(grid: Grid, unit: Unit, value: u8) void {

    if (mem.indexOfScalar(UnitId, &destructible_2x1, unit.unit_type)) |_| {
        const index = grid.pointToIndex(unit.position);
        grid.data[index - 1] = value;
        grid.data[index] = value;
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_2x2, unit.unit_type)) |_| {
        const index = grid.pointToIndex(unit.position);
        grid.data[index - 1] = value;
        grid.data[index] = value;
        grid.data[index - 1 - grid.w] = value;
        grid.data[index - grid.w] = value;
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_4x4, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 2;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 2 + grid.w*y;
            const end = unit_x + 2 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_2x4, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 2;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 1 + grid.w*y;
            const end = unit_x + 1 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_4x2, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 1;
        while (y < unit_y + 1) : (y += 1) {
            const start = unit_x - 2 + grid.w*y;
            const end = unit_x + 2 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_2x6, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 3;
        while (y < unit_y + 3) : (y += 1) {
            const start = unit_x - 1 + grid.w*y;
            const end = unit_x + 1 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_6x2, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 1;
        while (y < unit_y + 1) : (y += 1) {
            const start = unit_x - 3 + grid.w*y;
            const end = unit_x + 3 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_4x12, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 6;
        while (y < unit_y + 6) : (y += 1) {
            const start = unit_x - 2 + grid.w*y;
            const end = unit_x + 2 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_12x4, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        var y: usize = unit_y - 2;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 6 + grid.w*y;
            const end = unit_x + 6 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_6x6, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);
        // These should be 6x6 (with their corners cut off?) but
        // depending on the map and map position it seems it's either
        // exactly that or one cell too high or too low.
        // Taking only 4x6 away from the middle so hopefully
        // we don't mark stuff pathable that isn't, and this
        // should allow units to pass through these rocks anyway
        var y: usize = unit_y - 2;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 3 + grid.w*y;
            const end = unit_x + 3 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        return;
    }

    // These below have a strange shape
    if (mem.indexOfScalar(UnitId, &destructible_blur, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);

        var y: usize = unit_y + 4;
        var start_x: usize = unit_x + 1;
        var row_len: usize = 3;
        var start: usize = start_x + grid.w*y;
        var end: usize = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 3;
        start_x = unit_x;
        row_len = 4;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 2;
        start_x = unit_x - 1;
        row_len = 6;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 1;
        start_x = unit_x - 2;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y;
        start_x = unit_x - 3;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 1;
        start_x = unit_x - 4;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 2;
        start_x = unit_x - 5;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 3;
        start_x = unit_x - 5;
        row_len = 6;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 4;
        start_x = unit_x - 4;
        row_len = 4;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 5;
        start_x = unit_x - 3;
        row_len = 2;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);
        return;
    }

    if (mem.indexOfScalar(UnitId, &destructible_ulbr, unit.unit_type)) |_| {
        const unit_x = @floatToInt(usize, unit.position.x);
        const unit_y = @floatToInt(usize, unit.position.y);

        var y: usize = unit_y - 5;
        var start_x: usize = unit_x + 1;
        var row_len: usize = 3;
        var start: usize = start_x + grid.w*y;
        var end: usize = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 4;
        start_x = unit_x;
        row_len = 4;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 3;
        start_x = unit_x - 1;
        row_len = 6;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 2;
        start_x = unit_x - 2;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y - 1;
        start_x = unit_x - 3;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y;
        start_x = unit_x - 4;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 1;
        start_x = unit_x - 5;
        row_len = 7;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 2;
        start_x = unit_x - 5;
        row_len = 6;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 3;
        start_x = unit_x - 4;
        row_len = 4;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);

        y = unit_y + 4;
        start_x = unit_x - 3;
        row_len = 2;
        start = start_x + grid.w*y;
        end = start + row_len;
        mem.set(u8, grid.data[start..end], value);
        return;
    }

}