const std = @import("std");
const c = @import("node_c");
const esb = @import("esbuild_c");
const builtin = @import("builtin");

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
var captured_stdout: std.Io.Writer.Allocating = undefined;
var captured_stderr: std.Io.Writer.Allocating = undefined;

// A tsconfig `paths` entry, "@/*" -> ["src/*"], stored as a literal prefix
// ("@/") and the absolute directory it expands to ("/abs/src/").
const Alias = struct { prefix: []const u8, replacement: []const u8 };

const source_extensions = [_][]const u8{ ".ts", ".tsx", ".jsx", ".js", ".mjs", ".cjs", ".json" };
const index_files = [_][]const u8{ "index.ts", "index.tsx", "index.jsx", "index.js" };

// Module-graph state read by the (callconv(.c), no-userdata) resolve callback.
// Set up in main before instantiating; all persistent strings/maps live in the
// program arena, so there's nothing to free.
var g_ctx: ?*c.v8_local_context = undefined;
var g_isolate: ?*c.v8_isolate = undefined;
// The libuv loop, so testCallback can pump it to settle an async test's promise.
var g_loop: ?*c.uv_loop = undefined;
var g_cwd: []const u8 = undefined;
var g_aliases: []const Alias = &.{};
var g_path_to_module: std.StringHashMapUnmanaged(*c.v8_module) = .empty;
// Importer module -> its own directory, keyed by GetIdentityHash (Local handles
// aren't pointer-stable across resolve calls), so relative imports resolve.
var g_dir_by_module: std.AutoHashMapUnmanaged(c_int, []const u8) = .empty;

fn captureStdoutWriteCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const chunk = c.v8_function_callback_info_get(info, 0);
    printV8String(&captured_stdout.writer, isolate, chunk);
    c.v8_function_callback_info_set_return_value(info, c.v8_boolean_new(isolate, true));
}

fn captureStderrWriteCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const chunk = c.v8_function_callback_info_get(info, 0);
    printV8String(&captured_stderr.writer, isolate, chunk);
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

// test(name, closure) and test.fails(name, closure) are these two trampolines
// over runTest; the only difference is whether a throw/rejection is the failure
// or the expected outcome.
fn testCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    runTest(info, false);
}
fn testFailsCallback(info: ?*const c.v8_function_callback_info) callconv(.c) void {
    runTest(info, true);
}

// Run a test now, time it, report one plain-text line. An async closure returns a
// promise; pump microtasks and the libuv loop until it settles so its post-await
// assertions and rejections are seen, just like a sync test's. The loop is run
// re-entrantly here (we're nested inside module evaluation), but no test is
// running concurrently, so the promise owns whatever the loop waits on. With
// expect_failure (test.fails), a throw/rejection is the pass and a clean run the
// failure; a deadlock fails either way.
fn runTest(info: ?*const c.v8_function_callback_info, expect_failure: bool) void {
    const isolate = c.v8_function_callback_info_isolate(info);
    const ctx = c.v8_isolate_get_current_context(isolate);

    const name_val = c.v8_function_callback_info_get(info, 0);
    const closure = c.v8_function_callback_info_get(info, 1);
    const recv = c.v8_undefined(isolate);

    var tc: c.v8_try_catch = undefined;
    c.v8_try_catch_init(&tc, isolate);
    defer c.v8_try_catch_deinit(&tc);

    // Redirect process.stdout/stderr.write to a native buffer for the duration of
    // the test (including its async tail), then restore the originals so output
    // outside tests still goes straight to the terminal. The originals are saved
    // as locals in the program-wide HandleScope (opened in main, never torn down
    // here), so they outlive the call. A fresh buffer per test; the bytes stay in
    // the arena so they survive until the end-of-run dump.
    captured_stdout = .init(arena);
    captured_stderr = .init(arena);
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
    const result = c.v8_function_call(ctx, closure, recv, 0, null);

    var async_rejection: ?*c.v8_local_value = null;
    var deadlocked = false;
    if (!c.v8_try_catch_has_caught(&tc) and result != null and c.v8_value_is_promise(result)) {
        // We surface this promise's rejection as the test failure ourselves, so
        // pre-mark it handled: a microtask checkpoint that rejects it ends by
        // running Node's unhandled-rejection processing (fatal by default), and
        // that fires before we'd get to inspect the result. The mark sets the
        // has-handler bit up front, so the rejection is never flagged.
        c.v8_promise_mark_as_handled(result);
        while (c.v8_promise_state(result) == c.V8_PROMISE_PENDING) {
            c.v8_isolate_perform_microtask_checkpoint(isolate);
            if (c.v8_promise_state(result) != c.V8_PROMISE_PENDING) break;
            // Advance timers/IO; UV_RUN_ONCE blocks until the loop's next event.
            // Node runs the awaited continuation (and drains microtasks) inside
            // this call, so a one-shot timer settles the promise on the very turn
            // that empties the loop and makes uv_run return 0. Re-check before
            // judging: only a still-pending promise with a drained loop is a real
            // deadlocked await rather than a test that just finished.
            if (c.node_uv_run_once(g_loop) == 0) {
                c.v8_isolate_perform_microtask_checkpoint(isolate);
                if (c.v8_promise_state(result) == c.V8_PROMISE_PENDING) deadlocked = true;
                break;
            }
        }
        if (c.v8_promise_state(result) == c.V8_PROMISE_REJECTED) async_rejection = c.v8_promise_result(result);
    }
    const duration = start.untilNow(io, .awake);

    c.v8_object_set(ctx, test_stdout, "write", original_test_stdout_write);
    c.v8_object_set(ctx, test_stderr, "write", original_test_stderr_write);

    const errored = c.v8_try_catch_has_caught(&tc) or async_rejection != null;
    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    const w = &stderr.interface;
    if (!deadlocked and errored == expect_failure) {
        passed_tests += 1;
        w.writeAll("ok ") catch {};
        printV8String(w, isolate, name_val);
        // A test.fails that passed did so by failing; mark it so the line isn't
        // mistaken for an ordinary pass.
        if (expect_failure) w.writeAll(" (expected not ok)") catch {};
        w.print(" ({f})\n", .{duration}) catch {};
    } else {
        failed_tests += 1;
        w.writeAll("not ok ") catch {};
        printV8String(w, isolate, name_val);
        w.print(" ({f})\n  ", .{duration}) catch {};
        if (deadlocked) {
            w.writeAll("testa: test never settled; its promise stayed pending with nothing left to run") catch {};
        } else if (expect_failure) {
            w.writeAll("testa: expected this test to fail, but it passed") catch {};
        } else if (async_rejection) |reason| {
            printV8String(w, isolate, reason);
        } else {
            printV8String(w, isolate, c.v8_try_catch_exception(&tc));
        }
        w.writeAll("\n") catch {};
    }
    w.flush() catch {};

    // Stash this test's output (if any) to print in a per-test block at the end,
    // like vitest. The name is materialized now while its v8 handle is live.
    if (captured_stdout.written().len > 0 or captured_stderr.written().len > 0) {
        var name_buf: std.Io.Writer.Allocating = .init(arena);
        printV8String(&name_buf.writer, isolate, name_val);
        outputs.append(arena, .{
            .name = name_buf.written(),
            .stdout_bytes = captured_stdout.written(),
            .stderr_bytes = captured_stderr.written(),
        }) catch {};
    }
}

// Resolve a relative or tsconfig-aliased import to an existing absolute file
// path, probing extensions, index files, and the TS `.js`->`.ts` rewrite. Bare
// specifiers (npm / node:) aren't supported in v1.
fn resolveSpecifier(spec: []const u8, base_dir: []const u8) ![]const u8 {
    const cwd = std.Io.Dir.cwd();
    var scratch: [std.Io.Dir.max_path_bytes]u8 = undefined;

    var rel = spec;
    var aliased = false;
    for (g_aliases) |a| {
        if (std.mem.startsWith(u8, spec, a.prefix)) {
            rel = std.fmt.bufPrint(&scratch, "{s}{s}", .{ a.replacement, spec[a.prefix.len..] }) catch return error.NotFound;
            aliased = true;
            break;
        }
    }

    const relative = std.mem.startsWith(u8, rel, "./") or std.mem.startsWith(u8, rel, "../");
    if (!aliased and !relative and !std.fs.path.isAbsolute(rel)) return error.UnsupportedBareImport;

    const base = if (aliased) g_cwd else base_dir;
    const joined = if (std.fs.path.isAbsolute(rel))
        try arena.dupe(u8, rel)
    else
        try std.fs.path.resolve(arena, &.{ base, rel });

    var has_ext = false;
    for (source_extensions) |ext| {
        if (std.mem.endsWith(u8, joined, ext)) has_ext = true;
    }

    var cand: [std.Io.Dir.max_path_bytes + 16]u8 = undefined;
    if (has_ext) {
        cwd.access(io, joined, .{}) catch {
            // TS emits `./x.js` for a `./x.ts` source; fall back to the real extension.
            if (std.mem.endsWith(u8, joined, ".js")) {
                for ([_][]const u8{ ".ts", ".tsx" }) |ext| {
                    const probe = std.fmt.bufPrint(&cand, "{s}{s}", .{ joined[0 .. joined.len - ".js".len], ext }) catch return error.NotFound;
                    cwd.access(io, probe, .{}) catch continue;
                    return try arena.dupe(u8, probe);
                }
            }
            return error.NotFound;
        };
        return joined;
    }

    for (source_extensions) |ext| {
        const probe = std.fmt.bufPrint(&cand, "{s}{s}", .{ joined, ext }) catch return error.NotFound;
        cwd.access(io, probe, .{}) catch continue;
        return try arena.dupe(u8, probe);
    }
    for (index_files) |idx| {
        const probe = std.fmt.bufPrint(&cand, "{s}/{s}", .{ joined, idx }) catch return error.NotFound;
        cwd.access(io, probe, .{}) catch continue;
        return try arena.dupe(u8, probe);
    }
    return error.NotFound;
}

// Compiled module for an absolute path, transpiling + caching on first use.
// Reusing the cached module for a repeated path lets V8 resolve import cycles
// natively, and records each module's dir for its relative imports. Throws into
// V8 on any failure, so callers just propagate.
fn loadModule(abs: []const u8) !*c.v8_module {
    if (g_path_to_module.get(abs)) |m| return m;

    const path_z = try arena.dupeZ(u8, abs);
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, abs, arena, .unlimited, .of(u8), 0) catch {
        var b: [1024]u8 = undefined;
        const m: [:0]const u8 = std.fmt.bufPrintZ(&b, "testa: cannot read {s}", .{abs}) catch "testa: read error";
        c.v8_isolate_throw_error(g_isolate, m.ptr);
        return error.Failed;
    };

    var ok: c_int = 0;
    const transpiled = esb.esbuild_transform(source.ptr, path_z.ptr, &ok);
    defer esb.esbuild_free(transpiled);
    if (ok != 1) {
        c.v8_isolate_throw_error(g_isolate, transpiled);
        return error.Failed;
    }

    const mod = c.v8_compile_module(g_ctx, transpiled, path_z.ptr) orelse {
        var b: [1024]u8 = undefined;
        const m: [:0]const u8 = std.fmt.bufPrintZ(&b, "testa: failed to compile {s}", .{abs}) catch "testa: compile error";
        c.v8_isolate_throw_error(g_isolate, m.ptr);
        return error.Failed;
    };

    try g_path_to_module.put(arena, abs, mod);
    g_dir_by_module.put(arena, c.v8_module_identity_hash(mod), std.fs.path.dirname(abs) orelse g_cwd) catch {};
    return mod;
}

fn resolveModuleCallback(ctx: ?*c.v8_local_context, specifier: [*c]const u8, referrer: ?*c.v8_module) callconv(.c) ?*c.v8_module {
    _ = ctx;
    const spec = std.mem.span(specifier);
    const base_dir = if (referrer) |r| (g_dir_by_module.get(c.v8_module_identity_hash(r)) orelse g_cwd) else g_cwd;

    const resolved = resolveSpecifier(spec, base_dir) catch |err| {
        var buf: [1024]u8 = undefined;
        const msg: [:0]const u8 = switch (err) {
            error.UnsupportedBareImport => std.fmt.bufPrintZ(&buf, "testa: import \"{s}\" is a bare/builtin specifier, which is not supported yet", .{spec}) catch "testa: unsupported import",
            else => std.fmt.bufPrintZ(&buf, "testa: cannot find module \"{s}\"", .{spec}) catch "testa: module not found",
        };
        c.v8_isolate_throw_error(g_isolate, msg.ptr);
        return null;
    };
    return loadModule(resolved) catch null;
}

// tsconfig is often JSONC; if std.json can't parse it, run without aliases
// rather than fail.
fn loadAliases() []const Alias {
    const data = std.Io.Dir.cwd().readFileAlloc(io, "tsconfig.json", arena, .unlimited) catch return &.{};
    const parsed = std.json.parseFromSlice(std.json.Value, arena, data, .{}) catch return &.{};
    const root = switch (parsed.value) {
        .object => |o| o,
        else => return &.{},
    };
    const co = switch (root.get("compilerOptions") orelse return &.{}) {
        .object => |o| o,
        else => return &.{},
    };
    const base_url = if (co.get("baseUrl")) |b| (switch (b) {
        .string => |s| s,
        else => ".",
    }) else ".";
    const paths = switch (co.get("paths") orelse return &.{}) {
        .object => |o| o,
        else => return &.{},
    };

    var list: std.ArrayListUnmanaged(Alias) = .empty;
    var it = paths.iterator();
    while (it.next()) |e| {
        const key = e.key_ptr.*;
        const targets = switch (e.value_ptr.*) {
            .array => |a| a,
            else => continue,
        };
        if (targets.items.len == 0) continue;
        const target = switch (targets.items[0]) {
            .string => |s| s,
            else => continue,
        };
        if (!std.mem.endsWith(u8, key, "*") or !std.mem.endsWith(u8, target, "*")) continue;
        // Keep relative to baseUrl with the trailing slash intact so "@/x" -> "src/x";
        // resolveSpecifier resolves it against cwd at use.
        const target_prefix = target[0 .. target.len - 1];
        const replacement = if (std.mem.eql(u8, base_url, ".") or base_url.len == 0)
            arena.dupe(u8, target_prefix) catch continue
        else
            std.fmt.allocPrint(arena, "{s}/{s}", .{ base_url, target_prefix }) catch continue;
        const prefix = arena.dupe(u8, key[0 .. key.len - 1]) catch continue;
        list.append(arena, .{ .prefix = prefix, .replacement = replacement }) catch continue;
    }
    return list.toOwnedSlice(arena) catch &.{};
}

// this would basically be enough for running a 100,000 test suite
var testa_allocations_buffer: [50000000]u8 = undefined;

// Startup phase timing, compiled out entirely outside Debug builds. mark() prints
// the elapsed time since the previous mark (or begin) and resets the clock.
const time_phases = builtin.mode == .Debug;
const Phase = struct {
    last: if (time_phases) std.Io.Timestamp else void,

    fn begin() Phase {
        return .{ .last = if (time_phases) std.Io.Timestamp.now(io, .awake) else {} };
    }
    fn mark(self: *Phase, comptime label: []const u8) void {
        if (time_phases) {
            std.debug.print("[t] " ++ label ++ ": {f}\n", .{self.last.untilNow(io, .awake)});
            self.last = std.Io.Timestamp.now(io, .awake);
        }
    }
};

// Set true by the platform once a disposed isolate's resources have been released.
fn isolateFinished(data: ?*anyopaque) callconv(.c) void {
    const flag: *bool = @ptrCast(@alignCast(data.?));
    flag.* = true;
}

// Tear an isolate down in the order node requires: arm the finished callback,
// dispose the isolate (which flushes its foreground tasks, so it must still be
// registered here), unregister it right after, then pump the loop until the
// platform reports its resources are gone (mirrors CommonEnvironmentSetup).
fn disposeIsolate(platform: *c.v8_platform, isolate: *c.v8_isolate, loop: *c.uv_loop) void {
    var finished = false;
    c.node_platform_add_isolate_finished_callback(platform, isolate, &isolateFinished, &finished);
    c.node_isolate_dispose(isolate);
    c.node_platform_unregister_isolate(platform, isolate);
    while (!finished) _ = c.node_uv_run_once(loop);
}

pub fn main(init: std.process.Init) !void {
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&testa_allocations_buffer);
    const fixed_buffer_allocator = fixed_buffer.allocator();

    var arena_allocator = std.heap.ArenaAllocator.init(fixed_buffer_allocator);
    defer arena_allocator.deinit();
    arena = arena_allocator.allocator();

    io = init.io;

    var phase: Phase = .begin();

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

    phase.mark("node_initialize_once_per_process");

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

    phase.mark("platform create + v8_initialize");

    // Assemble the Node environment from primitives (node_embed.h explains why we
    // don't use CommonEnvironmentSetup). Each defer sits right after the step it
    // undoes, so they unwind in the order a clean teardown needs: free env +
    // isolate_data while the isolate is still entered, then close the scopes, then
    // unregister + dispose the isolate and drain + close the loop.
    const loop = c.node_uv_loop_create() orelse return error.CouldNotCreateLoop;
    defer c.node_uv_loop_close(loop);
    const allocator = c.node_array_buffer_allocator_create() orelse return error.CouldNotCreateAllocator;
    defer c.node_array_buffer_allocator_free(allocator);
    const isolate = c.node_new_isolate(allocator, loop, platform) orelse return error.CouldNotCreateIsolate;
    defer disposeIsolate(platform, isolate, loop);

    phase.mark("new isolate");

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

    const isolate_data = c.node_create_isolate_data(isolate, loop, platform, allocator);
    defer c.node_free_isolate_data(isolate_data);

    const context = c.node_new_context(isolate) orelse return error.CouldNotCreateContext;
    var context_scope: c.v8_context_scope = undefined;
    c.v8_context_scope_init(&context_scope, context);
    defer c.v8_context_scope_deinit(&context_scope);

    // kDefaultFlags keeps the full Node runtime (process state, ESM loader, browser
    // globals); the two opt-outs drop only the inspector and its SIGUSR1 debug i/o
    // thread, which a test runner never uses.
    const env_flags = c.NODE_ENV_DEFAULT_FLAGS | c.NODE_ENV_NO_CREATE_INSPECTOR | c.NODE_ENV_NO_START_DEBUG_SIGNAL_HANDLER;
    const env = c.node_create_environment(isolate_data, context, &result, env_flags) orelse return error.CouldNotCreateEnvironment;
    defer c.node_free_environment(env);

    phase.mark("create environment (bootstrap)");

    // Bootstrap Node so its globals (process, console, queueMicrotask, ...) exist
    // before we evaluate modules. We can't load the tests via
    // node_load_environment_module: that drives Node's own resolver, but we want
    // ours, so we bootstrap with an empty main and drive the module API directly.
    if (!c.node_load_environment(env, "")) return error.CouldNotBootstrapNode;

    phase.mark("node_load_environment (bootstrap)");

    const global = c.v8_context_global(context);
    const test_fn = c.v8_function_new(context, testCallback, null);
    c.v8_object_set(context, global, "test", test_fn);
    // test.fails(name, closure): passes only when the closure throws or rejects.
    const test_fails_fn = c.v8_function_new(context, testFailsCallback, null);
    c.v8_object_set(context, test_fn, "fails", test_fails_fn);
    const expect_fn = c.v8_function_new(context, &expectCallback, null);
    c.v8_object_set(context, global, "expect", expect_fn);

    const cwd_path = try std.process.currentPathAlloc(io, arena);
    g_ctx = context;
    g_isolate = isolate;
    g_loop = loop;
    g_cwd = cwd_path;
    g_aliases = loadAliases();

    var test_files: std.ArrayList([]const u8) = .empty;
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
        const p = entry.path;
        if (std.mem.endsWith(u8, p, ".test.ts") or std.mem.endsWith(u8, p, ".test.tsx") or
            std.mem.endsWith(u8, p, ".test.jsx") or std.mem.endsWith(u8, p, ".test.js"))
        {
            try test_files.append(arena, try std.fs.path.resolve(arena, &.{ cwd_path, p }));
        }
    }

    var buffer: [128]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &buffer);
    const w = &stderr.interface;

    // Each test file is its own entry: transpile it, instantiate it (which drives
    // the resolve callback over its imports), then evaluate it on its own. Any
    // failure along the way (resolve, transpile, compile, top-level throw) leaves
    // an exception in `tc`; report it once and mark the run failed.
    var load_failed = false;
    for (test_files.items) |abs| {
        var tc: c.v8_try_catch = undefined;
        c.v8_try_catch_init(&tc, isolate);
        defer c.v8_try_catch_deinit(&tc);

        if (loadModule(abs) catch null) |mod| {
            if (c.v8_module_instantiate(context, mod, &resolveModuleCallback)) {
                _ = c.v8_module_evaluate(context, mod);
            }
        }
        if (c.v8_try_catch_has_caught(&tc)) {
            w.writeAll("error: ") catch {};
            printV8String(w, isolate, c.v8_try_catch_exception(&tc));
            w.writeAll("\n") catch {};
            w.flush() catch {};
            load_failed = true;
        }
    }

    phase.mark("discover + load + evaluate test files");

    const loop_code = c.node_spin_event_loop(env);

    phase.mark("spin_event_loop");
    _ = c.node_stop(env);

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
    } else if (failed_tests > 0 or load_failed) {
        std.process.exit(1);
    }
}
