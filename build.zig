const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_sc2_module = b.addModule("zig-sc2", .{
        .root_source_file = b.path("src/runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = zig_sc2_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // Add the option to run a dummy bot
    // and test if all the main base ramps exist
    const ladder_maps = [_][]const u8{
        "MagannathaAIE_v2",
        "UltraloveAIE_v2",
        "LeyLinesAIE_v3",
        "TorchesAIE_v4",
        "PylonAIE_v4",
        "PersephoneAIE_v4",
        "IncorporealAIE_v4",
    };
    const ramp_validator_module = b.createModule(.{
        .root_source_file = b.path("util/ramp_validator.zig"),
        .target = target,
        .optimize = optimize,
    });
    ramp_validator_module.addImport("zig-sc2", zig_sc2_module);

    const ramp_validator = b.addExecutable(.{
        .name = "ladder-ramp-validator",
        .root_module = ramp_validator_module,
    });

    const test_ladder_ramps_step = b.step("test-ladder-ramps", "Validate main-base ramp wall-off positions on the current ladder maps");
    var previous_validator_step: ?*std.Build.Step = null;
    for (ladder_maps, 0..) |map, index| {
        const game_port = b.fmt("{d}", .{5001 + index * 10});
        const run_validator = b.addRunArtifact(ramp_validator);
        run_validator.addArgs(&.{ "--Map", map, "--GamePort", game_port });
        if (previous_validator_step) |previous| {
            run_validator.step.dependOn(previous);
        }
        test_ladder_ramps_step.dependOn(&run_validator.step);
        previous_validator_step = &run_validator.step;
    }
}
