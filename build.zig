const std = @import("std");

const VERSION = "3.1.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    // Default build (32-bit)
    const exe = b.addExecutable(.{
        .name = "AndroidUtility",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    addWindowsLibraries(exe);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const win32_step = b.step("win32", "Build for Windows 32-bit");
    const win64_step = b.step("win64", "Build for Windows 64-bit");
    const all_step = b.step("all", "Build for all Windows targets");
    const release_step = b.step("release", "Build optimized releases for all targets");

    const exe32 = b.addExecutable(.{
        .name = std.fmt.allocPrint(b.allocator, "AndroidUtility-{s}-x86", .{VERSION}) catch "AndroidUtility-x86",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .gnu,
            }),
            .optimize = optimize,
        }),
    });
    addWindowsLibraries(exe32);

    // 64-bit build
    const exe64 = b.addExecutable(.{
        .name = std.fmt.allocPrint(b.allocator, "AndroidUtility-{s}-x64", .{VERSION}) catch "AndroidUtility-x64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            }),
            .optimize = optimize,
        }),
    });
    addWindowsLibraries(exe64);

    // Release builds (optimized)
    const exe32_release = b.addExecutable(.{
        .name = std.fmt.allocPrint(b.allocator, "AndroidUtility-{s}-x86", .{VERSION}) catch "AndroidUtility-x86",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .gnu,
            }),
            .optimize = .ReleaseSafe,
        }),
    });
    addWindowsLibraries(exe32_release);

    const exe64_release = b.addExecutable(.{
        .name = std.fmt.allocPrint(b.allocator, "AndroidUtility-{s}-x64", .{VERSION}) catch "AndroidUtility-x64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            }),
            .optimize = .ReleaseSafe,
        }),
    });
    addWindowsLibraries(exe64_release);

    const install32 = b.addInstallArtifact(exe32, .{});
    const install64 = b.addInstallArtifact(exe64, .{});
    const install32_release = b.addInstallArtifact(exe32_release, .{});
    const install64_release = b.addInstallArtifact(exe64_release, .{});

    win32_step.dependOn(&install32.step);
    win64_step.dependOn(&install64.step);
    all_step.dependOn(&install32.step);
    all_step.dependOn(&install64.step);
    release_step.dependOn(&install32_release.step);
    release_step.dependOn(&install64_release.step);
}

fn addWindowsLibraries(exe: *std.Build.Step.Compile) void {
    exe.linkSystemLibrary("advapi32");
    exe.linkSystemLibrary("urlmon");
    exe.linkSystemLibrary("shell32");
    exe.linkSystemLibrary("comdlg32");
    exe.linkSystemLibrary("ole32");
    exe.linkSystemLibrary("oleaut32");
    exe.linkSystemLibrary("user32");
}
