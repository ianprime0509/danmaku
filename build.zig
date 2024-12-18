const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "danmaku",
        .root_source_file = b.path("src/danmaku.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.entry = .disabled;
    exe.linkLibC();
    exe.linkSystemLibrary("sdl3");
    exe.linkSystemLibrary("sdl3-image");
    b.installArtifact(exe);

    const exe_run = b.addRunArtifact(exe);
    if (b.args) |args| exe_run.addArgs(args);
    b.step("run", "Run").dependOn(&exe_run.step);
}
