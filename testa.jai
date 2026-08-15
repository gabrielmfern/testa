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
    start: Apollo_Time;
    promise: *v8_promise;
    // if the test was triggered by uv, so the event loop spinning, it means we
    // can't spin the event loop from inside the test itself, and therefore
    // can't block other tests from running while running an async test, and
    // instead we have to collect them from this "gulp" of the event loop, and
    // then iterate through them running them ourselves, we process the tests
    // on our side in the file visitor where we can do this.
    //
    // we can't run the event loop from the event loop because uv_run is not
    // reentrant: http://docs.libuv.org/en/v1.x/loop.html#c.uv_run
    triggered_by_uv: bool;

    // triggered by calling test.fails
    expected_to_fail: bool;

    breadcrumb: [..]string;
};

test_state: TestState;
watchdog: Watchdog;

Quiesce :: struct {
    ns: napi_value;
    checkpoint: napi_value;
    report: napi_value;
    quiesce: napi_value;
}
quiesce: Quiesce;

quiesce_init :: () {
    global: napi_value;
    process: napi_value;
    napi_get_global(napi_env_instance, *global);
    napi_get_named_property(napi_env_instance, global, "process".data, *process);
    napi_get_named_property(napi_env_instance, process, "quiesce".data, *quiesce.ns);
    napi_get_named_property(napi_env_instance, quiesce.ns, "checkpoint".data, *quiesce.checkpoint);
    napi_get_named_property(napi_env_instance, quiesce.ns, "report".data, *quiesce.report);
    napi_get_named_property(napi_env_instance, quiesce.ns, "quiesce".data, *quiesce.quiesce);
}

quiesce_checkpoint :: () -> napi_value {
    cp: napi_value;
    napi_call_function(napi_env_instance, quiesce.ns, quiesce.checkpoint, 0, null, *cp);
    return cp;
}

quiesce_run :: (cp: napi_value) {
    result: napi_value;
    napi_call_function(napi_env_instance, quiesce.ns, quiesce.quiesce, 1, *cp, *result);
}

quiesce_drain :: (cp: napi_value) {
    quiesce_run(cp);
    watchdog_arm(*watchdog, 2000);
    while node_spin_event_loop_once(node_setup) {
        if atomic_load(*watchdog.fired) {
            node_cancel_terminate_execution(node_setup);
            break;
        }
    }
    watchdog_disarm(*watchdog);
}

napi_string :: (value: napi_value) -> string {
    size: u64;
    napi_get_value_string_utf8(napi_env_instance, value, null, 0, *size);
    str := talloc_string(xx (size + 1));
    napi_get_value_string_utf8(napi_env_instance, value, str.data, size + 1, null);
    str.count = xx size;
    return str;
}

Leak :: struct {
    type: string;
    async_id: s64;
}

quiesce_report :: (cp: napi_value) -> [..]Leak {
    leaks: [..]Leak;
    result: napi_value;
    napi_call_function(napi_env_instance, quiesce.ns, quiesce.report, 1, *cp, *result);

    resources: napi_value;
    napi_get_named_property(napi_env_instance, result, "resources".data, *resources);
    count: u32;
    napi_get_array_length(napi_env_instance, resources, *count);
    for 0..cast(s64) count - 1 {
        item, type, async_id: napi_value;
        napi_get_element(napi_env_instance, resources, xx it, *item);
        napi_get_named_property(napi_env_instance, item, "type".data, *type);
        napi_get_named_property(napi_env_instance, item, "asyncId".data, *async_id);
        leak: Leak;
        leak.type = napi_string(type);
        napi_get_value_int64(napi_env_instance, async_id, *leak.async_id);
        array_add(*leaks, leak);
    }

    timers: napi_value;
    napi_get_named_property(napi_env_instance, result, "timers".data, *timers);
    for field: string.["Timeout", "Immediate"] {
        list: napi_value;
        n: u32;
        napi_get_named_property(napi_env_instance, timers, ifx field == "Timeout" then "timeouts".data else "immediates".data, *list);
        napi_get_array_length(napi_env_instance, list, *n);
        for 0..cast(s64) n - 1 {
            item: napi_value;
            napi_get_element(napi_env_instance, list, xx it, *item);
            leak: Leak;
            leak.type = field;
            napi_get_value_int64(napi_env_instance, item, *leak.async_id);
            array_add(*leaks, leak);
        }
    }
    return leaks;
}

cwd_prefix: string;

frame_location :: (frame: string) -> string {
    loc := frame;
    open := find_index_from_right(frame, #char "(");
    if open >= 0 {
        loc = slice(frame, open + 1, frame.count - open - 2);
    } else if begins_with(loc, "at ") {
        loc = slice(loc, 3, loc.count - 3);
    }
    if begins_with(loc, "file://") loc = slice(loc, 7, loc.count - 7);
    if cwd_prefix.count && begins_with(loc, cwd_prefix) loc = slice(loc, cwd_prefix.count, loc.count - cwd_prefix.count);
    return loc;
}

leak_origin :: (leak: Leak) -> origin: string, internal: bool {
    if leak.async_id < 0 return "", false;
    global, fn, arg, result: napi_value;
    napi_get_global(napi_env_instance, *global);
    napi_get_named_property(napi_env_instance, global, "__testa_stack".data, *fn);
    napi_create_int64(napi_env_instance, leak.async_id, *arg);
    napi_call_function(napi_env_instance, global, fn, 1, *arg, *result);
    stack := napi_string(result);
    // TODO: add a --verbose flag that doesn't filter the node internal leaks
    first_internal := "";
    for line: split(stack, "\n") {
        if !contains(line, "    at ") continue;
        if contains(line, "__bootstrap__") || contains(line, "node:internal/async_hooks") continue;
        if contains(line, "(node:") || contains(line, "at node:") {
            if !first_internal.count first_internal = frame_location(trim(line));
            continue;
        }
        return frame_location(trim(line)), false;
    }
    return first_internal, first_internal.count > 0;
}

print_leaks :: (header: string, leaks: []Leak) {
    log_error("%", header);
    internal := 0;
    for leaks {
        origin, is_internal := leak_origin(it);
        if is_internal { internal += 1; continue; }
        if origin.count log_error("  % at %", it.type, origin);
        else            log_error("  %", it.type);
    }
    if internal log_error("  % from inside node itself (e.g. fetch keep-alive)", internal);
}

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

kPending: s32 = 0; 
kFulfilled: s32 = 1; 
kRejected: s32 = 2;

test_fails :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    test_state.expected_to_fail = true;
    defer test_state.expected_to_fail = false;
    return test(env, info);
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
            argc: u64 = 3;
            argv: [3]napi_value;
            this: napi_value;
            napi_get_cb_info(env, info, *argc, argv.data, *this, null);
            // TODO: validate types for incoming parameters here
            test_name := argv[0];
            callback := argv[1];
            timeout_ms_value := argv[2];

            test_name_string_size: u64;
            napi_get_value_string_utf8(env, test_name, null, 0, *test_name_string_size);
            test_name_string: string = talloc_string(xx (test_name_string_size + 1));
            napi_get_value_string_utf8(env, test_name, test_name_string.data, test_name_string_size + 1, null);
            test_name_string.count = xx test_name_string_size;

            timeout_ms_value_type: napi_valuetype;
            napi_typeof(napi_env_instance, timeout_ms_value, *timeout_ms_value_type);
            timeout_ms: s64;
            if timeout_ms_value_type == .napi_undefined || timeout_ms_value_type == .napi_null {
                timeout_ms = 5000;
            } else {
                napi_get_value_int64(napi_env_instance, timeout_ms_value, *timeout_ms);
            }

            pending: PendingTest;
            pending.name = copy_string(test_name_string);
            pending.timeout_ms = timeout_ms;
            pending.expected_to_fail = test_state.expected_to_fail;
            napi_create_reference(env, callback, 1, *pending.callback);
            napi_create_reference(env, this, 1, *pending.this);
            array_add(*pending_tests, pending);
        }
    }
    return null;
}

PendingTest :: struct {
    name: string;
    timeout_ms: s64;
    expected_to_fail: bool;
    callback: napi_ref;
    this: napi_ref;
}
pending_tests: [..]PendingTest;

run_test :: (pending: PendingTest) {
    env := napi_env_instance;
    test_name_string := pending.name;
    timeout_ms := pending.timeout_ms;
    test_state.start = current_time_monotonic();
    test_state.passed = true;
    test_state.expected_to_fail = pending.expected_to_fail;
    defer test_state.expected_to_fail = false;
    array_add(*test_state.breadcrumb, test_name_string);
    defer array_unordered_remove_by_index(*test_state.breadcrumb, test_state.breadcrumb.count - 1);

    callback, this: napi_value;
    napi_get_reference_value(env, pending.callback, *callback);
    napi_get_reference_value(env, pending.this, *this);
    defer napi_delete_reference(env, pending.callback);
    defer napi_delete_reference(env, pending.this);

    {
        {
            cp := quiesce_checkpoint();
            watchdog_arm(*watchdog, timeout_ms);
            test_return: napi_value;
            napi_call_function(env, this, callback, 0, null, *test_return);
            if atomic_load(*watchdog.fired) {
                node_cancel_terminate_execution(node_setup);
                test_state.passed = false;
            }
            does_test_return_a_promise: bool;
            napi_is_promise(napi_env_instance, test_return, *does_test_return_a_promise);
            defer if does_test_return_a_promise {
                v8_promise_unref(test_state.promise);
            }

            promise_state: s32;
            if does_test_return_a_promise {
                test_state.promise = v8_promise_ref(test_return);
                while node_spin_event_loop_once(node_setup) {
                    promise_state = v8_promise_state(test_state.promise);
                    if promise_state == kFulfilled || promise_state == kRejected {
                        // TODO: in this error message, explain what kind of things can leave the loop busy.
                        log_error("The test promise finished, but the event loop was still busy.");
                        break;
                    }
                    if atomic_load(*watchdog.fired) {
                        log_error("Timeout of %ms was reached, killing async work beacuse of it.", timeout_ms);
                        // TODO: add an explicit error message for when the test timeouts, currently it just fails.
                        test_state.passed = false;
                        break;
                    }
                }
                promise_state = v8_promise_state(test_state.promise);
                if atomic_load(*watchdog.fired) {
                    node_cancel_terminate_execution(node_setup);
                    if promise_state == kPending {
                        test_state.passed = false;
                    }
                }
            }
            watchdog_disarm(*watchdog);

            if promise_state == kRejected {
                test_state.passed = false;
            }

            // TODO: store this exception and show it later once all tests are done. we
            // should also do the same for the stdout/stderr output from the test, too.
            exception: napi_value;
            if napi_get_and_clear_last_exception(napi_env_instance, *exception) != .ok {
                log_error("Could not get and clear exception from last test");
                return;
            } else if (promise_state == kRejected) {
                exception = v8_promise_result(test_state.promise);
                // can this exception really be undefined? if it can't, there's
                // no point in setting passed to false here, too
                test_state.passed = false;
            }
            exception_type: napi_valuetype;
            napi_typeof(napi_env_instance, exception, *exception_type);
            if exception_type != .napi_undefined && exception_type != .napi_null {
                message: napi_value;
                napi_get_named_property(napi_env_instance, exception, "message".data, *message);
                length: u64;
                napi_get_value_string_utf8(napi_env_instance, message, null, 0, *length);
                buf := talloc(cast(s64) length + 1);
                napi_get_value_string_utf8(napi_env_instance, message, buf, length + 1, null);
                log_error("there was an exception: %", to_string(cast(*u8) buf, xx length));
                test_state.passed = false;
            }

            test_path_length: s64 = 0;
            separator := " > ";
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
                if it_index + 1 < test_state.breadcrumb.count {
                    memcpy(data, separator.data, separator.count);
                    data += separator.count;
                }
            }

            if test_state.expected_to_fail {
                test_state.passed = !test_state.passed;
            }

            if test_state.passed {
                print("PASS %", test_path);
                passed += 1;
            } else {
                print("FAILED %", test_path);
                failed += 1;
            }
            duration := current_time_monotonic() - test_state.start;
            if (to_seconds(duration) > 0) {
                print(" taking %s\n", to_seconds(duration));
            } else if (to_milliseconds(duration) > 0) {
                print(" taking %ms\n", to_milliseconds(duration));
            } else if (to_microseconds(duration) > 0) {
                print(" taking %μs\n", to_microseconds(duration));
            }

            left_behind := quiesce_report(cp);
            if left_behind.count {
                // TODO: fail the test when this happens under some kind of strict mode 
                print_leaks(tprint("Async work left behind by \"%\":", test_name_string), left_behind);
            }
            quiesce_drain(cp);
            stuck := quiesce_report(cp);
            if stuck.count {
                print_leaks(tprint("Async work left behind by \"%\" that could not be cleaned up:", test_name_string), stuck);
            }
        }
    }
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

        test_fails_fn: napi_value;
        napi_create_function(env, "fails".data, "fails".count, test_fails, null, *test_fails_fn);
        napi_set_named_property(env, test_fn, "fails".data, test_fails_fn);
        napi_set_named_property(env, test_fn, "failing".data, test_fails_fn);

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
    lock(*w.mutex);
    w.deadline_ms = to_milliseconds(current_time_monotonic()) + timeout_ms;
    atomic_store(*w.fired, false);
    unlock(*w.mutex);
    signal(*w.wake);
}

watchdog_disarm :: (w: *Watchdog) {
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
                node_stop_event_loop(w.node_setup);
                w.deadline_ms = 0;
                atomic_store(*w.fired, true);
                unlock(*w.mutex);
            } else {
                unlock(*w.mutex);
                wait_for(*w.wake, xx remaining);
            }
        } else {
            unlock(*w.mutex);
        }

        if w.deadline_ms == 0 {
            wait_for(*w.wake, -1);
        }
    }

    return 0;
}

main :: () {
    callback_ctx = context;
    cwd_prefix = tprint("%/", get_working_directory());
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
    quiesce_init();

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
        run_context := cast(*RunContext) user_data;
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

            array_add(*test_state.breadcrumb, info.full_name);
            defer {
                // we should only have the test filename in the breadcrumb here
                assert(test_state.breadcrumb.count == 1);
                array_unordered_remove_by_index(*test_state.breadcrumb, 0);
            }

            cp := quiesce_checkpoint();
            defer {
                quiesce_drain(cp);
                leaks := quiesce_report(cp);
                if leaks.count {
                    print_leaks(tprint("Could not drain async work after %:", info.full_name), leaks);
                }
            }

            napi_create_string_utf8(napi_env_instance, absolute.data, cast(u64) absolute.count, *run_context.arg);
            napi_call_function(
                napi_env_instance, 
                run_context.global, 
                run_context.fn, 
                1, 
                *run_context.arg, 
                *run_context.result
            );
            node_perform_microtask_checkpoint(node_setup);

            run_promise := v8_promise_ref(run_context.result);
            defer v8_promise_unref(run_promise);
            while v8_promise_state(run_promise) == kPending && node_spin_event_loop_once(node_setup) {}
            if v8_promise_state(run_promise) == kRejected {
                log_error("Failed to load %", info.full_name);
                return;
            }

            // though I hate the fact that we're collecting to run, this is
            // required if we want to provide a good experience to users, so
            // the performance cost should not be relevant towards that in this
            // case. 
            // 
            // in the future, we will have an API for defining tests that
            // does not use this stupid callback pattern for various reasons,
            // and this is one of the things we would not have to do without
            // it.
            for pending_tests run_test(it);
            array_reset(*pending_tests);
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
