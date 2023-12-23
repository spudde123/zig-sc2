/// Implements the necessary things to
/// read and write sc2 protobuf
/// messages.
const std = @import("std");
const mem = std.mem;

const WireType = enum(u8) {
    varint = 0,
    _64bit = 1,
    length_delim = 2,
    start_group = 3,
    end_group = 4,
    _32bit = 5,
    _,
};

const ParseError = error{
    Overflow,
    EndOfStream,
    OutOfMemory,
};

const WriteError = error{
    EndOfBuffer,
};

const ProtoHeader = struct {
    wire_type: WireType,
    field_number: u8,
};

pub const ProtoReader = struct {
    bytes_read: usize = 0,
    bytes: []u8,

    fn decodeProtoHeader(self: *ProtoReader) !ProtoHeader {
        var header = try self.decodeUInt64();

        return ProtoHeader{
            .wire_type = @as(WireType, @enumFromInt(header & 7)),
            .field_number = @as(u8, @truncate(header >> 3)),
        };
    }

    /// Use an arena allocator and free all allocations afterwards when the results aren't needed anymore
    pub fn decodeStruct(self: *ProtoReader, size: usize, comptime T: type, allocator: mem.Allocator) ParseError!T {
        var res = T{};

        const field_nums_tuple = @field(T, "field_nums");
        // Make a tuple to store arraylists for the fields
        // where we need to generate slices of unknown length.
        // Using a zero bit type for the other tuple members
        // seemed to cause a crash during compilation?
        // Seems fixed in 10.1
        const TupleType = comptime t: {
            var tuple_types: [field_nums_tuple.len]type = undefined;
            inline for (field_nums_tuple, 0..) |field_info, i| {
                const field_name = field_info[0];
                const info = @typeInfo(@TypeOf(@field(res, field_name)));
                const child_type = info.Optional.child;
                const child_info = @typeInfo(child_type);
                tuple_types[i] = switch (child_info) {
                    .Pointer => |ptr| std.ArrayListUnmanaged(ptr.child),
                    else => void,
                };
            }
            break :t std.meta.Tuple(&tuple_types);
        };

        var list_tuple: TupleType = comptime l: {
            var tuple: TupleType = undefined;
            inline for (field_nums_tuple, 0..) |field_info, i| {
                const field_name = field_info[0];
                const info = @typeInfo(@TypeOf(@field(res, field_name)));
                const child_type = info.Optional.child;
                const child_info = @typeInfo(child_type);
                tuple[i] = switch (child_info) {
                    .Pointer => |ptr| std.ArrayListUnmanaged(ptr.child){},
                    else => {},
                };
            }
            break :l tuple;
        };

        var start: usize = self.bytes_read;

        while (self.bytes_read - start < size) {
            const header = try self.decodeProtoHeader();

            var recognized_field = false;
            inline for (field_nums_tuple, 0..) |field_info, i| {
                const field_name = field_info[0];
                const field_num = field_info[1];

                if (header.field_number == field_num) {
                    recognized_field = true;
                    var obj_field = &@field(res, field_name);
                    const info = @typeInfo(@TypeOf(obj_field.*));
                    const child_type = info.Optional.child;
                    const child_info = @typeInfo(child_type);

                    switch (child_info) {
                        .Struct => {
                            const struct_encoding_size = try self.decodeUInt64();
                            obj_field.* = try self.decodeStruct(struct_encoding_size, child_type, allocator);
                        },
                        .Pointer => |ptr| {
                            if (ptr.child == u8) {
                                obj_field.* = try self.decodeBytes(allocator);
                            } else {
                                switch (ptr.child) {
                                    []const u8 => {
                                        var string = try self.decodeBytes(allocator);
                                        try list_tuple[i].append(allocator, string);
                                    },
                                    u32, u64 => {
                                        const int_to_add = @as(ptr.child, @intCast(try self.decodeUInt64()));
                                        try list_tuple[i].append(allocator, int_to_add);
                                    },
                                    i32, i64 => {
                                        const int_to_add = @as(ptr.child, @intCast(try self.decodeInt64()));
                                        try list_tuple[i].append(allocator, int_to_add);
                                    },
                                    else => {
                                        const element_info = @typeInfo(ptr.child);
                                        switch (element_info) {
                                            .Struct => {
                                                const struct_encoding_size = try self.decodeUInt64();
                                                const struct_to_add = try self.decodeStruct(struct_encoding_size, ptr.child, allocator);
                                                try list_tuple[i].append(allocator, struct_to_add);
                                            },
                                            .Enum => {
                                                const enum_int = try self.decodeUInt64();
                                                try list_tuple[i].append(allocator, @as(ptr.child, @enumFromInt(enum_int)));
                                            },
                                            else => unreachable,
                                        }
                                    },
                                }
                                obj_field.* = list_tuple[i].items;
                            }
                        },
                        .Int => |int| {
                            if (int.signedness == .unsigned) {
                                obj_field.* = @as(child_type, @intCast(try self.decodeUInt64()));
                            } else {
                                obj_field.* = @as(child_type, @intCast(try self.decodeInt64()));
                            }
                        },
                        .Float => |float| {
                            if (float.bits == 32) {
                                obj_field.* = try self.decodeFloat();
                            } else unreachable;
                        },
                        .Bool => {
                            const num = try self.decodeUInt64();
                            obj_field.* = num > 0;
                        },
                        .Void => {
                            // This only comes up when a message has an empty embedded message
                            // so we move forward by reading the zero size
                            _ = try self.decodeUInt64();
                            obj_field.* = {};
                        },
                        .Enum => {
                            const enum_int = try self.decodeUInt64();
                            obj_field.* = @as(child_type, @enumFromInt(enum_int));
                        },
                        else => unreachable,
                    }
                }
            }

            // Skip unrecognized fields
            if (!recognized_field) {
                //const type_name = @typeName(T);
                //std.log.debug("Found unknown field in {s}\n", .{type_name});
                //std.log.debug("field_num: {d}, type: {d}\n", .{header.field_number, header.wire_type});
                switch (header.wire_type) {
                    .varint => {
                        _ = try self.decodeUInt64();
                    },
                    ._32bit => {
                        self.bytes_read += 4;
                    },
                    ._64bit => {
                        self.bytes_read += 8;
                    },
                    .length_delim => {
                        const skip_len = try self.decodeUInt64();
                        self.bytes_read += skip_len;
                    },
                    else => unreachable,
                }
            }
        }

        return res;
    }

    fn decodeUInt64(self: *ProtoReader) ParseError!u64 {
        var value: u64 = 0;

        for (self.bytes[self.bytes_read..], 0..) |byte, i| {
            if (i >= 10) {
                return error.Overflow;
            }

            value += @as(u64, @intCast(0x7F & byte)) << (7 * @as(u6, @intCast(i)));
            // If msb is 0 we've reached the last byte
            if (byte & 0x80 == 0) {
                self.bytes_read += i + 1;
                return value;
            }
        }

        return error.EndOfStream;
    }

    fn decodeInt64(self: *ProtoReader) ParseError!i64 {
        return @as(i64, @bitCast(try self.decodeUInt64()));
    }

    fn decodeBytes(self: *ProtoReader, allocator: mem.Allocator) ![]u8 {
        const num_of_bytes = try self.decodeUInt64();
        var data = try allocator.dupe(u8, self.bytes[self.bytes_read..(self.bytes_read + num_of_bytes)]);
        self.bytes_read += num_of_bytes;

        return data;
    }

    fn decodeFloat(self: *ProtoReader) ParseError!f32 {
        const float_bits = mem.readIntSliceLittle(u32, self.bytes[self.bytes_read..(self.bytes_read + 4)]);
        self.bytes_read += 4;
        return @as(f32, @bitCast(float_bits));
    }
};

pub const ProtoWriter = struct {
    buffer: []u8,
    cursor: usize = 0,

    pub fn encodeBaseStruct(self: *ProtoWriter, s: anytype) []u8 {
        self.cursor = 0;
        const varint_byte_length = self.encodeElementStruct(s);
        const total_size = self.cursor;
        return self.buffer[varint_byte_length..total_size];
    }

    fn encodeProtoHeader(self: *ProtoWriter, header: ProtoHeader) void {
        var num = @as(u64, header.field_number) << 3;
        num += @intFromEnum(header.wire_type);
        self.encodeUInt64(num);
    }

    // Returns the number of bytes the preceding varint takes
    // so encodeBaseStruct can use it
    fn encodeElementStruct(self: *ProtoWriter, s: anytype) usize {

        // Leave 1 space for varint size by default
        self.cursor += 1;

        const content_start: usize = self.cursor;
        const field_nums_tuple = @field(@TypeOf(s), "field_nums");

        inline for (field_nums_tuple) |field_info| {
            const field_name = field_info[0];
            const field_num = field_info[1];
            const obj_field = @field(s, field_name);

            if (obj_field) |data| {
                const info = @typeInfo(@TypeOf(data));
                switch (info) {
                    .Struct => {
                        const field_header = ProtoHeader{ .wire_type = .length_delim, .field_number = field_num };
                        self.encodeProtoHeader(field_header);
                        _ = self.encodeElementStruct(data);
                    },
                    .Pointer => |ptr| {
                        if (ptr.child == u8) {
                            const field_header = ProtoHeader{ .wire_type = .length_delim, .field_number = field_num };

                            self.encodeProtoHeader(field_header);
                            self.encodeBytes(data);
                        } else if (ptr.child == []const u8) {
                            const field_header = ProtoHeader{ .wire_type = .length_delim, .field_number = field_num };

                            for (data) |string| {
                                self.encodeProtoHeader(field_header);
                                self.encodeBytes(string);
                            }
                        } else {
                            const child_info = @typeInfo(ptr.child);
                            switch (child_info) {
                                .Struct => {
                                    const field_header = ProtoHeader{ .wire_type = .length_delim, .field_number = field_num };

                                    for (data) |d| {
                                        self.encodeProtoHeader(field_header);
                                        _ = self.encodeElementStruct(d);
                                    }
                                },
                                .Int => |int| {
                                    const field_header = ProtoHeader{ .wire_type = .varint, .field_number = field_num };

                                    for (data) |integer_val| {
                                        self.encodeProtoHeader(field_header);
                                        if (int.signedness == .unsigned) {
                                            self.encodeUInt64(@as(u64, integer_val));
                                        } else {
                                            self.encodeInt64(@as(i64, integer_val));
                                        }
                                    }
                                },
                                else => unreachable,
                            }
                        }
                    },
                    .Int => |int| {
                        const field_header = ProtoHeader{ .wire_type = .varint, .field_number = field_num };
                        self.encodeProtoHeader(field_header);

                        if (int.signedness == .unsigned) {
                            self.encodeUInt64(@as(u64, data));
                        } else {
                            self.encodeInt64(@as(i64, data));
                        }
                    },
                    .Float => |float| {
                        if (float.bits == 32) {
                            const field_header = ProtoHeader{ .wire_type = ._32bit, .field_number = field_num };
                            self.encodeProtoHeader(field_header);
                            self.encodeFloat(data);
                        } else unreachable;
                    },
                    .Bool => {
                        const field_header = ProtoHeader{ .wire_type = .varint, .field_number = field_num };
                        self.encodeProtoHeader(field_header);
                        self.encodeUInt64(@as(u64, @intFromBool(data)));
                    },
                    .Enum => {
                        const field_header = ProtoHeader{ .wire_type = .varint, .field_number = field_num };
                        self.encodeProtoHeader(field_header);
                        self.encodeUInt64(@as(u64, @intFromEnum(data)));
                    },
                    .Void => {
                        // This only comes up when the proto file has an empty embedded message
                        const field_header = ProtoHeader{ .wire_type = .length_delim, .field_number = field_num };
                        self.encodeProtoHeader(field_header);
                        self.encodeUInt64(0);
                    },
                    else => unreachable,
                }
            }
        }

        const struct_encoding_size = self.cursor - content_start;

        const varint_byte_length = varIntByteLength(@as(u64, struct_encoding_size));
        self.cursor = content_start - 1;

        if (varint_byte_length == 1) {
            self.encodeUInt64(@as(u64, struct_encoding_size));
        } else {
            mem.copyBackwards(u8, self.buffer[content_start - 1 + varint_byte_length ..], self.buffer[content_start..(content_start + struct_encoding_size)]);
            self.encodeUInt64(@as(u64, struct_encoding_size));
        }

        const total_size = varint_byte_length + struct_encoding_size;
        self.cursor = content_start - 1 + total_size;
        return varint_byte_length;
    }

    fn encodeUInt64(self: *ProtoWriter, data: u64) void {
        if (data == 0) {
            self.buffer[self.cursor] = 0;
            self.cursor += 1;
            return;
        }

        var i: usize = 0;
        var value = data;

        // MSB of all bytes before last to 1
        while (value > 0) : (i += 1) {
            self.buffer[self.cursor + i] = @as(u8, 0x80) + @as(u7, @truncate(value));
            value >>= 7;
        }

        // Set MSB of last byte to 0
        self.buffer[self.cursor + i - 1] &= 0x7F;
        self.cursor += i;
    }

    fn encodeInt64(self: *ProtoWriter, data: i64) void {
        self.encodeUInt64(@as(u64, @bitCast(data)));
    }

    fn encodeBytes(self: *ProtoWriter, bytes: []const u8) void {
        self.encodeUInt64(bytes.len);
        @memcpy(self.buffer[self.cursor..(self.cursor + bytes.len)], bytes);
        self.cursor += bytes.len;
    }

    fn encodeFloat(self: *ProtoWriter, data: f32) void {
        var result = self.buffer[self.cursor..(self.cursor + 4)];
        mem.writeIntSliceLittle(u32, result, @as(u32, @bitCast(data)));
        self.cursor += 4;
    }
};

fn varIntByteLength(data: u64) usize {
    if (data == 0) {
        return 1;
    }
    var i: usize = 0;
    var value = data;

    while (value > 0) : (i += 1) {
        value >>= 7;
    }
    return i;
}

test "protobuf_floats" {
    var buffer: [256]u8 = undefined;

    var data: f32 = 9.81;
    var writer = ProtoWriter{ .buffer = buffer[0..] };
    writer.encodeFloat(data);

    var reader = ProtoReader{ .bytes = buffer[0..writer.cursor] };
    var decoded_data = try reader.decodeFloat();

    try std.testing.expectEqual(data, decoded_data);
}

test "protobuf_bytes" {
    var buffer: [256]u8 = undefined;

    const comparison = [_]u8{ 0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67 };
    var writer = ProtoWriter{ .buffer = buffer[0..] };
    writer.encodeBytes("testing");
    try std.testing.expectEqualSlices(
        u8,
        comparison[0..],
        buffer[0..writer.cursor],
    );

    var reader = ProtoReader{ .bytes = buffer[0..] };

    var decoded = try reader.decodeBytes(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, decoded, comparison[1..]);
    try std.testing.expectEqual(reader.bytes_read, 8);
    std.testing.allocator.free(decoded);
}

test "protobuf_varint" {
    var buf0 = [_]u8{ 1, 0b10101100, 0b00000010, 0b10010110, 0b00000001, 26 };

    var reader = ProtoReader{ .bytes = buf0[0..] };
    var uint = try reader.decodeUInt64();
    try std.testing.expectEqual(uint, 1);

    uint = try reader.decodeUInt64();
    try std.testing.expectEqual(uint, 300);

    uint = try reader.decodeUInt64();
    try std.testing.expectEqual(uint, 150);

    var header = try reader.decodeProtoHeader();
    std.debug.print("Type: {d}, Field: {d}\n", .{ header.wire_type, header.field_number });

    var buf1: [1000]u8 = undefined;
    var buf2: [1000]u8 = undefined;

    var writer1 = ProtoWriter{ .buffer = buf1[0..] };
    var writer2 = ProtoWriter{ .buffer = buf2[0..] };

    writer1.encodeUInt64(std.math.maxInt(u64));
    writer2.encodeInt64(-1);

    try std.testing.expectEqualSlices(
        u8,
        buf1[0..writer1.cursor],
        buf2[0..writer2.cursor],
    );

    var buffer: [256]u8 = undefined;
    var writer3 = ProtoWriter{ .buffer = buffer[0..] };

    writer3.encodeUInt64(300);
    for (buffer[0..writer3.cursor]) |byte| {
        std.debug.print("{b} ", .{byte});
    }
    std.debug.print("\n", .{});
}

test "protobuf_struct" {
    var buf1: [2048]u8 = undefined;
    var writer = ProtoWriter{ .buffer = buf1[0..] };

    const Test1 = struct {
        pub const field_nums = .{
            .{ "a", 1 },
        };
        a: ?i32 = null,
    };

    const Test2 = struct {
        pub const field_nums = .{
            .{ "c", 3 },
        };
        c: ?Test1 = null,
    };

    var t1 = Test1{ .a = 150 };
    var t2 = Test2{ .c = t1 };

    const encoding = writer.encodeBaseStruct(t2);
    const comparison1 = [_]u8{ 0b00011010, 0b00000011, 0b00001000, 0b10010110, 0b00000001 };
    try std.testing.expectEqualSlices(u8, comparison1[0..], encoding);

    const Test3 = struct {
        pub const field_nums = .{
            .{ "a", 1 },
            .{ "b", 2 },
            .{ "c", 3 },
            .{ "d", 4 },
            .{ "e", 5 },
        };
        a: ?bool = null,
        b: ?f32 = null,
        c: ?i32 = null,
        d: ?u32 = null,
        e: ?[]const u8 = null,
    };

    const Test5 = struct {
        pub const field_nums = .{
            .{ "a", 1 },
            .{ "b", 2 },
        };
        a: ?u32 = null,
        b: ?f32 = null,
    };

    const TestEnum = enum(u8) {
        opt1,
        opt2,
    };

    const Test4 = struct {
        pub const field_nums = .{
            .{ "f", 1 },
            .{ "g", 2 },
            .{ "h", 3 },
            .{ "i", 4 },
            .{ "j", 5 },
            .{ "k", 6 },
            .{ "l", 7 },
            .{ "m", 8 },
            .{ "n", 9 },
        };
        f: ?f32 = null,
        g: ?[]const u8 = null,
        h: ?Test3 = null,
        i: ?u32 = null,
        j: ?[]Test5 = null,
        k: ?[][]const u8 = null,
        l: ?TestEnum = null,
        m: ?[]u64 = null,
        n: ?[]u8 = null,
    };

    var t3 = Test3{
        .a = true,
        .b = 4.5,
        .c = -1,
        .d = 32,
        .e = "testing",
    };

    var t5 = Test5{
        .a = 6,
        .b = 7.5,
    };

    var t5_array: [2]Test5 = .{ t5, t5 };

    var string_array = [_][]const u8{ "string1", "string2", "string3" };

    var tag_array = [_]u64{ 32, 66, 128, 256, 1000 };
    var bytes_array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var t4 = Test4{
        .f = 1.5,
        .g = "testing",
        .h = t3,
        .i = 4,
        .j = t5_array[0..],
        .k = string_array[0..],
        .l = .opt2,
        .m = tag_array[0..],
        .n = bytes_array[0..],
    };

    const res = writer.encodeBaseStruct(t4);

    for (res) |byte| {
        std.debug.print("{b} ", .{byte});
    }
    std.debug.print("\n", .{});

    var reader = ProtoReader{ .bytes = res[1..5] };
    var first_float = try reader.decodeFloat();
    std.debug.print("{d}\n", .{first_float});

    var reader2 = ProtoReader{ .bytes = res };

    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    const decoded_t4 = try reader2.decodeStruct(res.len, Test4, arena);
    //std.debug.print("{any}\n", .{decoded_t4});

    try std.testing.expectEqual(t4.f.?, decoded_t4.f.?);
    try std.testing.expectEqualSlices(u8, t4.g.?, decoded_t4.g.?);
    try std.testing.expectEqual(t4.j.?[1].a.?, decoded_t4.j.?[1].a.?);
    try std.testing.expectEqual(t4.h.?.a.?, decoded_t4.h.?.a.?);
    try std.testing.expectEqual(t4.h.?.c.?, decoded_t4.h.?.c.?);
    try std.testing.expectEqualSlices(u8, t4.h.?.e.?, decoded_t4.h.?.e.?);
    try std.testing.expectEqualSlices(u8, t4.k.?[0], decoded_t4.k.?[0]);
    std.debug.print("{s}\n", .{decoded_t4.k.?[0]});
    try std.testing.expectEqual(t4.l.?, decoded_t4.l.?);
    try std.testing.expectEqual(t4.m.?[3], decoded_t4.m.?[3]);
    try std.testing.expectEqualSlices(u8, t4.n.?, decoded_t4.n.?);
}
