const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cli = b.option(bool, "cli", "build CLI emulator") orelse true;

    const uxn = b.addModule("uxn", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/uxn.zig"),
    });

    if (cli) {
        const exe = b.addExecutable(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .name = "uxn-cli",
        });
        exe.root_module.addImport("uxn", uxn);
        b.installArtifact(exe);
    }

    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("uxn", uxn);
    const tests_run = b.addRunArtifact(tests);

    const tests_step = b.step("test", "run the tests");
    tests_step.dependOn(&tests_run.step);
}
