const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const check = b.step("check", "Check compiler errors");
    const fmt = b.step("fmt", "Formats files in src");
    const fmt_check = b.step("fmt-check", "Formats files in src");

    const exe = b.addExecutable(.{
        .name = "sicvm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("readline");

    const is_exe_step = addCompiledFile(b, exe, "instruction_set", "tools/is_gen.zig", "tools/instruction_set.zig").?;
    _ = addCompiledFile(b, exe, "result", null, "tools/result.zig");
    _ = addCompiledFile(b, exe, "ring_buffer", null, "tools/ring_buffer.zig");
    _ = addCompiledFile(b, exe, "helper", null, "tools/helper.zig");

    const check_comp = try b.allocator.create(std.Build.Step.Compile);
    check_comp.* = exe.*;

    const paths = &.{"src/"};
    const fmt_step = std.Build.Step.Fmt.create(b, .{
        .check = false,
        .paths = paths,
    });

    const fmt_check_step = std.Build.Step.Fmt.create(b, .{
        .check = true,
        .paths = paths,
    });

    fmt.dependOn(&fmt_step.step);

    fmt_check.dependOn((&fmt_check_step.step));

    check.dependOn(&check_comp.step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_files = .{
        "src/machine/machine.zig",
        "src/main.zig",
        "src/machine/device.zig",
        "src/machine/obj_reader.zig",
        "tools/helper.zig",
        "src/compiler/lexer.zig",
    };

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&is_exe_step.step);

    inline for (test_files) |file| {
        const exe_unit_tests = b.addTest(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });

        exe_unit_tests.root_module.addAnonymousImport("instruction_set", .{
            .root_source_file = b.path("tools/instruction_set.zig"),
        });
        _ = addCompiledFile(b, exe_unit_tests, "result", null, "tools/result.zig");
        _ = addCompiledFile(b, exe_unit_tests, "ring_buffer", null, "tools/ring_buffer.zig");
        _ = addCompiledFile(b, exe_unit_tests, "helper", null, "tools/helper.zig");

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        // Similar to creating the run step earlier, this exposes a `test` step to
        // the `zig build --help` menu, providing a way for the user to request
        // running the unit tests.
        // test_step.dependOn(&run_lib_unit_tests.step);
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}

fn addCompiledFile(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8, generator_path: ?[]const u8, generated_file_path: []const u8) ?*std.Build.Step.Run {
    if (generator_path == null) {
        exe.root_module.addAnonymousImport(name, .{
            .root_source_file = b.path(generated_file_path),
        });
        return null;
    }

    const is_exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(generator_path.?),
        .target = b.host,
    });
    const is_exe_step = b.addRunArtifact(is_exe);
    exe.step.dependOn(&is_exe_step.step);
    exe.root_module.addAnonymousImport(name, .{
        .root_source_file = b.path(generated_file_path),
    });

    return is_exe_step;
}
