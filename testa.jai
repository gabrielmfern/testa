#import "Basic";
#import "String";
#import "File";
#import "Thread";
#import "File_Utilities";

#load "napi-linux.jai";

callback_ctx: #Context;

napi_env_instance: napi_env;
node_env: *node_environment;

passed := 0;
failed := 0;

TestState :: struct {
    passed: bool;
};

test_state: TestState;

Compiler :: #import "Compiler";

DEBUG :: #run Compiler.get_build_options().array_bounds_check == .ON;

log_debug :: (format: string, args: .. Any, loc := #caller_location) {
  #if DEBUG  log(format, ..args, loc = loc);
}

to_be :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context callback_ctx {
        argc: u64 = 1;
        expected: napi_value;
        matcher: napi_value;
        napi_get_cb_info(env, info, *argc, *expected, *matcher, null);
        actual: napi_value;
        napi_get_named_property(env, matcher, "actual".data, *actual);
        equal: bool;
        napi_strict_equals(env, actual, expected, *equal);
        if equal {
            test_state.passed = true;
        } else {
            test_state.passed = false;
        }
    }
    return null;
}

expect :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    matcher: napi_value;
    push_context callback_ctx {
        argc: u64 = 1;
        actual: napi_value;
        napi_get_cb_info(env, info, *argc, *actual, null, null);
        napi_create_object(env, *matcher);
        napi_set_named_property(env, matcher, "actual".data, actual);
        fn: napi_value;
        napi_create_function(env, "toBe".data, "toBe".count, to_be, null, *fn);
        napi_set_named_property(env, matcher, "toBe".data, fn);
    }
    return matcher;
}

register :: (env: napi_env, exports: napi_value) -> napi_value #c_call {
    push_context callback_ctx {
        napi_env_instance = env;
        global: napi_value;
        napi_get_global(env, *global);
        fn: napi_value;
        napi_create_function(env, "expect".data, "expect".count, expect, null, *fn);
        napi_set_named_property(env, global, "expect".data, fn);
    }
    return exports;
}

BOOTSTRAP :: #run read_entire_file("__bootstrap__.mjs", zero_terminated=true);

Watchdog :: struct {
    thread: Thread;
    wake: Semaphore;
    mutex: Mutex;

    node_setup: *node_common_environment_setup;

    deadline_ms: s64;
    // someone called watchdog_shutdown
    shutdown: bool;
    // the deadline was hit 
    fired: bool;
}

watchdog_init :: (w: *Watchdog, setup: *node_common_environment_setup) {
    w.node_setup = setup;
    init(*w.wake);
    init(*w.mutex);
    thread_init(*w.thread, watchdog_proc, name = "Watchdog");
    w.thread.data = w;
    thread_start(*w.thread);
}

watchdog_shutdown :: (w: *Watchdog) {
    atomic_store(*w.shutdown, true);
    signal(*w.wake);
    thread_is_done(*w.thread, -1);
    thread_deinit(*w.thread);
    destroy(*w.wake);
    destroy(*w.mutex);
}

watchdog_arm :: (w: *Watchdog, timeout_ms: s64) {
    log_debug("WATCHDOG: arming\n");
    lock(*w.mutex);
    w.deadline_ms = to_milliseconds(current_time_monotonic()) + timeout_ms;
    atomic_store(*w.fired, false);
    unlock(*w.mutex);
    signal(*w.wake);
}

watchdog_disarm :: (w: *Watchdog) {
    log_debug("WATCHDOG: disarming manually\n");
    lock(*w.mutex);
    w.deadline_ms = 0;
    unlock(*w.mutex);
    signal(*w.wake);
}

watchdog_proc :: (thread: *Thread) -> s64 {
    w := cast(*Watchdog) thread.data;
    while !atomic_load(*w.shutdown) {
        lock(*w.mutex);
        if w.deadline_ms != 0 {
            remaining := w.deadline_ms - to_milliseconds(current_time_monotonic());
            if remaining <= 0 {
                log_debug("WATCHDOG: timeout was reached here, disarming automatically\n");
                node_stop_event_loop(w.node_setup);
                w.deadline_ms = 0;
                atomic_store(*w.fired, true);
                unlock(*w.mutex);
            } else {
                log_debug("WATCHDOG: it is armed, and timeout was not reached. waiting for %ms\n", remaining);
                unlock(*w.mutex);
                wait_for(*w.wake, xx remaining);
            }
        } else {
            unlock(*w.mutex);
        }

        if w.deadline_ms == 0 {
            log_debug("WATCHDOG: waiting indefinitely because it's disarmed\n");
            wait_for(*w.wake, -1);
        }
    }

    return 0;
}

watchdog: Watchdog;

main :: () {
    callback_ctx = context;
    args := get_command_line_arguments();
    dir := ifx args.count > 1 then args[1] else ".";

    init := node_initialize_once_per_process();
    if node_initialization_result_early_return(init) != 0 exit(node_initialization_result_exit_code(init));
    defer node_tear_down_once_per_process();

    platform := node_multi_isolate_platform_create(4);
    v8_initialize(platform);
    defer v8_dispose(platform);

    setup := node_common_environment_setup_create(platform, init);
    if !setup exit(1);
    defer node_common_environment_setup_destroy(setup);
    node_env = node_common_environment_setup_env(setup);
    defer node_stop(node_env);

    watchdog_init(*watchdog, setup);
    defer watchdog_shutdown(*watchdog);

    scope := v8_scope_open(setup);
    defer v8_scope_close(scope);
    node_add_linked_binding(node_env, "testa".data, register);
    status := node_load_environment_module(node_env, BOOTSTRAP.data, "file:///__bootstrap__.mjs".data);
    if status == 1 {
        log_error("Could not load environment with bootstrap script");
        return;
    }
    assert(napi_env_instance != null);

    RunContext :: struct {
        setup: *node_common_environment_setup;
        global: napi_value;
        fn: napi_value;
        arg: napi_value;
        result: napi_value;
    }

    runContext : RunContext;
    runContext.setup = setup;
    napi_get_global(napi_env_instance, *runContext.global);
    napi_get_named_property(napi_env_instance, runContext.global, "__testa_run".data, *runContext.fn);

    file_visitor :: (info: *File_Visit_Info, user_data: *void) {
        runContext := cast(*RunContext) user_data;
        if ends_with(info.short_name, ".test.ts") || 
            ends_with(info.short_name, ".test.js") || 
            ends_with(info.short_name, ".test.mts") || 
            ends_with(info.short_name, ".test.mjs") ||
            ends_with(info.short_name, ".spec.ts") || 
            ends_with(info.short_name, ".spec.js") || 
            ends_with(info.short_name, ".spec.mts") || 
            ends_with(info.short_name, ".spec.mjs") {
            absolute, success := get_absolute_path(info.full_name);
            if !success {
                log_error("Could not resolve path: %", info.full_name);
                return;
            }

            start := current_time_monotonic();
            test_state.passed = false;

            watchdog_arm(*watchdog, 10);

            // TODO: store this exception and show it later once the tests are done. 
            // we should also do the same for the stdout/stderr output from the test, too.
            result: napi_value;
            if napi_get_and_clear_last_exception(napi_env_instance, *result) != .ok {
                log_error("Could not get and clear exception from last test run");
                return;
            }

            napi_create_string_utf8(napi_env_instance, absolute.data, cast(u64) absolute.count, *runContext.arg);
            napi_call_function(
                napi_env_instance, 
                runContext.global, 
                runContext.fn, 
                1, 
                *runContext.arg, 
                *runContext.result
            );
            while node_spin_event_loop_once(runContext.setup) {
                if atomic_load(*watchdog.fired) {
                    log_debug("WATCHDOG: breaking spin event loop because it took too long, and watchdog fired");
                    break;
                }
            }
            if atomic_load(*watchdog.fired) {
                node_cancel_terminate_execution(runContext.setup);
                node_purge_event_loop(runContext.setup);
                test_state.passed = false;
            }
            watchdog_disarm(*watchdog);
            if test_state.passed {
                print("PASS %", info.full_name);
                passed += 1;
            } else {
                print("FAILED %", info.full_name);
                failed += 1;
            }
            duration := current_time_monotonic() - start;
            if (to_seconds(duration) > 0) {
                print(" taking %s\n", to_seconds(duration));
            } else if (to_milliseconds(duration) > 0) {
                print(" taking %ms\n", to_milliseconds(duration));
            } else if (to_microseconds(duration) > 0) {
                print(" taking %μs\n", to_microseconds(duration));
            }
        }
    }
    visit_files(
        dir, 
        recursive=true, 
        cast(*void) *runContext, 
        file_visitor,
    );

    print("passed: %, failed: %\n", passed, failed);
    if failed exit(1);
}
