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
    x: f32 = 0,
    y: f32 = 0,

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

    pub fn towards(self: Point2, other: Point2, distance: f32) Point2 {
        const d = self.distanceTo(other);
        if (d == 0) return self;
        
        return .{
            .x = self.x + (other.x - self.x) / d * distance,
            .y = self.y + (other.y - self.y) / d * distance, 
        };
    }

    pub fn length(self: Point2) f32 {
        return math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Point2) Point2 {
        const l = self.length();
        return .{
            .x = self.x / l,
            .y = self.y / l,
        };
    }

    pub fn add(self: Point2, other: Point2) Point2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn subtract(self: Point2, other: Point2) Point2 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    /// Angle in radians
    pub fn rotate(self: Point2, angle: f32) Point2 {
        const cos = math.cos(angle);
        const sin = math.sin(angle);
        return .{
            .x = cos * self.x - sin * self.y,
            .y = sin * self.x + cos * self.y,
        };
    }

    pub fn multiply(self: Point2, multiplier: f32) Point2 {
        return .{
            .x = self.x * multiplier,
            .y = self.y * multiplier,
        };
    }

    pub fn dot(self: Point2, other: Point2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn floor(self: Point2) Point2 {
        return .{
            .x = math.floor(self.x),
            .y = math.floor(self.y),
        };
    }

    pub fn ceil(self: Point2) Point2 {
        return .{
            .x = math.ceil(self.x),
            .y = math.ceil(self.y),
        };
    }

};

pub const Point3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn fromPoint2(p: Point2, z: f32) Point3 {
        return .{
            .x = p.x,
            .y = p.y,
            .z = z,
        };
    }
};

pub const Grid = struct {
    data: []u8,
    w: usize,
    h: usize,

    pub fn getValue(self: Grid, point: Point2) u8 {
        const x: usize = @floatToInt(usize, math.floor(point.x));
        const y: usize = @floatToInt(usize, math.floor(point.y));

        assert(x >= 0 and x < self.w);
        assert(y >= 0 and y < self.h);
        
        return self.data[x + y*self.w];
    }

    pub fn allEqual(self: Grid, indices: []usize, value: u8) bool {
        for (indices) |index| {
            if (self.data[index] != value) return false;
        }
        return true;
    }

    pub fn count(self: Grid, indices: []usize) u64 {
        var total: u64 = 0;
        for (indices) |index| {
            total += @as(u64, self.data[index]);
        }
        return total;
    }

    pub fn pointToIndex(self: Grid, point: Point2) usize {
        const x: usize = @floatToInt(usize, math.floor(point.x));
        const y: usize = @floatToInt(usize, math.floor(point.y));
        return x + y*self.w;
    }

    pub fn indexToPoint(self: Grid, index: usize) Point2 {
        const x = @intToFloat(f32, @mod(index, self.w));
        const y = @intToFloat(f32, @divFloor(index, self.w));
        return .{
            .x = x,
            .y = y,
        };
    }

};
