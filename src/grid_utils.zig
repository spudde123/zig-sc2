const std = @import("std");
const mem = std.mem;

const UnitId = @import("ids/unit_id.zig").UnitId;
const Unit = @import("units.zig").Unit;
const grids = @import("grids.zig");
const Grid = grids.Grid;
const Point2 = grids.Point2;

const buildings_2x2 = [_]UnitId{
    .SupplyDepot,
    .Pylon,
    .DarkShrine,
    .PhotonCannon,
    .ShieldBattery,
    .TechLab,
    .StarportTechLab,
    .FactoryTechLab,
    .BarracksTechLab,
    .Reactor,
    .StarportReactor,
    .FactoryReactor,
    .BarracksReactor,
    .MissileTurret,
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
    .RefineryRich
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

pub fn setBuildingToValue(grid: Grid, unit: Unit, value: u8) void {
    const index = grid.pointToIndex(unit.position);
    if (mem.indexOfScalar(UnitId, &buildings_2x2, unit.unit_type)) |_| {
        grid.data[index - 1] = value;
        grid.data[index] = value;
        grid.data[index - 1 + grid.w] = value;
        grid.data[index + grid.w] = value;
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
        // We do two loops of smaller rectangles
        // to get the right shape
        var y: usize = unit_y - 1;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 2 + grid.w*y;
            const end = unit_x + 3 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        y = unit_y - 2;
        while (y < unit_y + 3) : (y += 1) {
            const start = unit_x - 1 + grid.w*y;
            const end = unit_x + 2 + grid.w*y;
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
        grid.data[index - 1 + grid.w] = value;
        grid.data[index + grid.w] = value;
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
        // These have the corners cut off
        // We do two loops of smaller rectangles
        // to get the right shape
        var y: usize = unit_y - 2;
        while (y < unit_y + 2) : (y += 1) {
            const start = unit_x - 3 + grid.w*y;
            const end = unit_x + 3 + grid.w*y;
            mem.set(u8, grid.data[start..end], value);
        }
        y = unit_y - 3;
        while (y < unit_y + 3) : (y += 1) {
            const start = unit_x - 2 + grid.w*y;
            const end = unit_x + 2 + grid.w*y;
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