const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const testa = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Translate the C shim header into a Zig module (replaces hand-written externs).
    const node_c = b.addTranslateC(.{
        .root_source_file = b.path("src/node_embed.h"),
        .target = target,
        .optimize = optimize,
    });
    testa.addImport("node_c", node_c.createModule());

    // Vendored esbuild (vendor/esbuild). Build its public pkg/api into a static
    // c-archive and link it directly — no subprocess, no Node, for bundling.
    const esbuild = b.addSystemCommand(&.{ "go", "build", "-buildmode=c-archive" });
    esbuild.setCwd(b.path("vendor/esbuild"));
    esbuild.setEnvironmentVariable("CGO_ENABLED", "1");
    esbuild.addArg("-o");
    const esbuild_a = esbuild.addOutputFileArg("libesbuild.a");
    esbuild.addArg("./cabi");
    testa.addObjectFile(esbuild_a);

    const esbuild_c = b.addTranslateC(.{
        .root_source_file = b.path("src/esbuild.h"),
        .target = target,
        .optimize = optimize,
    });
    testa.addImport("esbuild_c", esbuild_c.createModule());

    // Vendored libnode (node 26.3.0). Pick the dir matching the target triple.
    const t = target.result;
    const libnode_dir = b.fmt("vendor/libnode/{s}-{s}", .{
        @tagName(t.cpu.arch),
        switch (t.os.tag) {
            .linux => "linux",
            .macos => "macos",
            .windows => "windows",
            else => @panic("no vendored libnode for this OS"),
        },
    });
    testa.addLibraryPath(b.path(libnode_dir));
    testa.linkSystemLibrary("node", .{});

    // Zig's clang only speaks libc++; on Linux libnode needs libstdc++. Compile
    // the shim with the system g++ (Apple clang on macOS) and link the object.
    const shim = b.addSystemCommand(&.{ "g++", "-std=c++20", "-fPIC", "-c" });
    shim.addArg("-Ivendor/libnode/include/node");
    shim.addFileArg(b.path("src/node_embed.cpp"));
    shim.addArg("-o");
    const shim_obj = shim.addOutputFileArg("node_embed.o");
    testa.addObjectFile(shim_obj);

    switch (t.os.tag) {
        .linux => {
            // libnode + the shim are libstdc++; link the real GNU libstdc++ by path.
            // (Zig remaps linkSystemLibrary("stdc++") to its own libc++, so we can't use it.)
            const libstdcxx = std.mem.trim(u8, b.run(&.{ "g++", "-print-file-name=libstdc++.so" }), " \r\n\t");
            testa.addObjectFile(.{ .cwd_relative = libstdcxx });
            // libgcc_s provides the C++ exception unwinder (_Unwind_Resume).
            const libgcc_s = std.mem.trim(u8, b.run(&.{ "g++", "-print-file-name=libgcc_s.so.1" }), " \r\n\t");
            testa.addObjectFile(.{ .cwd_relative = libgcc_s });
        },
        // macOS libnode and the Apple-clang shim both use the system libc++.
        .macos => testa.linkSystemLibrary("c++", .{}),
        else => @panic("no C++ runtime configured for this OS"),
    }

    // So the built exe finds libnode.so/.dylib next to itself at runtime.
    testa.addRPath(b.path(libnode_dir));

    const exe = b.addExecutable(.{
        .name = "testa",
        .root_module = testa,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
