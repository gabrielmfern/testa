const std = @import("std");
const c = @import("node_c");
const esb = @import("esbuild_c");

var passed_tests: u32 = 0;
var failed_tests: u32 = 0;
var io: std.Io = undefined;

// expect(actual).toBe(expected): strict identity via v8 SameValue (Object.is).
// `actual` rides along as the function's bound data.
fn toBeCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const actual = c.v8_function_callback_info_data(info);
    defer c.v8_local_value_free(actual);
    const expected = c.v8_function_callback_info_get(info, 0);
    defer c.v8_local_value_free(expected);
    if (c.v8_value_same_value(actual, expected)) return;

    const a = c.v8_value_to_utf8(isolate, actual);
    defer c.v8_utf8_free(a);
    const e = c.v8_value_to_utf8(isolate, expected);
    defer c.v8_utf8_free(e);
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrintZ(
        &buf,
        "expected {s} but got {s}",
        .{ std.mem.span(
            e,
        ), std.mem.span(a) },
    ) catch "assertion failed";
    c.v8_isolate_throw_error(isolate, msg);
}

// expect(actual) -> { toBe } with `actual` bound as the toBe closure's data.
fn expectCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);
    defer c.v8_local_context_free(ctx);
    const actual = c.v8_function_callback_info_get(info, 0);
    defer c.v8_local_value_free(actual);

    const obj = c.v8_object_new(isolate);
    defer c.v8_local_value_free(obj);
    const to_be = c.v8_function_new(ctx, &toBeCallback, actual);
    defer c.v8_local_value_free(to_be);
    c.v8_object_set(ctx, obj, "toBe", to_be);
    c.v8_function_callback_info_set_return_value(info, obj);
}

// test(name, closure): run it now, time it, report one plain-text line.
fn testCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);
    defer c.v8_local_context_free(ctx);

    const name_val = c.v8_function_callback_info_get(info, 0);
    defer c.v8_local_value_free(name_val);
    const closure = c.v8_function_callback_info_get(info, 1);
    defer c.v8_local_value_free(closure);
    const recv = c.v8_undefined(isolate);
    defer c.v8_local_value_free(recv);

    const name = c.v8_value_to_utf8(isolate, name_val);
    defer c.v8_utf8_free(name);

    const tc = c.v8_try_catch_new(isolate);
    defer c.v8_try_catch_free(tc);

    const start = std.Io.Timestamp.now(io, .awake);
    const result = c.v8_function_call(ctx, closure, recv, 0, null);
    const duration = start.untilNow(io, .awake);
    if (result != null) c.v8_local_value_free(result);

    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    if (c.v8_try_catch_has_caught(tc)) {
        failed_tests += 1;
        const exc = c.v8_try_catch_exception(tc);
        defer c.v8_local_value_free(exc);
        const emsg = c.v8_value_to_utf8(isolate, exc);
        stderr.interface.print(
            "not ok {s} ({f})\n  {s}\n",
            .{ std.mem.span(name), duration, std.mem.span(emsg) },
        ) catch {};
    } else {
        passed_tests += 1;
        stderr.interface.print(
            "ok {s} ({f})\n",
            .{ std.mem.span(name), duration },
        ) catch {};
    }
    stderr.interface.flush() catch {};
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*c]u8, args.len);
    argv[0] = @constCast(args[0].ptr);
    for (args[1..], 0..) |a, j| argv[1 + j] = @constCast(a.ptr);
    const argc: c_int = @intCast(argv.len);

    const flags = c.NODE_INIT_NO_INITIALIZE_V8 | c.NODE_INIT_NO_INITIALIZE_NODE_V8_PLATFORM;
    const result = c.node_initialize_once_per_process(argc, argv.ptr, flags) orelse
        return error.FailedToNodeInit;
    defer c.node_teardown_once_per_process();
    defer c.node_init_result_free(result);

    var i: c_int = 0;
    while (i < c.node_init_result_error_count(result)) : (i += 1) {
        std.debug.print("{s}: {s}\n", .{ args[0], c.node_init_result_error_at(result, i) });
    }
    if (c.node_init_result_early_return(result)) {
        std.process.exit(@intCast(c.node_init_result_exit_code(result)));
    }

    const platform = c.node_multi_isolate_platform_create(4) orelse return error.Platform;
    defer c.node_multi_isolate_platform_free(platform);
    c.v8_initialize_platform(platform);
    defer c.v8_dispose_platform();
    _ = c.v8_initialize();
    defer _ = c.v8_dispose();

    const setup = c.node_common_environment_setup_create(platform, result) orelse return error.CouldNotCreateSetup;
    defer c.node_common_environment_setup_free(setup);

    const isolate = c.node_common_environment_setup_isolate(setup);
    const env = c.node_common_environment_setup_env(setup);

    // Enter the v8 scopes. defers run LIFO, so they tear down in reverse order:
    // context_scope -> handle_scope -> isolate_scope -> locker.
    const locker = c.v8_locker_new(isolate);
    defer c.v8_locker_free(locker);
    const isolate_scope = c.v8_isolate_scope_new(isolate);
    defer c.v8_isolate_scope_free(isolate_scope);
    const handle_scope = c.v8_handle_scope_new(isolate);
    defer c.v8_handle_scope_free(handle_scope);

    const context = c.node_common_environment_setup_context(setup);
    defer c.v8_local_context_free(context);
    const context_scope = c.v8_context_scope_new(context);
    defer c.v8_context_scope_free(context_scope);

    // Install native test()/expect() globals on the context before running
    // anything, so they're present the moment user tests evaluate.
    const global = c.v8_context_global(context);
    defer c.v8_local_value_free(global);
    const test_fn = c.v8_function_new(context, testCallback, null);
    defer c.v8_local_value_free(test_fn);
    c.v8_object_set(context, global, "test", test_fn);
    const expect_fn = c.v8_function_new(context, &expectCallback, null);
    defer c.v8_local_value_free(expect_fn);
    c.v8_object_set(context, global, "expect", expect_fn);

    var code_to_bundle: std.ArrayList(u8) = .empty;

    // const cwd_path = try std.process.currentPathAlloc(io, arena);
    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    var walker = try cwd.walkSelectively(arena);
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.basename, "node_modules")) continue;
            if (std.mem.eql(u8, entry.basename, "zig-out")) continue;
            if (std.mem.eql(u8, entry.basename, ".zig-cache")) continue;
            if (std.mem.eql(u8, entry.basename, ".git")) continue;
            if (std.mem.eql(u8, entry.basename, ".next")) continue;
            if (std.mem.eql(u8, entry.basename, ".dist")) continue;
            try walker.enter(io, entry);
            continue;
        }
        if (std.mem.endsWith(u8, entry.path, ".test.js")) {
            try code_to_bundle.print(arena, "import './{s}'\n", .{entry.path});
        }
    }

    const entry_z = try arena.dupeZ(u8, code_to_bundle.items);
    const cwd_path = try std.process.currentPathAlloc(io, arena);

    var ok: c_int = 0;
    const bundled = esb.esbuild_bundle(entry_z.ptr, cwd_path.ptr, &ok);
    defer esb.esbuild_free(bundled);
    if (ok != 1) {
        std.debug.print("bundle failed:\n{s}\n", .{std.mem.span(bundled)});
        return error.BundleFailed;
    }

    if (!c.node_load_environment_module(env, bundled, "file:///testa-entry.mjs")) {
        return error.CouldNotLoadEnvironmentModule;
    }

    const loop_code = c.node_spin_event_loop(env);
    _ = c.node_stop(env);

    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    try stderr.interface.print("\n{d} passed, {d} failed\n", .{ passed_tests, failed_tests });
    try stderr.flush();
    if (loop_code != 0) {
        std.process.exit(@intCast(loop_code));
    } else if (failed_tests > 0) {
        return error.TestsFailed;
    }
}

