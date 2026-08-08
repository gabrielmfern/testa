#import "Basic";
#import "String";
#import "File";
#import "Thread";
#import "File_Utilities";

#if OS == .MACOS {
    #load "napi-macos.jai";
} else #if OS == .LINUX {
    #load "napi-linux.jai";
}

callback_ctx: #Context;

napi_env_instance: napi_env;
node_env: *node_environment;
node_setup: *node_common_environment_setup;

passed := 0;
failed := 0;

TestState :: struct {
    passed: bool;
    breadcrumb: [..]string;
};

test_state: TestState;
watchdog: Watchdog;

Compiler :: #import "Compiler";

DEBUG :: #run Compiler.get_build_options().array_bounds_check == .ON;

log_debug :: (format: string, args: .. Any, loc := #caller_location) {
  #if DEBUG  log(format, ..args, loc = loc);
}

to_be :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context callback_ctx {
        assert(test_state.breadcrumb.count > 0);

        argc: u64 = 1;
        expected: napi_value;
        napi_get_cb_info(env, info, *argc, *expected, null, null);

        actual: napi_value;
        napi_get_named_property(env, matcher, "actual".data, *actual);
        equal: bool;
        napi_strict_equals(env, actual, expected, *equal);
        // TODO: should we be throwing an exception here instead? if I use an
        // exception we can't explore a better pattern than the test closure
        // thing, so I think we should do our best to shy away from that
        // pattern
        if !equal {
            test_state.passed = false;
        }
    }
    return null;
}

Assertion :: struct {
    name: string;
    proc: #type (env: napi_env, info: napi_callback_info) -> napi_value #c_call;
}

assertions :: Assertion.[
    .{ "toBe", to_be },
];

matcher: napi_value;

expect :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context callback_ctx {
        argc: u64 = 1;
        actual: napi_value;
        // TODO: right now all of the calls to napi are not handling the
        // possible errors that can return, we should be handling them
        napi_get_cb_info(env, info, *argc, *actual, null, null);
        napi_set_named_property(env, matcher, "actual".data, actual);
    }
    return matcher;
}

// TODO: we should suppot having callbacks to be compatible with vitest, but we
// should find something better because these callbacks copy memory all aruond
// which is not ideal.
test :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context callback_ctx {
        // we expect it to be one only for now since we don't have any test
        // scopes such as describe
        if test_state.breadcrumb.count > 1 {
            napi_throw_error(env, null, "nested test() calls are not supported".data);
        } else {
            start := current_time_monotonic();

            argc: u64 = 2;
            argv: [2]napi_value;
            this: napi_value;
            napi_get_cb_info(env, info, *argc, argv.data, *this, null);
            // TODO: validate types for incoming parameters here
            test_name := argv[0];
            callback := argv[1];

            test_name_string_size: u64;
            napi_get_value_string_utf8(env, test_name, null, 0, *test_name_string_size);
            test_name_string: string = alloc_string(xx test_name_string_size);
            defer free(cast(*void) test_name_string.data);
            napi_get_value_string_utf8(env, test_name, test_name_string.data, 0, *test_name_string_size);

            test_state.passed = true;
            array_add(*test_state.breadcrumb, test_name_string);
            defer array_unordered_remove_by_index(*test_state.breadcrumb, test_state.breadcrumb.count - 1);

            watchdog_arm(*watchdog, 5000);
            // we need to handle promises here
            napi_call_function(env, this, callback, 0, null, null);
            if atomic_load(*watchdog.fired) {
                node_cancel_terminate_execution(node_setup);
                test_state.passed = false;
            }
            watchdog_disarm(*watchdog);

            // TODO: store this exception and show it later once the tests are done. 
            // we should also do the same for the stdout/stderr output from the test, too.
            result: napi_value;
            if napi_get_and_clear_last_exception(napi_env_instance, *result) != .ok {
                log_error("Could not get and clear exception from last test run");
                return null;
            }
            result_type: napi_valuetype;
            napi_typeof(napi_env_instance, result, *result_type);
            if result_type != .napi_undefined {
                message: napi_value;
                napi_get_named_property(napi_env_instance, result, "message".data, *message);
                length: u64;
                napi_get_value_string_utf8(napi_env_instance, message, null, 0, *length);
                buf := talloc(cast(s64) length + 1);
                napi_get_value_string_utf8(napi_env_instance, message, buf, length + 1, null);
                log_error("there was an exception: %", to_string(cast(*u8) buf, xx length));
                test_state.passed = false;
            }

            test_path_length: s64 = 0;
            separator = " > ";
            for test_state.breadcrumb {
                test_path_length += it.count;
                if it_index + 1 < test_state.breadcrumb.count {
                    test_path_length += separator.count;
                }
            }
            test_path := talloc_string(test_path_length);
            data := test_path.data;
            for test_state.breadcrumb {
                memcpy(data, it.data, it.count);
                data += it.count;
                memcpy(data, separator.data, separator.count);
                data += separator.count;
            }

            if test_state.passed {
                print("PASS %", test_path);
                passed += 1;
            } else {
                print("FAILED %", test_path);
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
    return null;
}

register :: (env: napi_env, exports: napi_value) -> napi_value #c_call {
    push_context callback_ctx {
        napi_env_instance = env;
        global: napi_value;
        napi_get_global(env, *global);

        expect_fn: napi_value;
        napi_create_function(env, "expect".data, "expect".count, expect, null, *expect_fn);
        napi_set_named_property(env, global, "expect".data, expect_fn);

        test_fn: napi_value;
        napi_create_function(env, "test".data, "test".count, test, null, *test_fn);
        napi_set_named_property(env, global, "test".data, test_fn);
    }
    return exports;
}

BOOTSTRAP :: #run read_entire_file("__bootstrap__.mjs", zero_terminated=true);

Watchdog :: struct {
    thread: Thread;
    wake: Semaphore;
    mutex: Mutex;

    // we store this in the struct because it's going to the watchdog thread
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
    atomic_store(*w.fired, false);
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

    node_setup = node_common_environment_setup_create(platform, init);
    if !node_setup exit(1);
    defer node_common_environment_setup_destroy(node_setup);
    node_env = node_common_environment_setup_env(node_setup);
    defer node_stop(node_env);

    watchdog_init(*watchdog, node_setup);
    defer watchdog_shutdown(*watchdog);

    scope := v8_scope_open(node_setup);
    defer v8_scope_close(scope);
    node_add_linked_binding(node_env, "testa".data, register);
    status := node_load_environment_module(node_env, BOOTSTRAP.data, "file:///__bootstrap__.mjs".data);
    if status == 1 {
        log_error("Could not load environment with bootstrap script");
        return;
    }
    assert(napi_env_instance != null);
    node_snapshot_event_loop(node_setup);

    napi_create_object(napi_env_instance, *matcher);
    for assertions {
        fn: napi_value;
        napi_create_function(napi_env_instance, it.name.data, xx it.name.count, it.proc, null, *fn);
        napi_set_named_property(napi_env_instance, matcher, it.name.data, fn);
    }

    RunContext :: struct {
        global: napi_value;
        fn: napi_value;
        arg: napi_value;
        result: napi_value;
    }

    runContext : RunContext;
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
            test_state.passed = true;
            array_add(*test_state.breadcrumb, info.full_name);
            defer {
                // we should only have the test filename in the breadcrumb here
                assert(test_state.breadcrumb.count == 1);
                array_unordered_remove_by_index(*test_state.breadcrumb, 0);
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
            while node_spin_event_loop_once(node_setup) {
                if atomic_load(*watchdog.fired) {
                    log_debug("WATCHDOG: breaking spin event loop because it took too long, and watchdog fired");
                    break;
                }
            }
            if atomic_load(*watchdog.fired) {
                node_cancel_terminate_execution(node_setup);
                node_purge_event_loop(node_setup);
                test_state.passed = false;
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
