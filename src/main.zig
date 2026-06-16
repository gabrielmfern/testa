const std = @import("std");
const c = @import("node_c"); // translate-c of src/node_embed.h (see build.zig)

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // argv as a C array for InitializeOncePerProcess.
    const args = try init.minimal.args.toSlice(allocator);
    const argv = try allocator.alloc([*c]u8, args.len);
    for (args, 0..) |a, i| argv[i] = @constCast(a.ptr);

    // node::InitializeOncePerProcess (no V8 init — we own the platform).
    const flags = c.NODE_INIT_NO_INITIALIZE_V8 | c.NODE_INIT_NO_INITIALIZE_NODE_V8_PLATFORM;
    const result = c.node_initialize_once_per_process(@intCast(args.len), argv.ptr, flags) orelse
        return error.NodeInit;
    defer c.node_init_result_free(result);

    var i: c_int = 0;
    while (i < c.node_init_result_error_count(result)) : (i += 1) {
        std.debug.print("{s}: {s}\n", .{ args[0], c.node_init_result_error_at(result, i) });
    }
    if (c.node_init_result_early_return(result)) {
        std.process.exit(@intCast(c.node_init_result_exit_code(result)));
    }

    // MultiIsolatePlatform::Create + V8::InitializePlatform + V8::Initialize.
    const platform = c.node_multi_isolate_platform_create(4) orelse return error.Platform;
    c.v8_initialize_platform(platform);
    _ = c.v8_initialize();

    const exit_code = blk: {
        const setup = c.node_common_environment_setup_create(platform, result) orelse break :blk 1;
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

        const bootstrap = @embedFile("bootstrap.cjs");
        if (!c.node_load_environment(env, bootstrap)) break :blk 1;
        const exit_code = c.node_spin_event_loop(env);
        _ = c.node_stop(env);
        break :blk exit_code;
    };

    _ = c.v8_dispose();
    c.v8_dispose_platform();
    c.node_multi_isolate_platform_free(platform);
    c.node_teardown_once_per_process();
    std.process.exit(@intCast(exit_code));
}
