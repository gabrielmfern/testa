const std = @import("std");
const c = @import("node_c");
const esb = @import("esbuild_c");

var arena: std.mem.Allocator = undefined;

var passed_tests: u32 = 0;
var failed_tests: u32 = 0;
var io: std.Io = undefined;

// One per test that wrote anything; printed in a block keyed by name after all
// tests finish. name and bytes are owned by the program arena.
const TestOutput = struct {
    name: []const u8,
    stdout_bytes: []const u8,
    stderr_bytes: []const u8,
};
var outputs: std.ArrayList(TestOutput) = .empty;
// stdout/stderr written during the current test, captured here while it runs.
var captured_stdout: std.ArrayList(u8) = .empty;
var captured_stderr: std.ArrayList(u8) = .empty;

// Append a v8 value's string bytes to buf as UTF-8 (Latin1 one-byte strings
// widen to two bytes; UTF-16 is transcoded). The borrowed bytes are unpinned the
// moment v8_value_string_bytes returns, so they're consumed here with no V8 call
// in between.
fn appendV8Utf8(buf: *std.ArrayList(u8), isolate: ?*c.v8_isolate, value: ?*c.v8_local_value) void {
    const s = c.v8_value_string_bytes(isolate, value);
    const data = s.data orelse return;
    const len: usize = s.len;
    if (s.one_byte) {
        const bytes: [*]const u8 = @ptrCast(data);
        for (bytes[0..len]) |b| {
            if (b < 0x80) {
                buf.append(arena, b) catch {};
            } else {
                buf.append(arena, 0xC0 | (b >> 6)) catch {};
                buf.append(arena, 0x80 | (b & 0x3F)) catch {};
            }
        }
    } else {
        const units: [*]const u16 = @ptrCast(@alignCast(data));
        buf.print(arena, "{f}", .{std.unicode.fmtUtf16Le(units[0..len])}) catch {};
    }
}

fn captureStdoutWriteCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const chunk = c.v8_function_callback_info_get(info, 0);
    appendV8Utf8(&captured_stdout, isolate, chunk);
    c.v8_function_callback_info_set_return_value(info, c.v8_boolean_new(isolate, true));
}

fn captureStderrWriteCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const chunk = c.v8_function_callback_info_get(info, 0);
    appendV8Utf8(&captured_stderr, isolate, chunk);
    c.v8_function_callback_info_set_return_value(info, c.v8_boolean_new(isolate, true));
}

// Write a value's string bytes (borrowed from V8, zero copy) as UTF-8. The bytes
// are unpinned the moment v8_value_string_bytes returns, so read them here with
// no V8 call in between.
fn printV8String(w: *std.Io.Writer, isolate: ?*c.v8_isolate, value: ?*c.v8_local_value) void {
    const s = c.v8_value_string_bytes(isolate, value);
    const data = s.data orelse return;
    const len: usize = s.len;
    if (s.one_byte) {
        const bytes: [*]const u8 = @ptrCast(data);
        for (bytes[0..len]) |b| {
            // V8 one-byte strings are Latin1, so bytes >= 0x80 are two UTF-8 bytes.
            if (b < 0x80) {
                w.writeByte(b) catch return;
            } else {
                w.writeByte(0xC0 | (b >> 6)) catch return;
                w.writeByte(0x80 | (b & 0x3F)) catch return;
            }
        }
    } else {
        const units: [*]const u16 = @ptrCast(@alignCast(data));
        w.print("{f}", .{std.unicode.fmtUtf16Le(units[0..len])}) catch return;
    }
}

// expect(actual).toBe(expected): strict identity via v8 SameValue (Object.is).
// `actual` rides along as the function's bound data.
fn toBeCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const actual = c.v8_function_callback_info_data(info);
    const expected = c.v8_function_callback_info_get(info, 0);
    if (c.v8_value_same_value(actual, expected)) return;

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(buf[0 .. buf.len - 1]);
    w.writeAll("expected ") catch {};
    printV8String(&w, isolate, expected);
    w.writeAll(" but got ") catch {};
    printV8String(&w, isolate, actual);
    buf[w.end] = 0;
    c.v8_isolate_throw_error(isolate, buf[0..w.end :0]);
}

// expect(actual) -> { toBe } with `actual` bound as the toBe closure's data.
fn expectCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);
    const actual = c.v8_function_callback_info_get(info, 0);

    const obj = c.v8_object_new(isolate);
    const to_be = c.v8_function_new(ctx, &toBeCallback, actual);
    c.v8_object_set(ctx, obj, "toBe", to_be);
    c.v8_function_callback_info_set_return_value(info, obj);
}

// test(name, closure): run it now, time it, report one plain-text line.
fn testCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);

    const name_val = c.v8_function_callback_info_get(info, 0);
    const closure = c.v8_function_callback_info_get(info, 1);
    const recv = c.v8_undefined(isolate);

    var tc: c.v8_try_catch = undefined;
    c.v8_try_catch_init(&tc, isolate);
    defer c.v8_try_catch_deinit(&tc);

    // Redirect process.stdout/stderr.write to a native buffer for the duration of
    // the test, then restore the originals so output outside tests still goes
    // straight to the terminal. The originals are saved as locals in the
    // program-wide HandleScope (opened in main, never torn down here), so they
    // outlive the call. A fresh buffer per test; the bytes stay in the arena so
    // they survive until the end-of-run dump.
    captured_stdout = .empty;
    captured_stderr = .empty;
    const global = c.v8_context_global(ctx);
    const process = c.v8_object_get(ctx, global, "process");
    const test_stdout = c.v8_object_get(ctx, process, "stdout");
    const test_stderr = c.v8_object_get(ctx, process, "stderr");
    const original_test_stdout_write = c.v8_object_get(ctx, test_stdout, "write");
    const original_test_stderr_write = c.v8_object_get(ctx, test_stderr, "write");
    const test_stdout_hook = c.v8_function_new(ctx, &captureStdoutWriteCallback, null);
    const test_stderr_hook = c.v8_function_new(ctx, &captureStderrWriteCallback, null);
    c.v8_object_set(ctx, test_stdout, "write", test_stdout_hook);
    c.v8_object_set(ctx, test_stderr, "write", test_stderr_hook);

    const start = std.Io.Timestamp.now(io, .awake);
    _ = c.v8_function_call(ctx, closure, recv, 0, null);
    const duration = start.untilNow(io, .awake);

    c.v8_object_set(ctx, test_stdout, "write", original_test_stdout_write);
    c.v8_object_set(ctx, test_stderr, "write", original_test_stderr_write);

    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    const w = &stderr.interface;
    if (c.v8_try_catch_has_caught(&tc)) {
        failed_tests += 1;
        const exc = c.v8_try_catch_exception(&tc);
        w.writeAll("not ok ") catch {};
        printV8String(w, isolate, name_val);
        w.print(" ({f})\n  ", .{duration}) catch {};
        printV8String(w, isolate, exc);
        w.writeAll("\n") catch {};
    } else {
        passed_tests += 1;
        w.writeAll("ok ") catch {};
        printV8String(w, isolate, name_val);
        w.print(" ({f})\n", .{duration}) catch {};
    }
    w.flush() catch {};

    // Stash this test's output (if any) to print in a per-test block at the end,
    // like vitest. The name is materialized now while its v8 handle is live.
    if (captured_stdout.items.len > 0 or captured_stderr.items.len > 0) {
        var name_buf: std.ArrayList(u8) = .empty;
        appendV8Utf8(&name_buf, isolate, name_val);
        outputs.append(arena, .{
            .name = name_buf.items,
            .stdout_bytes = captured_stdout.items,
            .stderr_bytes = captured_stderr.items,
        }) catch {};
    }
}

// this would basically be enough for running a 100,000 test suite
var testa_allocations_buffer: [50000000]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&testa_allocations_buffer);
    const fixed_buffer_allocator = fixed_buffer.allocator();

    var arena_allocator = std.heap.ArenaAllocator.init(fixed_buffer_allocator);
    defer arena_allocator.deinit();
    arena = arena_allocator.allocator();

    io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*c]u8, args.len);
    argv[0] = @constCast(args[0].ptr);
    for (args[1..], 0..) |a, j| argv[1 + j] = @constCast(a.ptr);
    const argc: c_int = @intCast(argv.len);

    const flags = c.NODE_INIT_NO_INITIALIZE_V8 | c.NODE_INIT_NO_INITIALIZE_NODE_V8_PLATFORM;
    var result: c.node_init_result = undefined;
    c.node_initialize_once_per_process(argc, argv.ptr, flags, &result);
    defer c.node_teardown_once_per_process();
    defer c.node_init_result_deinit(&result);

    var i: c_int = 0;
    while (i < c.node_init_result_error_count(&result)) : (i += 1) {
        std.debug.print("{s}: {s}\n", .{ args[0], c.node_init_result_error_at(&result, i) });
    }
    if (c.node_init_result_early_return(&result)) {
        std.process.exit(@intCast(c.node_init_result_exit_code(&result)));
    }

    const platform = c.node_multi_isolate_platform_create(4) orelse return error.Platform;
    defer c.node_multi_isolate_platform_free(platform);
    c.v8_initialize_platform(platform);
    defer c.v8_dispose_platform();
    _ = c.v8_initialize();
    defer _ = c.v8_dispose();

    const setup = c.node_common_environment_setup_create(platform, &result) orelse return error.CouldNotCreateSetup;
    defer c.node_common_environment_setup_free(setup);

    const isolate = c.node_common_environment_setup_isolate(setup);
    const env = c.node_common_environment_setup_env(setup);

    // Enter the v8 scopes. Each guard lives in stack storage here; defers run
    // LIFO, so they tear down in reverse order: context_scope -> handle_scope ->
    // isolate_scope -> locker.
    var locker: c.v8_locker = undefined;
    c.v8_locker_init(&locker, isolate);
    defer c.v8_locker_deinit(&locker);
    var isolate_scope: c.v8_isolate_scope = undefined;
    c.v8_isolate_scope_init(&isolate_scope, isolate);
    defer c.v8_isolate_scope_deinit(&isolate_scope);
    var handle_scope: c.v8_handle_scope = undefined;
    c.v8_handle_scope_init(&handle_scope, isolate);
    defer c.v8_handle_scope_deinit(&handle_scope);

    const context = c.node_common_environment_setup_context(setup);
    var context_scope: c.v8_context_scope = undefined;
    c.v8_context_scope_init(&context_scope, context);
    defer c.v8_context_scope_deinit(&context_scope);

    // Install native test()/expect() globals on the context before running
    // anything, so they're present the moment user tests evaluate.
    const global = c.v8_context_global(context);
    const test_fn = c.v8_function_new(context, testCallback, null);
    c.v8_object_set(context, global, "test", test_fn);
    const expect_fn = c.v8_function_new(context, &expectCallback, null);
    c.v8_object_set(context, global, "expect", expect_fn);

    var code_to_bundle: std.ArrayList(u8) = .empty;

    const cwd = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    var walker = try cwd.walkSelectively(arena);
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.basename, "node_modules")) continue;
            if (std.mem.eql(u8, entry.basename, "zig-out")) continue;
            if (std.mem.eql(u8, entry.basename, ".zig-cache")) continue;
            if (std.mem.eql(u8, entry.basename, ".git")) continue;
            if (std.mem.eql(u8, entry.basename, ".next")) continue;
            if (std.mem.eql(u8, entry.basename, "dist")) continue;
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
    const w = &stderr.interface;

    for (outputs.items) |out| {
        if (out.stdout_bytes.len > 0) {
            try w.print("\nstdout | {s}\n", .{out.name});
            try w.writeAll(out.stdout_bytes);
        }

        if (out.stderr_bytes.len > 0) {
            try w.print("\nstderr | {s}\n", .{out.name});
            try w.writeAll(out.stderr_bytes);
        }
    }

    try w.print("\n{d} passed, {d} failed\n", .{ passed_tests, failed_tests });
    try stderr.flush();
    if (loop_code != 0) {
        std.process.exit(@intCast(loop_code));
    } else if (failed_tests > 0) {
        std.process.exit(1);
    }
}
