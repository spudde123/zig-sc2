const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

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
