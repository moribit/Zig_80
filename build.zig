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
    b.step("test", "Run all tests").dependOn(&b.addRunArtifact(tests).step);

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
