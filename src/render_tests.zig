const std = @import("std");
const p = @import("sc2proto.zig");
const protobuf = @import("protobuf.zig");

test {
    _ = @import("replay_session.zig");
}

test "render interface uses upstream field numbers and round trips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buffer: [1024]u8 = undefined;
    const options = p.InterfaceOptions{ .render = .{
        .resolution = .{ .x = 640, .y = 480 },
        .minimap_resolution = .{ .x = 128, .y = 128 },
    } };
    const bytes = try protobuf.encode(&buffer, options);
    try std.testing.expectEqual(@as(u8, 0x22), bytes[0]); // field 4, length-delimited
    const decoded = try protobuf.decode(p.InterfaceOptions, bytes, arena.allocator());
    try std.testing.expectEqual(@as(?i32, 640), decoded.render.?.resolution.?.x);
    const request = p.Request{ .start_replay = .{ .options = options, .realtime = false, .observed_player_id = 0 } };
    const wire = try protobuf.encode(&buffer, request);
    const res = try protobuf.decode(p.Request, wire, arena.allocator());
    try std.testing.expectEqual(@as(?bool, false), res.start_replay.?.realtime);
    try std.testing.expectEqual(@as(?i32, 0), res.start_replay.?.observed_player_id);
}

test "independent wire fixture decodes RGB observation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Observation.render_data=7 -> ObservationRender.map=1 -> ImageData:
    // bits_per_pixel=24, Size2DI(1,1), data={0xff,0x00,0x7f}; game_loop=9.
    var fixture = [_]u8{ 0x3a, 0x0f, 0x0a, 0x0d, 0x08, 0x18, 0x12, 0x04, 0x08, 0x01, 0x10, 0x01, 0x1a, 0x03, 0xff, 0x00, 0x7f, 0x48, 0x40 };
    const obs = try protobuf.decode(p.Observation, &fixture, arena.allocator());
    try std.testing.expectEqual(@as(?u32, 64), obs.game_loop);
    const image = obs.render.?.map.?;
    try std.testing.expectEqual(@as(?i32, 24), image.bits_per_pixel);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0x00, 0x7f }, image.image.?);
    var empty = [_]u8{ 0x48, 0x00 };
    try std.testing.expect((try protobuf.decode(p.Observation, &empty, arena.allocator())).render == null);
}

test "observer camera request uses request 21 and camera action 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buffer: [1024]u8 = undefined;
    const actions = [_]p.ObserverAction{.{ .camera_move = .{ .world_pos = .{ .x = 32, .y = 64 } } }};
    const bytes = try protobuf.encode(&buffer, p.Request{ .observer_action = .{ .actions = &actions } });
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0x01 }, bytes[0..2]); // field 21
    const req = try protobuf.decode(p.Request, bytes, arena.allocator());
    try std.testing.expectEqual(@as(?f32, 32), req.observer_action.?.actions.?[0].camera_move.?.world_pos.?.x);
}
