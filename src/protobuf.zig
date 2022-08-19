const std = @import("std");
const mem = std.mem;

pub const max_varint_length: usize = 10;
pub const float_length: usize = 4;
pub const header_length: usize = 1;

pub const WireType = enum(u8) {
    varint = 0,
    _64bit = 1,
    length_delim = 2,
    start_group = 3,
    end_group = 4,
    _32bit = 5,
    _
};

const ParseError = error{
    Overflow,
    EndOfStream,
    OutOfMemory,
};

const WriteError = error{
    EndOfBuffer,
};

pub fn ProtoField(comptime field_num: comptime_int,  comptime data_type: type) type {

    const info = @typeInfo(data_type);
    switch (info) {
        .Pointer => |ptr| {
            return struct {
                field_num: u8 = field_num,
                data: ?data_type = null,
                list: ?std.ArrayList(ptr.child) = null,
            };
        },
        else => {
            return struct {
                field_num: u8 = field_num,
                data: ?data_type = null,
            };
        }
    }
}

const ProtoHeader = struct {
    wire_type: WireType,
    field_number: u8,
};

pub const ProtoReader = struct {
    bytes_read: usize = 0,
    bytes: []u8,

    fn decodeProtoHeader(self: *ProtoReader) !ProtoHeader {
        var header = try self.decodeUInt64();

        return ProtoHeader {
            .wire_type = @intToEnum(WireType, header & 7),
            .field_number = @truncate(u8, header >> 3),
        };
    }


    /// Use an arena allocator and free all allocations afterwards when the results aren't needed anymore
    // @TODO: Need to skip stuff in the buffer we don't recognize
    pub fn decodeStruct(self: *ProtoReader, size: usize, comptime T: type, allocator: mem.Allocator) ParseError!T {
        var res = T{};

        var start: usize = self.bytes_read;

        while (self.bytes_read - start < size) {
            const header = try self.decodeProtoHeader();

            inline for (@typeInfo(T).Struct.fields) |field| {
                var obj_field = @field(res, field.name);
                
                const field_num = obj_field.field_num;

                if (header.field_number == field_num) {
                    //std.debug.print("{s}\n", .{field.name});
                    const data_info = @typeInfo(@TypeOf(obj_field.data));
                    const child_type = data_info.Optional.child;
                    const child_info = @typeInfo(child_type);

                    switch (child_info) {
                        .Struct => {
                            const struct_encoding_size = try self.decodeUInt64();
                            obj_field.data = try self.decodeStruct(struct_encoding_size, child_type, allocator);
                        },
                        .Pointer => |ptr| {
                            if (ptr.child == u8) {
                                obj_field.data = try self.decodeBytes(allocator);
                            } else {
                                if (obj_field.list == null) {
                                    obj_field.list = std.ArrayList(ptr.child).init(allocator);
                                }

                                switch(ptr.child) {
                                    []const u8 => {
                                        var string = try self.decodeBytes(allocator);
                                        try obj_field.list.?.append(string);
                                    },
                                    u32, u64 => {
                                        const int_to_add = @intCast(ptr.child, try self.decodeUInt64());
                                        try obj_field.list.?.append(int_to_add);
                                    },
                                    i32, i64 => {
                                        const int_to_add = @intCast(ptr.child, try self.decodeInt64());
                                        try obj_field.list.?.append(int_to_add);
                                    },
                                    else => {
                                        const element_info = @typeInfo(ptr.child);
                                        switch (element_info) {
                                            .Struct => {
                                                const struct_encoding_size = try self.decodeUInt64();
                                                const struct_to_add = try self.decodeStruct(struct_encoding_size, ptr.child, allocator);
                                                try obj_field.list.?.append(struct_to_add);
                                            },
                                            .Enum => {
                                                const enum_int = try self.decodeUInt64();
                                                try obj_field.list.?.append(@intToEnum(ptr.child, enum_int));
                                            },
                                            else => {
                                                
                                            }
                                        }
                                    }
                                }
                                obj_field.data = obj_field.list.?.items;
                            }
                        },
                        .Int => |int| {
                            if (int.signedness == .unsigned) {
                                obj_field.data = @intCast(child_type, try self.decodeUInt64());
                            } else {
                                obj_field.data = @intCast(child_type, try self.decodeInt64());
                            }
                        },
                        .Float => |float| {
                            if (float.bits == 32) {
                                obj_field.data = try self.decodeFloat();
                            }
                        },
                        .Bool => {
                            const num = try self.decodeUInt64();
                            obj_field.data = num > 0;
                        },
                        .Void => {
                            _ = try self.decodeUInt64();
                            obj_field.data = {};
                        },
                        .Enum => {
                            const enum_int = try self.decodeUInt64();
                            obj_field.data = @intToEnum(child_type, @truncate(u8, enum_int));
                        },
                        else => {
                        }
                    }

                    @field(res, field.name) = obj_field;
                }
            }
        }

        return res;
    } 
    
    fn decodeUInt64(self: *ProtoReader) ParseError!u64 {
        var value: u64 = 0;

        for (self.bytes[self.bytes_read..]) |byte, i| {
            if (i >= 10) {
                return error.Overflow;
            }

            value += @intCast(u64, 0x7F & byte) << (7 * @intCast(u6, i));
            if (byte & 0x80 == 0) {
                self.bytes_read += i + 1;
                return value;
            }
        }

        return error.EndOfStream;
    }

    fn decodeInt64(self: *ProtoReader) ParseError!i64 {
        return @bitCast(i64, try self.decodeUInt64());
    }

    fn decodeBytes(self: *ProtoReader, allocator: mem.Allocator) ![]u8 {
        const starting_byte: usize = self.bytes_read;
        const num_of_bytes = try self.decodeUInt64();
        const header_len = self.bytes_read - starting_byte;

        var data = try allocator.alloc(u8, num_of_bytes);

        mem.copy(u8, data, self.bytes[starting_byte + header_len .. (starting_byte + header_len + num_of_bytes)]);
        self.bytes_read += num_of_bytes;

        return data;
    }

    fn decodeFloat(self: *ProtoReader) ParseError!f32 {
        const float_bits = mem.readIntSliceLittle(u32, self.bytes[self.bytes_read .. (self.bytes_read + 4)]);
        self.bytes_read += 4;
        return @bitCast(f32, float_bits);
    }
};

pub const ProtoWriter = struct {

    buffer: []u8,
    cursor: usize = 0,

    pub fn encodeBaseStruct(self: *ProtoWriter, s: anytype) []u8 {
        const encoding_size = self.encodeElementStruct(s);
        self.cursor = 0;
        const varint_byte_length = varIntByteLength(@as(u64, encoding_size));
        return self.buffer[varint_byte_length .. encoding_size];   
    }

    fn encodeProtoHeader(self: *ProtoWriter, header: ProtoHeader) usize {
        var num = @as(u64, header.field_number) << 3;
        num += @enumToInt(header.wire_type);
        return self.encodeUInt64(num);
    }

    fn encodeElementStruct(self: *ProtoWriter, s: anytype) usize {
        
        // Leave 1 space for varint size by default
        self.cursor += 1;

        const content_start: usize = self.cursor;
        
        inline for (@typeInfo(@TypeOf(s)).Struct.fields) |field| {
            const obj_field = @field(s, field.name);
            const field_num = @field(obj_field, "field_num");
            const optional_data = @field(obj_field, "data");

            if (optional_data) |data| {
                
                const info = @typeInfo(@TypeOf(data));
                switch (info) {
                    .Struct => {
                        const field_header = ProtoHeader{.wire_type = .length_delim, .field_number = field_num};
                        self.cursor += self.encodeProtoHeader(field_header);
                        self.cursor += self.encodeElementStruct(data);
                    },
                    .Pointer => |ptr| {
                        const field_header = ProtoHeader{.wire_type = .length_delim, .field_number = field_num};
                        if (ptr.child == u8) {
                            self.cursor += self.encodeProtoHeader(field_header);
                            self.cursor += self.encodeBytes(data);
                        } else if (ptr.child == []const u8) {
                            for (data) |string| {
                                self.cursor += self.encodeProtoHeader(field_header);
                                self.cursor += self.encodeBytes(string);
                            }
                        } else {
                            const child_info = @typeInfo(ptr.child);
                            if (child_info == .Struct) {
                                for (data) |d| {
                                    self.cursor += self.encodeProtoHeader(field_header);
                                    self.cursor += self.encodeElementStruct(d);
                                }
                            }
                        }
                    },
                    .Int => |int| {
                        
                        const field_header = ProtoHeader{.wire_type = .varint, .field_number = field_num};
                        self.cursor += self.encodeProtoHeader(field_header);

                        if (int.signedness == .unsigned) {
                            self.cursor += self.encodeUInt64(@as(u64, data));
                        } else {
                            self.cursor += self.encodeInt64(@as(i64, data));
                        }
                    },
                    .Float => |float| {
                        if (float.bits == 32) {
                            const field_header = ProtoHeader{.wire_type = ._32bit, .field_number = field_num};
                            self.cursor += self.encodeProtoHeader(field_header);
                            self.cursor += self.encodeFloat(data);
                        }
                    },
                    .Bool => {
                        const field_header = ProtoHeader{.wire_type = .varint, .field_number = field_num};
                        self.cursor += self.encodeProtoHeader(field_header);
                        self.cursor += self.encodeUInt64(@as(u64, @boolToInt(data)));
                    },
                    .Enum => {
                        const field_header = ProtoHeader{.wire_type = .varint, .field_number = field_num};
                        self.cursor += self.encodeProtoHeader(field_header);
                        self.cursor += self.encodeUInt64(@as(u64, @enumToInt(data)));
                    },
                    .Void => {
                        // This only comes up when the proto file has an empty embedded message
                        const field_header = ProtoHeader{.wire_type = .length_delim, .field_number = field_num};
                        self.cursor += self.encodeProtoHeader(field_header);
                        self.cursor += self.encodeUInt64(0);
                    },
                    else => {
                        std.debug.print("{d}\n", .{data});
                    }
                }
            }
        }

        const struct_encoding_size = self.cursor - content_start;

        const varint_byte_length = varIntByteLength(@as(u64, struct_encoding_size));
        self.cursor = content_start - 1;
        
        if (varint_byte_length == 1) {
            _ = self.encodeUInt64(@as(u64, struct_encoding_size));
        } else {
            mem.copyBackwards(u8, self.buffer[content_start - 1 + varint_byte_length ..], self.buffer[content_start .. (content_start + struct_encoding_size)]);
            _ = self.encodeUInt64(@as(u64, struct_encoding_size));
        }

        const total_size = varint_byte_length + struct_encoding_size;
        self.cursor = content_start - 1;

        return total_size;
    }
    
    fn encodeUInt64(self: *ProtoWriter, data: u64) usize {
        if (data == 0) {
            self.buffer[self.cursor] = 0;
            return 1;
        }

        var i: usize = 0;
        var value = data;

        while (value > 0) : (i += 1) {
            self.buffer[self.cursor + i] = @as(u8, 0x80) + @truncate(u7, value);
            value >>= 7;
        }

        self.buffer[self.cursor + i - 1] &= 0x7F;
        return i;
    }

    fn encodeInt64(self: *ProtoWriter, data: i64) usize {
        return self.encodeUInt64(@bitCast(u64, data));
    }

    fn encodeBytes(self: *ProtoWriter, bytes: []const u8) usize {
        const encoded_length = self.encodeUInt64(bytes.len);
        const copy_start = self.cursor + encoded_length;
        mem.copy(u8, self.buffer[copy_start .. (copy_start + bytes.len)], bytes);
        return encoded_length + bytes.len;
    }

    fn encodeFloat(self: *ProtoWriter, data: f32) usize {
        var result = self.buffer[self.cursor..(self.cursor + 4)];
        mem.writeIntSliceLittle(u32, result, @bitCast(u32, data));
        return 4;
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
    var writer = ProtoWriter{.buffer = buffer[0..]};
    const float_size = writer.encodeFloat(data);

    var reader = ProtoReader{.bytes = buffer[0..float_size]};
    var decoded_data = try reader.decodeFloat();

    try std.testing.expectEqual(data, decoded_data);
}

test "protobuf_bytes" {
    var buffer: [256]u8 = undefined;
    
    const comparison = [_]u8 {0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67};
    var writer = ProtoWriter{.buffer = buffer[0..]};
    const bytes_len = writer.encodeBytes("testing");
    try std.testing.expectEqualSlices(
        u8,
        comparison[0..],
        buffer[0..bytes_len],
    );
    
    var reader = ProtoReader{.bytes = buffer[0..]};

    var decoded = try reader.decodeBytes(std.testing.allocator);
    try std.testing.expectEqualSlices(
        u8,
        decoded,
        comparison[1..]
    );
    try std.testing.expectEqual(reader.bytes_read, 8);
    std.testing.allocator.free(decoded);
}

test "protobuf_varint" {

    var buf0 = [_]u8{1, 0b10101100, 0b00000010, 0b10010110, 0b00000001, 26};

    var reader = ProtoReader{.bytes = buf0[0..]};
    var uint = try reader.decodeUInt64();
    try std.testing.expectEqual(uint, 1);

    uint = try reader.decodeUInt64();
    try std.testing.expectEqual(uint, 300);

    uint = try reader.decodeUInt64();
    try std.testing.expectEqual(uint, 150);

    var header = try reader.decodeProtoHeader();
    std.debug.print("Type: {d}, Field: {d}\n", .{header.wire_type, header.field_number});

    var buf1: [1000]u8 = undefined;
    var buf2: [1000]u8 = undefined;

    var writer1 = ProtoWriter{.buffer = buf1[0..]};
    var writer2 = ProtoWriter{.buffer = buf2[0..]};

    const l1 = writer1.encodeUInt64(std.math.maxInt(u64));
    const l2 = writer2.encodeInt64(-1);

    try std.testing.expectEqualSlices(
        u8,
        buf1[0..l1],
        buf2[0..l2],
    );

    var buffer: [256]u8 = undefined;
    var writer3 = ProtoWriter{.buffer = buffer[0..]};

    const l3 = writer3.encodeUInt64(300);
    for (buffer[0..l3]) |byte| {
        std.debug.print("{b} ", .{byte});
    }
    std.debug.print("\n", .{});

}

test "protobuf_struct" {
    var buf1: [2048]u8 = undefined;
    var writer = ProtoWriter{.buffer = buf1[0..]};

    const Test1 = struct {
        a: ProtoField(1, i32) = .{},
    };

    const Test2 = struct {
        c: ProtoField(3, Test1) = .{},
    };

    var t1 = Test1{.a = .{.data = 150}};
    var t2 = Test2{.c = .{.data = t1}};

    const encoding = writer.encodeBaseStruct(t2);
    const comparison1 = [_]u8 {0b00011010, 0b00000011, 0b00001000, 0b10010110, 0b00000001};
    try std.testing.expectEqualSlices(
        u8,
        comparison1[0..],
        encoding
    );

    const Test3 = struct {
        a: ProtoField(1, bool) = .{},
        b: ProtoField(2, f32) = .{},
        c: ProtoField(3, i32) = .{},
        d: ProtoField(4, u32) = .{},
        e: ProtoField(5, []const u8) = .{},
    };

    const Test5 = struct {
        a: ProtoField(1, u32) = .{},
        b: ProtoField(2, f32) = .{},
    };

    const TestEnum = enum(u8) {
        opt1,
        opt2,
    };

    const Test4 = struct {
        f: ProtoField(1, f32) = .{},
        g: ProtoField(2, []const u8) = .{},
        h: ProtoField(3, Test3) = .{},
        i: ProtoField(4, u32) = .{},
        j: ProtoField(5, []Test5) = .{},
        k: ProtoField(6, [][]const u8) = .{},
        l: ProtoField(7, TestEnum) = .{},
    };

    var t3 = Test3{
        .a = .{.data = true},
        .b = .{.data = 4.5},
        .c = .{.data = -1},
        .d = .{.data = 32},
        .e = .{.data = "testing"},
    };

    var t5 = Test5{
        .a = .{.data = 6},
        .b = .{.data = 7.5},
    };

    var t5_array: [2]Test5 = .{t5, t5};

    var string_array = [_][]const u8{"string1", "string2", "string3"};

    var t4 = Test4{
        .f = .{.data = 1.5},
        .g = .{.data = "testing"},
        .h = .{.data = t3},
        .i = .{.data = 4},
        .j = .{.data = t5_array[0..]},
        .k = .{.data = string_array[0..]},
        .l = .{.data = .opt2},
    };

    const res = writer.encodeBaseStruct(t4);

    for (res) |byte| {
        std.debug.print("{b} ", .{byte});
    }
    std.debug.print("\n", .{});

    var reader = ProtoReader{.bytes = res[1..5]};
    var first_float = try reader.decodeFloat();
    std.debug.print("{d}\n", .{first_float});

    var reader2 = ProtoReader{.bytes = res};
    
    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    const decoded_t4 = try reader2.decodeStruct(res.len, Test4, arena);
    std.debug.print("{any}\n", .{decoded_t4});
    
    try std.testing.expectEqual(t4.f.data.?, decoded_t4.f.data.?);
    try std.testing.expectEqualSlices(u8, t4.g.data.?, decoded_t4.g.data.?);
    try std.testing.expectEqual(t4.j.data.?[1].a.data.?, decoded_t4.j.data.?[1].a.data.?);
    try std.testing.expectEqual(t4.h.data.?.a.data.?, decoded_t4.h.data.?.a.data.?);
    try std.testing.expectEqual(t4.h.data.?.c.data.?, decoded_t4.h.data.?.c.data.?);
    try std.testing.expectEqualSlices(u8, t4.h.data.?.e.data.?, decoded_t4.h.data.?.e.data.?);
    try std.testing.expectEqualSlices(u8, t4.k.data.?[0], decoded_t4.k.data.?[0]);
    std.debug.print("{s}\n", .{decoded_t4.k.data.?[0]});
    try std.testing.expectEqual(t4.l.data.?, decoded_t4.l.data.?);

}