const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zig80",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (@hasDecl(std.Build.Step.Run, "addPassthruArgs")) {
        run.addPassthruArgs();
    } else {
        if (b.args) |args| run.addArgs(args);
    }
    b.step("run", "Run zig80").dependOn(&run.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_run = b.addRunArtifact(tests);
    // These suites assemble files at run time. Include them in the run cache key
    // so an ASM-only edit cannot reuse an older successful test result.
    for ([_][]const u8{
        "examples/pc8001/loader/stage0.asm",            "examples/pc8001/loader/stage1.asm",    "examples/pc8001/loader/mini_stage0.asm",
        "examples/pc8001/loader/layout.inc",            "examples/pc8001/loader/uart.inc",      "examples/pc8001/loader/crc.inc",
        "examples/pc8001/hello.asm",                    "examples/pc8001/memory_test.asm",      "examples/pc8001/return_to_loader.asm",
        "examples/pc8001/serial_echo.asm",              "examples/pc8001/serial/common.inc",    "examples/pc8001/serial/tx_test.asm",
        "examples/pc8001/serial/rx_test.asm",           "examples/pc8001/serial/echo_test.asm", "examples/pc8001/serial/pattern_test.asm",
        "examples/pc8001/serial/binary_ready_test.asm", "examples/pc8001/orbital_rings.asm",
    }) |path| test_run.addFileInput(b.path(path));
    b.step("test", "Run all tests").dependOn(&test_run.step);

    const loader_mock = b.addExecutable(.{
        .name = "zig80-loader-mock",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/loader_mock.zig"), .target = target, .optimize = optimize, .link_libc = true }),
    });
    loader_mock.root_module.addIncludePath(b.path("hardware/pico2-pc8001/firmware"));
    loader_mock.root_module.addCSourceFile(.{ .file = b.path("hardware/pico2-pc8001/firmware/bridge.c"), .flags = &.{"-std=c11"} });
    loader_mock.root_module.addCSourceFile(.{ .file = b.path("hardware/pico2-pc8001/tests/loader_bridge.c"), .flags = &.{"-std=c11"} });
    b.step("loader-mock", "Build native C bridge + existing Z80 loader integration fixture (no GPIO)").dependOn(&b.addInstallArtifact(loader_mock, .{}).step);

    const differential = b.addExecutable(.{
        .name = "zig80-differential",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/differential.zig"), .target = target, .optimize = optimize }),
    });
    const differential_run = b.addRunArtifact(differential);
    if (@hasDecl(std.Build.Step.Run, "addPassthruArgs")) differential_run.addPassthruArgs() else if (b.args) |args| differential_run.addArgs(args);
    b.step("differential", "Compare external SingleStepTests JSON vectors").dependOn(&differential_run.step);
    const coverage = b.addExecutable(.{
        .name = "zig80-coverage",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/coverage.zig"), .target = target, .optimize = optimize }),
    });
    b.step("coverage", "Print machine-generated CPU coverage table").dependOn(&b.addRunArtifact(coverage).step);
}
