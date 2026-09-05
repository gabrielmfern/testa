#if DEBUG {
    #import "Basic"()(MEMORY_DEBUGGER=true);
} else {
    #import "Basic";
}
#import "String";
#import "File";
#import "Pool";
#import "Thread";
#import "File_Utilities";

#if OS == .WINDOWS {
    #load "napi-windows.jai";
} else #if OS == .MACOS {
    #load "napi-macos.jai";
} else #if OS == .LINUX {
    #load "napi-linux.jai";
}

test_pool: Pool;
test_context: #Context;

///////////////////////////////////////////////////////////////////////////////
// node

napi_env_instance: napi_env;
napi_global: napi_value;
napi_process: napi_value;
napi_tick_callback_fn: napi_value;
url_prototype: napi_value;
temporal_equals_prototypes: [7]napi_value;
temporal_duration_prototype: napi_value;
noop_fn: napi_value;
testa_run_fn: napi_value;
testa_inspect_fn: napi_value;
node_env: *node_environment;
node_setup: *node_common_environment_setup;

kPending: s32 = 0;
kFulfilled: s32 = 1;
kRejected: s32 = 2;

napi_check :: (status: napi_status, loc := #caller_location) {
    if status != .ok {
        info: *napi_extended_error_info;
        if napi_get_last_error_info(napi_env_instance, *info) == .ok {
            assert(false, "napi % (%)", status, to_string(info.error_message), loc = loc);
        } else {
            assert(false, "failed to get error info for napi error %", status);
        }
    }
}

napi_try :: (status: napi_status) #expand {
    if status != .ok {
      if status != .pending_exception {
          info: *napi_extended_error_info;
          napi_check(napi_get_last_error_info(napi_env_instance, *info));
          napi_check(napi_throw_error(napi_env_instance, null, info.error_message));
      }
      `return null;
    }
}

// performant version of Object.is
object_is :: (env: napi_env, a: napi_value, b: napi_value) -> bool {
  same: bool;
  napi_check(napi_strict_equals(env, a, b, *same));
  a_type, b_type: napi_valuetype;
  napi_check(napi_typeof(env, a, *a_type));
  napi_check(napi_typeof(env, b, *b_type));
  if a_type == .napi_number && b_type == .napi_number {
      x, y: float64;
      napi_check(napi_get_value_double(env, a, *x));
      napi_check(napi_get_value_double(env, b, *y));
      if same && x == 0 {
          same = (1 / x) == (1 / y);
      } else if !same {
          same = !(x == x) && !(y == y);
      }
  }
  return same;
}

Eq_Frame :: struct {
    a, b: napi_value;
    parent: *Eq_Frame;
}

deep_equal :: (env: napi_env, a: napi_value, b: napi_value, parent: *Eq_Frame) -> bool {
    try :: (status: napi_status) #expand {
        if status != .ok {
            if status != .pending_exception {
                info: *napi_extended_error_info;
                napi_check(napi_get_last_error_info(napi_env_instance, *info));
                napi_check(napi_throw_error(napi_env_instance, null, info.error_message));
            }
            `return false;
        }
    }

    if object_is(env, a, b) {
        return true;
    }

    kind := v8_value_kind_of(a);
    if kind != v8_value_kind_of(b) {
        return false;
    }

    if kind == {
        case .PRIMITIVE; #through;
        case .FUNCTION;
            return false;
        case .NUMBER_OBJECT;
            x := v8_number_object_value(a);
            y := v8_number_object_value(b);
            if x == y {
                return x != 0 || (1 / x) == (1 / y);
            }
            return !(x == x) && !(y == y);
        case .STRING_OBJECT;
            same: bool;
            try(napi_strict_equals(env, v8_string_object_value(a), v8_string_object_value(b), *same));
            return same;
        case .BOOLEAN_OBJECT;
            return v8_boolean_object_value(a) == v8_boolean_object_value(b);
        case .DATE;
            x, y: float64;
            try(napi_get_date_value(env, a, *x));
            try(napi_get_date_value(env, b, *y));
            return x == y || (!(x == x) && !(y == y));
        case .REGEXP;
            a_source, b_source, a_flags, b_flags: napi_value;
            try(napi_get_named_property(env, a, "source", *a_source));
            try(napi_get_named_property(env, b, "source", *b_source));
            try(napi_get_named_property(env, a, "flags", *a_flags));
            try(napi_get_named_property(env, b, "flags", *b_flags));
            same_source, same_flags: bool;
            try(napi_strict_equals(env, a_source, b_source, *same_source));
            try(napi_strict_equals(env, a_flags, b_flags, *same_flags));
            return same_source && same_flags;
    }

    ancestor := parent;
    while ancestor {
        if v8_same_object(ancestor.a, a) {
            return v8_same_object(ancestor.b, b) != 0;
        }
        if v8_same_object(ancestor.b, b) {
            return false;
        }
        ancestor = ancestor.parent;
    }
    frame := Eq_Frame.{a, b, parent};

    scope: napi_handle_scope;
    try(napi_open_handle_scope(env, *scope));
    defer napi_check(napi_close_handle_scope(env, scope));

    if kind == .ARRAY {
        a_length, b_length: u32;
        try(napi_get_array_length(env, a, *a_length));
        try(napi_get_array_length(env, b, *b_length));
        if a_length != b_length {
            return false;
        }
        for 0..cast(s64) a_length - 1 {
            a_element, b_element: napi_value;
            try(napi_get_element(env, a, xx it, *a_element));
            try(napi_get_element(env, b, xx it, *b_element));
            if !deep_equal(env, a_element, b_element, *frame) {
                return false;
            }
        }
        return true;
    }

    if kind == .OBJECT {
        a_prototype, b_prototype: napi_value;
        try(napi_get_prototype(env, a, *a_prototype));
        try(napi_get_prototype(env, b, *b_prototype));
        if v8_same_object(a_prototype, b_prototype) {
            if v8_same_object(a_prototype, url_prototype) {
                a_href, b_href: napi_value;
                try(napi_get_named_property(env, a, "href", *a_href));
                try(napi_get_named_property(env, b, "href", *b_href));
                same: bool;
                try(napi_strict_equals(env, a_href, b_href, *same));
                return same;
            }
            if temporal_duration_prototype {
                for temporal_equals_prototypes {
                    if v8_same_object(a_prototype, it) {
                        equals_fn, result: napi_value;
                        try(napi_get_named_property(env, a, "equals", *equals_fn));
                        try(napi_call_function(env, a, equals_fn, 1, *b, *result));
                        equal: bool;
                        try(napi_get_value_bool(env, result, *equal));
                        return equal;
                    }
                }
                if v8_same_object(a_prototype, temporal_duration_prototype) {
                    a_string, b_string: napi_value;
                    try(napi_coerce_to_string(env, a, *a_string));
                    try(napi_coerce_to_string(env, b, *b_string));
                    same: bool;
                    try(napi_strict_equals(env, a_string, b_string, *same));
                    return same;
                }
            }
        }
    }

    if kind == .ERROR {
        for string.["name", "message"] {
            a_field, b_field: napi_value;
            try(napi_get_named_property(env, a, it.data, *a_field));
            try(napi_get_named_property(env, b, it.data, *b_field));
            same: bool;
            try(napi_strict_equals(env, a_field, b_field, *same));
            if !same {
                return false;
            }
        }
        for string.["cause", "errors"] {
            b_field: napi_value;
            try(napi_get_named_property(env, b, it.data, *b_field));
            b_type: napi_valuetype;
            try(napi_typeof(env, b_field, *b_type));
            if b_type != .napi_undefined {
                a_field: napi_value;
                try(napi_get_named_property(env, a, it.data, *a_field));
                if !deep_equal(env, a_field, b_field, *frame) {
                    return false;
                }
            }
        }
    }

    a_keys, b_keys: napi_value;
    try(napi_get_all_property_names(env, a, .napi_key_own_only, .napi_key_enumerable, .napi_key_numbers_to_strings, *a_keys));
    try(napi_get_all_property_names(env, b, .napi_key_own_only, .napi_key_enumerable, .napi_key_numbers_to_strings, *b_keys));

    a_count, b_count: u32;
    try(napi_get_array_length(env, a_keys, *a_count));
    try(napi_get_array_length(env, b_keys, *b_count));

    b_defined := 0;
    for 0..cast(s64) b_count - 1 {
        key, value: napi_value;
        try(napi_get_element(env, b_keys, xx it, *key));
        try(napi_get_property(env, b, key, *value));
        type: napi_valuetype;
        try(napi_typeof(env, value, *type));
        if type != .napi_undefined {
            b_defined += 1;
        }
    }

    a_defined := 0;
    for 0..cast(s64) a_count - 1 {
        key, a_value, b_value: napi_value;
        try(napi_get_element(env, a_keys, xx it, *key));
        try(napi_get_property(env, a, key, *a_value));
        a_type: napi_valuetype;
        try(napi_typeof(env, a_value, *a_type));
        if a_type == .napi_undefined {
            continue;
        }
        a_defined += 1;
        if a_defined > b_defined {
            return false;
        }
        try(napi_get_property(env, b, key, *b_value));
        b_type: napi_valuetype;
        try(napi_typeof(env, b_value, *b_type));
        if b_type == .napi_undefined {
            return false;
        }
        b_has_key: bool;
        try(napi_has_own_property(env, b, key, *b_has_key));
        if !b_has_key {
            return false;
        }
        if !deep_equal(env, a_value, b_value, *frame) {
            return false;
        }
    }
    return a_defined == b_defined;
}

string_from_napi_value :: (value: napi_value) -> string {
    size: u64;
    napi_check(napi_get_value_string_utf8(napi_env_instance, value, null, 0, *size));
    str := alloc_string(xx (size + 1));
    napi_check(napi_get_value_string_utf8(napi_env_instance, value, str.data, size + 1, null));
    str.count = xx size;
    return str;
}

noop :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    return null;
}

clear_last_exception :: () -> napi_value {
    exception: napi_value;
    napi_check(napi_get_and_clear_last_exception(napi_env_instance, *exception));
    type: napi_valuetype;
    napi_check(napi_typeof(napi_env_instance, exception, *type));
    if type == .napi_undefined {
        return null;
    }
    return exception;
}

running_test: bool;
uncaught_exception: napi_ref;
on_uncaught_exception :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        error: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *error, null, null));

        if !running_test {
            set_print_color(.red);
            print("✘ ");
            reset_print_styling();
            print_test_path();
            print("\n");
            print_test_exception(error);
            failed += 1;
        } else if uncaught_exception {
            print_test_exception(error);
        } else {
            napi_try(napi_create_reference(env, error, 1, *uncaught_exception));
        }
    }
    return null;
}

call_testing_function :: (
    callback: napi_value, 
    this: napi_value, 
    timeout_ms: s64
) -> success: bool, exception: napi_value {
    success := true;
    running_test = true;
    defer running_test = false;

    watchdog_arm(*watchdog, timeout_ms);
    result: napi_value;

    exception: napi_value;
    does_it_return_a_promise: bool;
    promise_state: s32;

    napi_call_function(napi_env_instance, this, callback, 0, null, *result);
    if atomic_load(*interruption) != .NONE {
        node_cancel_terminate_execution(node_setup);
        node_clear_async_id_stack(node_setup);
        success = false;
    }

    exception = clear_last_exception();

    if result != null {
        napi_check(napi_is_promise(napi_env_instance, result, *does_it_return_a_promise));
    } else {
        does_it_return_a_promise = false;
    }

    if does_it_return_a_promise {
        then_fn, ignored: napi_value;
        // this is left here so that node doesn't think that the exception for the Promise was not handled, throwing a noisy warning to the end-user
        napi_check(napi_get_named_property(napi_env_instance, result, "then".data, *then_fn));
        handlers := napi_value.[noop_fn, noop_fn];
        napi_check(napi_call_function(napi_env_instance, result, then_fn, 2, handlers.data, *ignored));
    }

    tick_callback_result: napi_value;
    tick_status := napi_call_function(napi_env_instance, napi_process, napi_tick_callback_fn, 0, null, *tick_callback_result);
    if atomic_load(*interruption) != .NONE {
        node_cancel_terminate_execution(node_setup);
        node_clear_async_id_stack(node_setup);
        success = false;
    } else if tick_status == .pending_exception {
        node_clear_async_id_stack(node_setup);
    }

    tick_exception := clear_last_exception();
    if !exception {
        exception = tick_exception;
    }

    promise: *v8_promise;
    defer if does_it_return_a_promise {
        v8_promise_unref(promise);
    }
    if does_it_return_a_promise {
        promise = v8_promise_ref(result);
        while node_spin_event_loop_once(node_setup) {
            promise_state = v8_promise_state(promise);
            if promise_state == kFulfilled || promise_state == kRejected {
                // TODO: in this error message, explain what kind of things can leave the loop busy.
                // print("  The test promise finished, but the event loop was still busy.\n");
                break;
            }
            if atomic_load(*interruption) != .NONE {
                // print("  Timeout of %ms was reached, killing async work because of it.\n", timeout_ms);
                // TODO: add an explicit error message for when the test times out, currently it just fails.
                success = false;
                break;
            }
        }
        promise_state = v8_promise_state(promise);
        if atomic_load(*interruption) != .NONE {
            node_cancel_terminate_execution(node_setup);
            node_clear_async_id_stack(node_setup);
            if promise_state == kPending {
                success = false;
            }
        }
    }
    watchdog_disarm(*watchdog);

    if (promise_state == kRejected) {
        exception = v8_promise_result(promise);
        success = false;
    }
    if !exception && uncaught_exception {
        napi_check(napi_get_reference_value(napi_env_instance, uncaught_exception, *exception));
        napi_check(napi_delete_reference(napi_env_instance, uncaught_exception));
        uncaught_exception = null;
    }
    if exception {
        success = false;
    }

    return success, exception;
}

///////////////////////////////////////////////////////////////////////////////
// program interruption 

InterruptionReason :: enum { NONE; TIMEOUT; SIGINT; }
interruption: InterruptionReason = .NONE;
stdout_is_tty: bool;

Watchdog :: struct {
    thread: Thread;
    wake: Semaphore;
    mutex: Mutex;

    // we store this in the struct because it's going to the watchdog thread
    node_setup: *node_common_environment_setup;

    deadline_ms: s64;
    // someone called watchdog_shutdown
    shutdown: bool;
}
watchdog: Watchdog;

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
    compare_and_swap(*interruption, .TIMEOUT, .NONE);
    unlock(*w.mutex);
    signal(*w.wake);
}

watchdog_disarm :: (w: *Watchdog) {
    lock(*w.mutex);
    w.deadline_ms = 0;
    compare_and_swap(*interruption, .TIMEOUT, .NONE);
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
                atomic_store(*interruption, .TIMEOUT);
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

///////////////////////////////////////////////////////////////////////////////
// leaks

Leak :: struct {
    type: string;
    async_id: s64;
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
    #if OS == .WINDOWS {
        // Windows file URLs look like file:///C:/dir/file, so after stripping "file://" we're left with
        // "/C:/dir/file"; cwd_prefix is built in that same shape. Drive letters may differ in case.
        if cwd_prefix.count && begins_with_nocase(loc, cwd_prefix) loc = slice(loc, cwd_prefix.count, loc.count - cwd_prefix.count);
    } else {
        if cwd_prefix.count && begins_with(loc, cwd_prefix) loc = slice(loc, cwd_prefix.count, loc.count - cwd_prefix.count);
    }
    return loc;
}

get_stack_trace_origin :: (stack: string) -> origin: string, internal: bool {
    first_internal := "";
    origin: string;
    for line: split(stack, "\n") {
        // TODO: --verbose (?) flag that doesn't filter node internal leaks
        if contains(line, "    at ") && 
        !contains(line, "__bootstrap__") && 
        !contains(line, "node:internal/async_hooks") && 
        !contains(line, "(node:") && 
        !contains(line, "at node:") {
            origin = line;
            break;
        } else if contains(line, "(node:") || contains(line, "at node:") {
            if (!first_internal.count) {
                first_internal = frame_location(trim(line));
            }
        }
    }
    if origin.count != 0 {
        return frame_location(trim(origin)), false;
    } else {
        return first_internal, first_internal.count > 0;
    }
}

print_leaks :: (builder: *String_Builder, leaks: []Leak) {
    internal := 0;
    for leaks {
        if it.async_id >= 0 {
            global, fn, arg, result: napi_value;
            napi_check(napi_get_global(napi_env_instance, *global));
            napi_check(napi_get_named_property(napi_env_instance, global, "__testa_stack".data, *fn));
            napi_check(napi_create_int64(napi_env_instance, it.async_id, *arg));
            napi_check(napi_call_function(napi_env_instance, global, fn, 1, *arg, *result));
            stack := string_from_napi_value(result);

            origin, is_internal := get_stack_trace_origin(stack);
            if is_internal { 
                internal += 1; 
            } else {
                print_to_builder(builder, "    % at %\n", it.type, origin);
            }
        } else {
            print_to_builder(builder, "    %\n", it.type);
        }
    }
    if internal {
        print_to_builder(builder, "    % from inside node itself\n", internal);
    }
}

quiesce_namespace: napi_value;

quiesce_checkpoint_fn: napi_value;
quiesce_checkpoint :: () -> napi_value {
    cp: napi_value;
    napi_try(napi_call_function(napi_env_instance, quiesce_namespace, quiesce_checkpoint_fn, 0, null, *cp));
    return cp;
}

quiesce_fn: napi_value;
quiesce_drain :: (cp: napi_value) {
    result: napi_value;
    napi_check(napi_call_function(napi_env_instance, quiesce_namespace, quiesce_fn, 1, *cp, *result));
    watchdog_arm(*watchdog, 2000);
    while node_spin_event_loop_once(node_setup) {
        if atomic_load(*interruption) != .NONE {
            node_cancel_terminate_execution(node_setup);
            node_clear_async_id_stack(node_setup);
            break;
        }
    }
    watchdog_disarm(*watchdog);
}

quiesce_report_fn: napi_value;
quiesce_report :: (leaks: *[..]Leak, cp: napi_value) {
    result: napi_value;
    napi_check(napi_call_function(napi_env_instance, quiesce_namespace, quiesce_report_fn, 1, *cp, *result));

    resources: napi_value;
    napi_check(napi_get_named_property(napi_env_instance, result, "resources".data, *resources));
    count: u32;
    napi_check(napi_get_array_length(napi_env_instance, resources, *count));
    for 0..cast(s64) count - 1 {
        item, type, async_id: napi_value;
        napi_check(napi_get_element(napi_env_instance, resources, xx it, *item));
        napi_check(napi_get_named_property(napi_env_instance, item, "type".data, *type));
        napi_check(napi_get_named_property(napi_env_instance, item, "asyncId".data, *async_id));
        leak: Leak;
        leak.type = string_from_napi_value(type);
        napi_check(napi_get_value_int64(napi_env_instance, async_id, *leak.async_id));
        array_add(leaks, leak);
    }

    timers: napi_value;
    napi_check(napi_get_named_property(napi_env_instance, result, "timers".data, *timers));
    for field: string.["Timeout", "Immediate"] {
        list: napi_value;
        n: u32;
        napi_check(napi_get_named_property(napi_env_instance, timers, ifx field == "Timeout" then "timeouts".data else "immediates".data, *list));
        napi_check(napi_get_array_length(napi_env_instance, list, *n));
        for 0..cast(s64) n - 1 {
            item: napi_value;
            napi_check(napi_get_element(napi_env_instance, list, xx it, *item));
            leak: Leak;
            leak.type = field;
            napi_check(napi_get_value_int64(napi_env_instance, item, *leak.async_id));
            array_add(leaks, leak);
        }
    }
}

///////////////////////////////////////////////////////////////////////////////
// terminal work

Color :: enum {
    black; red; green; yellow; blue; cyan; white;

    brightBlack; brightRed; brightGreen; brightYellow; brightBlue; brightCyan; brightWhite;
}

colors :: string.[
    "\e[30m", "\e[31m", "\e[32m", "\e[33m", "\e[34m", "\e[35m", "\e[36m", "\e[37m",

    "\e[90m", "\e[91m", "\e[92m", "\e[93m", "\e[94m", "\e[95m", "\e[96m", "\e[97m"
];

set_print_color :: (color: Color) {
    print(colors[xx color]);
}

set_print_bold :: () {
    print("\e[1m");
}

set_print_dim :: () {
    print("\e[2m");
}

reset_print_styling :: () {
    print("\e[0m");
}

ProcessOutputCapture :: struct {
    // TODO: should we break this into two different builders, one for stderr
    // and another for stdout?
    builder: String_Builder;
    process: napi_value;
    next_tick: napi_value;
    stdout: napi_value;
    stderr: napi_value;
    original_stdout_write: napi_value;
    original_stderr_write: napi_value;
}

capture_process_output :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 3;
        argv: [3]napi_value;
        capture: *ProcessOutputCapture;
        napi_try(napi_get_cb_info(env, info, *argc, argv.data, null, cast(**void) *capture));

        chunk := argv[0];
        type: napi_valuetype;
        napi_try(napi_typeof(env, chunk, *type));
        if type == .napi_string {
            append(*capture.builder, string_from_napi_value(chunk));
        } else {
            is_typedarray: bool;
            napi_try(napi_is_typedarray(env, chunk, *is_typedarray));
            if is_typedarray {
                length: u64;
                data: *void;
                napi_try(napi_get_typedarray_info(env, chunk, null, *length, *data, null, null));
                append(*capture.builder, cast(*u8) data, xx length);
            }
        }

        for < 2..1 {
            napi_try(napi_typeof(env, argv[it], *type));
            if type == .napi_function {
                args: [2]napi_value;
                args[0] = argv[it];
                napi_try(napi_get_null(env, *args[1]));
                ignored: napi_value;
                napi_try(napi_call_function(env, capture.process, capture.next_tick, 2, args.data, *ignored));
                break;
            }
        }

        result: napi_value;
        napi_try(napi_get_boolean(env, true, *result));
        return result;
    }
}

init_process_output_capture :: (process_output_capture: *ProcessOutputCapture) {
    init_string_builder(*process_output_capture.builder);

    global: napi_value;
    napi_check(napi_get_global(napi_env_instance, *global));
    napi_check(napi_get_named_property(napi_env_instance, global, "process".data, *process_output_capture.process));
    napi_check(napi_get_named_property(napi_env_instance, process_output_capture.process, "nextTick".data, *process_output_capture.next_tick));
    napi_check(napi_get_named_property(napi_env_instance, process_output_capture.process, "stdout".data, *process_output_capture.stdout));
    napi_check(napi_get_named_property(napi_env_instance, process_output_capture.process, "stderr".data, *process_output_capture.stderr));

    napi_check(napi_get_named_property(napi_env_instance, process_output_capture.stdout, "write".data, *process_output_capture.original_stdout_write));
    napi_check(napi_get_named_property(napi_env_instance, process_output_capture.stderr, "write".data, *process_output_capture.original_stderr_write));

    capture_process_output_fn: napi_value;
    napi_check(napi_create_function(napi_env_instance, "write".data, "write".count, capture_process_output, process_output_capture, *capture_process_output_fn));

    napi_check(napi_set_named_property(napi_env_instance, process_output_capture.stdout, "write".data, capture_process_output_fn));
    napi_check(napi_set_named_property(napi_env_instance, process_output_capture.stderr, "write".data, capture_process_output_fn));
}

gather_process_output_capture :: (process_output_capture: *ProcessOutputCapture) -> string {
    return builder_to_string(*process_output_capture.builder);
}

deinit_process_output_capture :: (process_output_capture: *ProcessOutputCapture) {
    reset(*process_output_capture.builder);

    napi_check(napi_set_named_property(napi_env_instance, process_output_capture.stdout, "write".data, process_output_capture.original_stdout_write));
    napi_check(napi_set_named_property(napi_env_instance, process_output_capture.stderr, "write".data, process_output_capture.original_stderr_write));
}

print_test_path :: () {
    for test_name_breadcrumb {
        print("%", it);
        if it_index + 1 < test_name_breadcrumb.count {
            print(" > ");
        }
    }
}

cleanup_and_report_test_leaks :: (cp: napi_value) {
    if atomic_load(*interruption) == .SIGINT {
        node_cancel_terminate_execution(node_setup);
        node_clear_async_id_stack(node_setup);
        return;
    }

    leaks: [..]Leak;
    leaks_builder: String_Builder;

    quiesce_report(*leaks, cp);
    if leaks.count {
        print_leaks(*leaks_builder, leaks);
        // TODO: fail the test when this happens under some kind of strict mode 
        print("  Leaks: \n");
        write_builder(*leaks_builder);
    }

    quiesce_drain(cp);

    array_reset_keeping_memory(*leaks);
    quiesce_report(*leaks, cp);
    if leaks.count {
        print_leaks(*leaks_builder, leaks);
        print("  Leaks that could not be quiesced: \n");
        write_builder(*leaks_builder);
    }
}

print_test_exception :: (exception: napi_value) {
    if !exception {
        return;
    }
    is_error: bool;
    napi_check(napi_is_error(napi_env_instance, exception, *is_error));
    valuetype: napi_valuetype;
    napi_check(napi_typeof(napi_env_instance, exception, *valuetype));
    if is_error {
        exception_name: napi_value;
        napi_check(napi_get_named_property(napi_env_instance, exception, "name".data, *exception_name));
        exception_message: napi_value;
        napi_check(napi_get_named_property(napi_env_instance, exception, "message".data, *exception_message));
        exception_stack: napi_value;
        napi_check(napi_get_named_property(napi_env_instance, exception, "stack".data, *exception_stack));

        print("  threw ");
        set_print_color(.red);
        print("%: %", string_from_napi_value(exception_name), string_from_napi_value(exception_message));
        reset_print_styling();
        print(" at %\n", get_stack_trace_origin(string_from_napi_value(exception_stack)));
    } else if valuetype != .napi_undefined && valuetype != .napi_null {
        exception_stringified: napi_value;
        napi_check(napi_coerce_to_string(napi_env_instance, exception, *exception_stringified));
        print("  threw ");
        set_print_color(.red);
        print("%\n", string_from_napi_value(exception_stringified));
    }
}

///////////////////////////////////////////////////////////////////////////////
// tests

passed := 0;
todo := 0;
skipped := 0;
failed := 0;
test_files := 0;

TestState :: struct {
    passed: bool;
    start: Apollo_Time;

    // triggered by calling test.failing
    expected_to_fail: bool;
    timeout_ms: s64;
};
test_name_breadcrumb: [..]string;
test_state: TestState;

Filter :: struct {
    text: string;
    // anchored means it matches from the start of the path to the test
    anchored: bool;
}
filters: [..]Filter;

NULL_TIMEOUT: s64: -1;

matcher: napi_value;
negated_matcher: napi_value;
register_assertion :: (name: string, $message: string, $negated_message: string, $check: Code) {
    create_assertion :: ($check: Code, $message: string, $negated: bool) -> napi_callback {
        callback :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
            push_context test_context {
                assert(test_name_breadcrumb.count > 0);

                argc: u64 = 1;
                expected: napi_value;
                napi_try(napi_get_cb_info(env, info, *argc, *expected, null, null));

                actual: napi_value;
                napi_try(napi_get_named_property(env, matcher, "actual".data, *actual));

                passes: bool = true;
                #insert,scope() check;

                if passes == negated {
                    actual_inspected: napi_value;
                    napi_try(napi_call_function(env, napi_global, testa_inspect_fn, 1, *actual, *actual_inspected));
                    actual_inspected_string := string_from_napi_value(actual_inspected);

                    expected_inspected: napi_value;
                    napi_try(napi_call_function(env, napi_global, testa_inspect_fn, 1, *expected, *expected_inspected));
                    expected_inspected_string := string_from_napi_value(expected_inspected);

                    builder: String_Builder;
                    print_to_builder(*builder, message, actual_inspected_string, expected_inspected_string);
                    append(*builder, 0);
                    napi_try(napi_throw_error(env, null, builder_to_string(*builder).data));
                }
            }
            return null;
        }
        return callback;
    }

    fn: napi_value;
    napi_check(napi_create_function(napi_env_instance, name.data, xx name.count, create_assertion(check, message, negated = false), null, *fn));
    napi_check(napi_set_named_property(napi_env_instance, matcher, name.data, fn));

    napi_check(napi_create_function(napi_env_instance, name.data, xx name.count, create_assertion(check, negated_message, negated = true), null, *fn));
    napi_check(napi_set_named_property(napi_env_instance, negated_matcher, name.data, fn));
}

expect_fn: napi_value;
expect :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        actual: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *actual, null, null));
        napi_try(napi_set_named_property(env, matcher, "actual".data, actual));
    }
    return matcher;
}

Pending :: struct {
    name: string;
    callback: napi_ref;
    this: napi_ref;

    suite: bool;

    timeout_ms: s64;
    expected_to_fail: bool;
}
pending: [..]Pending;
SuiteConfiguration :: struct {
    // -1 means the suite doesn't define one, it should just use the default
    timeout_ms: s64;
    // suites and tests defined directly as this suite's descendants
    pending_count: s64;
    // The index inside of `pending` for this suite. This is used so that tests
    // and other suites can be inserted right after this suite in the pending
    // array
    index: s64;
};
// The stack of suite configurations up until now
suite_configurations: [..]SuiteConfiguration;

test_fn: napi_value;
// TODO: we should support having callbacks to be compatible with vitest, but we
// should find something better because these callbacks copy memory all around
// which is not ideal.
test :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 3;
        argv: [3]napi_value;
        this: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, argv.data, *this, null));
        test_name := argv[0];
        callback := argv[1];
        timeout_ms_value := argv[2];

        type: napi_valuetype;
        napi_try(napi_typeof(env, test_name, *type));
        if type != .napi_string {
            napi_check(napi_throw_type_error(env, null, "test(name, fn, timeout?): name must be a string".data));
            return null;
        }
        napi_try(napi_typeof(env, callback, *type));
        if type != .napi_function {
            napi_check(napi_throw_type_error(env, null, "test(name, fn, timeout?): fn must be a function".data));
            return null;
        }
        napi_try(napi_typeof(env, timeout_ms_value, *type));
        if type != .napi_undefined && type != .napi_number {
            napi_check(napi_throw_type_error(env, null, "test(name, fn, timeout?): timeout must be a number".data));
            return null;
        }

        test_name_string := string_from_napi_value(test_name);

        timeout_ms_value_type: napi_valuetype;
        napi_try(napi_typeof(napi_env_instance, timeout_ms_value, *timeout_ms_value_type));
        timeout_ms: s64;
        if timeout_ms_value_type != .napi_undefined && timeout_ms_value_type != .napi_null {
            napi_try(napi_get_value_int64(napi_env_instance, timeout_ms_value, *timeout_ms));
        } else if suite_configurations.count > 0 && suite_configurations[suite_configurations.count - 1].timeout_ms > NULL_TIMEOUT {
            timeout_ms = suite_configurations[suite_configurations.count - 1].timeout_ms;
        } else {
            timeout_ms = 5000;
        }

        pending_test: Pending;
        pending_test.name = test_name_string;
        pending_test.timeout_ms = timeout_ms;
        pending_test.expected_to_fail = test_state.expected_to_fail;
        pending_test.suite = false;
        napi_try(napi_create_reference(env, callback, 1, *pending_test.callback));
        napi_try(napi_create_reference(env, this, 1, *pending_test.this));
        if suite_configurations.count > 0 {
            array_insert_at(
                *pending, 
                pending_test, 
                suite_configurations[suite_configurations.count - 1].index + suite_configurations[suite_configurations.count - 1].pending_count + 1
            );
            suite_configurations[suite_configurations.count - 1].pending_count += 1;
        } else {
            array_add(*pending, pending_test);
        }
    }
    return null;
}

test_fails_fn: napi_value;
test_fails :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    test_state.expected_to_fail = true;
    defer test_state.expected_to_fail = false;
    return test(env, info);
}

test_run_if_fn: napi_value;
test_run_if :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        condition_argument: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *condition_argument, null, null));
        condition_coerced: napi_value;
        napi_try(napi_coerce_to_bool(env, condition_argument, *condition_coerced));
        condition: bool;
        napi_try(napi_get_value_bool(env, condition_coerced, *condition));

        if condition {
            return test_fn;
        } else {
            return test_skip_fn;
        }
    }
}

test_skip_if_fn: napi_value;
test_skip_if :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        condition_argument: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *condition_argument, null, null));
        condition_coerced: napi_value;
        napi_try(napi_coerce_to_bool(env, condition_argument, *condition_coerced));
        condition: bool;
        napi_try(napi_get_value_bool(env, condition_coerced, *condition));

        if condition {
            return test_skip_fn;
        } else {
            return test_fn;
        }
    }
}

test_skip_fn: napi_value;
test_skip :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        test_name: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *test_name, null, null));

        type: napi_valuetype;
        napi_try(napi_typeof(env, test_name, *type));
        if type != .napi_string {
            napi_check(napi_throw_type_error(env, null, "test.skip(name, fn, timeout?): name must be a string".data));
            return null;
        }

        test_name_string := string_from_napi_value(test_name);
        array_add(*test_name_breadcrumb, test_name_string);
        defer array_unordered_remove_by_index(*test_name_breadcrumb, test_name_breadcrumb.count - 1);

        set_print_color(.yellow);
        print("— ");
        print_test_path();
        set_print_color(.brightBlack);
        set_print_dim();
        print("[test.skip]\n");
        reset_print_styling();
        skipped += 1;

        return null;
    }
}

test_todo_fn: napi_value;
test_todo :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        test_name: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *test_name, null, null));

        type: napi_valuetype;
        napi_try(napi_typeof(env, test_name, *type));
        if type != .napi_string {
            napi_check(napi_throw_type_error(env, null, "test.todo(name): name must be a string".data));
            return null;
        }

        test_name_string := string_from_napi_value(test_name);
        array_add(*test_name_breadcrumb, test_name_string);
        defer array_unordered_remove_by_index(*test_name_breadcrumb, test_name_breadcrumb.count - 1);

        set_print_color(.brightBlack);
        set_print_dim();
        print("— ");
        print_test_path();
        print("[test.todo]\n");
        reset_print_styling();
        todo += 1;

        return null;
    }
}

describe_skip_fn: napi_value;
describe_skip :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        test_name: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *test_name, null, null));

        type: napi_valuetype;
        napi_try(napi_typeof(env, test_name, *type));
        if type != .napi_string {
            napi_check(napi_throw_type_error(env, null, "describe.skip(name, fn, timeout?): name must be a string".data));
            return null;
        }

        test_name_string := string_from_napi_value(test_name);
        array_add(*test_name_breadcrumb, test_name_string);
        defer array_unordered_remove_by_index(*test_name_breadcrumb, test_name_breadcrumb.count - 1);

        set_print_color(.yellow);
        print("— ");
        print_test_path();
        set_print_color(.brightBlack);
        set_print_dim();
        print("[describe.skip]\n");
        reset_print_styling();
        skipped += 1;

        return null;
    }
}

describe_todo_fn: napi_value;
describe_todo :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        test_name: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *test_name, null, null));

        type: napi_valuetype;
        napi_try(napi_typeof(env, test_name, *type));
        if type != .napi_string {
            napi_check(napi_throw_type_error(env, null, "describe.todo(name): name must be a string".data));
            return null;
        }

        test_name_string := string_from_napi_value(test_name);
        array_add(*test_name_breadcrumb, test_name_string);
        defer array_unordered_remove_by_index(*test_name_breadcrumb, test_name_breadcrumb.count - 1);

        set_print_color(.brightBlack);
        set_print_dim();
        print("— ");
        print_test_path();
        print("[describe.todo]\n");
        reset_print_styling();
        todo += 1;

        return null;
    }
}

describe_run_if_fn: napi_value;
describe_run_if :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        condition_argument: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *condition_argument, null, null));
        condition_coerced: napi_value;
        napi_try(napi_coerce_to_bool(env, condition_argument, *condition_coerced));
        condition: bool;
        napi_try(napi_get_value_bool(env, condition_coerced, *condition));

        if condition {
            return describe_fn;
        } else {
            return describe_skip_fn;
        }
    }
}

describe_skip_if_fn: napi_value;
describe_skip_if :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 1;
        condition_argument: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, *condition_argument, null, null));
        condition_coerced: napi_value;
        napi_try(napi_coerce_to_bool(env, condition_argument, *condition_coerced));
        condition: bool;
        napi_try(napi_get_value_bool(env, condition_coerced, *condition));

        if condition {
            return describe_skip_fn;
        } else {
            return describe_fn;
        }
    }
}

describe_fn: napi_value;
describe :: (env: napi_env, info: napi_callback_info) -> napi_value #c_call {
    push_context test_context {
        argc: u64 = 3;
        argv: [3]napi_value;
        this: napi_value;
        napi_try(napi_get_cb_info(env, info, *argc, argv.data, *this, null));
        suite_name := argv[0];
        callback := argv[1];
        timeout_ms_value := argv[2];

        type: napi_valuetype;
        napi_try(napi_typeof(env, suite_name, *type));
        if type != .napi_string {
            napi_check(napi_throw_type_error(env, null, "describe(name, fn, timeout?): name must be a string".data));
            return null;
        }
        napi_try(napi_typeof(env, callback, *type));
        if type != .napi_function {
            napi_check(napi_throw_type_error(env, null, "describe(name, fn, timeout?): fn must be a function".data));
            return null;
        }
        napi_try(napi_typeof(env, timeout_ms_value, *type));
        if type != .napi_undefined && type != .napi_number {
            napi_check(napi_throw_type_error(env, null, "describe(name, fn, timeout?): timeout must be a number".data));
            return null;
        }

        suite_name_string := string_from_napi_value(suite_name);

        timeout_ms_value_type: napi_valuetype;
        napi_try(napi_typeof(napi_env_instance, timeout_ms_value, *timeout_ms_value_type));
        timeout_ms: s64;
        if timeout_ms_value_type != .napi_undefined && timeout_ms_value_type != .napi_null {
            napi_try(napi_get_value_int64(napi_env_instance, timeout_ms_value, *timeout_ms));
        } else if suite_configurations.count > 0 && suite_configurations[suite_configurations.count - 1].timeout_ms > NULL_TIMEOUT {
            timeout_ms = suite_configurations[suite_configurations.count - 1].timeout_ms;
        } else {
            timeout_ms = NULL_TIMEOUT;
        }

        pending_suite: Pending;
        pending_suite.name = suite_name_string;
        pending_suite.timeout_ms = timeout_ms;
        pending_suite.suite = true;
        napi_try(napi_create_reference(env, callback, 1, *pending_suite.callback));
        napi_try(napi_create_reference(env, this, 1, *pending_suite.this));
        if suite_configurations.count > 0 {
            array_insert_at(
                *pending, 
                pending_suite, 
                suite_configurations[suite_configurations.count - 1].index + suite_configurations[suite_configurations.count - 1].pending_count + 1
            );
            suite_configurations[suite_configurations.count - 1].pending_count += 1;
        } else {
            array_add(*pending, pending_suite);
        }
    }
    return null;
}

register :: (env: napi_env, exports: napi_value) -> napi_value #c_call {
    napi_env_instance = env;
    return exports;
}

///////////////////////////////////////////////////////////////////////////////
// main

BOOTSTRAP :: #run,host -> string {
    #import "File";
    return read_entire_file("__bootstrap__.mjs", zero_terminated=true);
}

main :: () {
    pool: Pool;

    pool_context := context;
    pool_context.allocator.proc = pool_allocator_proc;
    pool_context.allocator.data = *pool;

    set_allocators(*pool);

    push_context pool_context {
        test_context = context;
        test_context.allocator.proc = pool_allocator_proc;
        test_context.allocator.data = *test_pool;

        set_allocators(*test_pool);

        cwd := get_working_directory();
        #if OS == .WINDOWS {
            path_overwrite_separators(cwd, #char "/");
            cwd_prefix = sprint("/%/", cwd); // matches the path part of a file:/// URL, e.g. "/C:/Users/me/project/"
        } else {
            cwd_prefix = sprint("%/", cwd);
        }
        args := get_command_line_arguments();
        for 1..args.count - 1 {
            filter: Filter;
            filter.text = to_lower_copy(args[it]);
            if begins_with(filter.text, "./") {
                filter.anchored = true;
                filter.text = slice(filter.text, 2, filter.text.count - 2);
            } else if begins_with(filter.text, "/") {
                filter.anchored = true;
                lowered_cwd_prefix := to_lower_copy(cwd_prefix);
                if begins_with(filter.text, lowered_cwd_prefix) {
                    filter.text = slice(filter.text, lowered_cwd_prefix.count, filter.text.count - lowered_cwd_prefix.count);
                }
            }
            array_add(*filters, filter);
        }

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

        #if OS == .WINDOWS {
            #import "Windows";
            kernel32 :: #library,system "kernel32";
            SetConsoleCtrlHandler :: (handler: (type: u32) -> BOOL #c_call, add: BOOL) -> BOOL #foreign kernel32;

            on_ctrl_c :: (type: u32) -> BOOL #c_call {
                if atomic_load(*interruption) == .SIGINT return 1;
                atomic_store(*interruption, .SIGINT);
                node_stop_event_loop(node_setup);
                return 1;
            }
            SetConsoleCtrlHandler(on_ctrl_c, 1);
        } else {
            #import "POSIX";

            stdout_is_tty = isatty(1) != 0;
            on_ctrl_c :: (sig: s32) #c_call {
                if atomic_load(*interruption) == .SIGINT return;
                atomic_store(*interruption, .SIGINT);
                node_stop_event_loop(node_setup);
                if stdout_is_tty {
                    write(1, "\r".data, 1);
                }
            }
            #if OS == .MACOS {
                libc :: #library,system "libc";
                signal :: (sig: s32, handler: (s32) -> () #c_call) -> *void #foreign libc;
            }
            signal(SIGINT, on_ctrl_c);
        }

        scope := v8_scope_open(node_setup);
        defer v8_scope_close(scope);
        node_add_linked_binding(node_env, "testa".data, register);
        status := node_load_environment_module(node_env, BOOTSTRAP.data, "file:///__bootstrap__.mjs".data);
        if status == 1 {
            print("Could not load environment with bootstrap script");
            return;
        }
        assert(napi_env_instance != null);

        napi_check(napi_get_global(napi_env_instance, *napi_global));

        {
            // process.quiesce setup
            process: napi_value;
            napi_check(napi_get_named_property(napi_env_instance, napi_global, "process".data, *process));
            napi_check(napi_get_named_property(napi_env_instance, process, "quiesce".data, *quiesce_namespace));
            napi_check(napi_get_named_property(napi_env_instance, quiesce_namespace, "checkpoint".data, *quiesce_checkpoint_fn));
            napi_check(napi_get_named_property(napi_env_instance, quiesce_namespace, "report".data, *quiesce_report_fn));
            napi_check(napi_get_named_property(napi_env_instance, quiesce_namespace, "quiesce".data, *quiesce_fn));
        }

        {
            napi_check(napi_get_named_property(napi_env_instance, napi_global, "process".data, *napi_process));
            napi_check(napi_get_named_property(napi_env_instance, napi_process, "_tickCallback".data, *napi_tick_callback_fn));

            on_uncaught_exception_fn, process_on, event, ignored: napi_value;
            napi_check(napi_create_function(napi_env_instance, "onUncaughtException".data, "onUncaughtException".count, on_uncaught_exception, null, *on_uncaught_exception_fn));
            napi_check(napi_get_named_property(napi_env_instance, napi_process, "on".data, *process_on));
            napi_check(napi_create_string_utf8(napi_env_instance, "uncaughtException".data, "uncaughtException".count, *event));
            args := napi_value.[event, on_uncaught_exception_fn];
            napi_check(napi_call_function(napi_env_instance, napi_process, process_on, 2, args.data, *ignored));
        }

        {
            // matchers/assertions
            napi_check(napi_create_object(napi_env_instance, *matcher));
            napi_check(napi_create_object(napi_env_instance, *negated_matcher));

            register_assertion("toBe", message="expected % to be %", negated_message="expceted % not to be %", #code {
                if !object_is(env, actual, expected) {
                    passes = false;
                }
            });

            register_assertion("toEqual", message="expected % to equal %", negated_message="expceted % not to equal %", #code {
                if !deep_equal(env, actual, expected, null) {
                    passes = false;
                }
            });

            napi_check(napi_set_named_property(napi_env_instance, matcher, "not".data, negated_matcher));
        }

        {
            // test definition functions
            {
                // assertions
                napi_check(napi_create_function(napi_env_instance, "expect".data, "expect".count, expect, null, *expect_fn));
                napi_check(napi_set_named_property(napi_env_instance, napi_global, "expect".data, expect_fn));
            }

            {
                // suites
                napi_check(napi_create_function(napi_env_instance, "describe".data, "describe".count, describe, null, *describe_fn));

                napi_check(napi_create_function(napi_env_instance, "describeSkip".data, "describeSkip".count, describe_skip, null, *describe_skip_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "skip".data, describe_skip_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "skips".data, describe_skip_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "skipped".data, describe_skip_fn));

                napi_check(napi_create_function(napi_env_instance, "describeTodo".data, "describeTodo".count, describe_todo, null, *describe_todo_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "todo".data, describe_todo_fn));

                napi_check(napi_create_function(napi_env_instance, "describeRunIf".data, "describeRunIf".count, describe_run_if, null, *describe_run_if_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "runIf".data, describe_run_if_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "if".data, describe_run_if_fn));

                napi_check(napi_create_function(napi_env_instance, "describeSkipIf".data, "describeSkipIf".count, describe_skip_if, null, *describe_skip_if_fn));
                napi_check(napi_set_named_property(napi_env_instance, describe_fn, "skipIf".data, describe_skip_if_fn));

                napi_check(napi_set_named_property(napi_env_instance, napi_global, "describe".data, describe_fn));
            }

            {
                // tests
                napi_check(napi_create_function(napi_env_instance, "test".data, "test".count, test, null, *test_fn));

                napi_check(napi_create_function(napi_env_instance, "testFails".data, "testFails".count, test_fails, null, *test_fails_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "fail".data, test_fails_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "fails".data, test_fails_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "failing".data, test_fails_fn));

                napi_check(napi_create_function(napi_env_instance, "testSkip".data, "testSkip".count, test_skip, null, *test_skip_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "skip".data, test_skip_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "skips".data, test_skip_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "skipped".data, test_skip_fn));

                napi_check(napi_create_function(napi_env_instance, "testRunIf".data, "testRunIf".count, test_run_if, null, *test_run_if_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "runIf".data, test_run_if_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "if".data, test_run_if_fn));

                napi_check(napi_create_function(napi_env_instance, "testSkipIf".data, "testSkipIf".count, test_skip_if, null, *test_skip_if_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "skipIf".data, test_skip_if_fn));

                napi_check(napi_create_function(napi_env_instance, "testTodo".data, "testTodo".count, test_todo, null, *test_todo_fn));
                napi_check(napi_set_named_property(napi_env_instance, test_fn, "todo".data, test_todo_fn));

                napi_check(napi_set_named_property(napi_env_instance, napi_global, "test".data, test_fn));
                napi_check(napi_set_named_property(napi_env_instance, napi_global, "it".data, test_fn));
            }
        }

        napi_check(napi_get_named_property(napi_env_instance, napi_global, "__testa_run".data, *testa_run_fn));
        napi_check(napi_get_named_property(napi_env_instance, napi_global, "__testa_inspect".data, *testa_inspect_fn));
        {
            url: napi_value;
            napi_check(napi_get_named_property(napi_env_instance, napi_global, "URL".data, *url));
            napi_check(napi_get_named_property(napi_env_instance, url, "prototype".data, *url_prototype));
        }

        {
            temporal: napi_value;
            napi_check(napi_get_named_property(napi_env_instance, napi_global, "Temporal".data, *temporal));
            temporal_type: napi_valuetype;
            napi_check(napi_typeof(napi_env_instance, temporal, *temporal_type));
            if temporal_type == .napi_object {
                names :: string.["Instant", "ZonedDateTime", "PlainDateTime", "PlainDate", "PlainTime", "PlainYearMonth", "PlainMonthDay"];
                for names {
                    constructor: napi_value;
                    napi_check(napi_get_named_property(napi_env_instance, temporal, it.data, *constructor));
                    napi_check(napi_get_named_property(napi_env_instance, constructor, "prototype".data, *temporal_equals_prototypes[it_index]));
                }
                duration: napi_value;
                napi_check(napi_get_named_property(napi_env_instance, temporal, "Duration".data, *duration));
                napi_check(napi_get_named_property(napi_env_instance, duration, "prototype".data, *temporal_duration_prototype));
            }
        }
        napi_check(napi_create_function(napi_env_instance, "noop".data, "noop".count, noop, null, *noop_fn));

        file_visitor :: (info: *File_Visit_Info, user_data: *void) {
            auto_release_temp();
            if atomic_load(*interruption) == .SIGINT return;

            push_context test_context {
                relative := info.full_name;
                if begins_with(relative, "./") {
                    relative = slice(relative, 2, relative.count - 2);
                }
                lowered := to_lower_copy(relative);

                if !info.is_directory {
                    matched := filters.count == 0;
                    for filters {
                        if (it.anchored && begins_with(lowered, it.text)) || (!it.anchored && contains(lowered, it.text)) {
                            matched = true;
                            break;
                        }
                    }
                    if matched {
                        if ends_with(info.short_name, ".test.ts") 
                        || ends_with(info.short_name, ".test.cts") 
                        || ends_with(info.short_name, ".test.mts") 

                        || ends_with(info.short_name, ".test.js") 
                        || ends_with(info.short_name, ".test.cjs") 
                        || ends_with(info.short_name, ".test.mjs") 

                        || ends_with(info.short_name, ".spec.ts") 
                        || ends_with(info.short_name, ".spec.cts") 
                        || ends_with(info.short_name, ".spec.mts") 

                        || ends_with(info.short_name, ".spec.js") 
                        || ends_with(info.short_name, ".spec.cjs") 
                        || ends_with(info.short_name, ".spec.mjs") {
                            test_files += 1;
                            absolute, success := get_absolute_path(info.full_name);
                            if !success {
                                print("Could not resolve path: %", relative);
                                return;
                            }

                            array_add(*test_name_breadcrumb, relative);
                            defer {
                                // we should only have the test filename in the breadcrumb here
                                assert(test_name_breadcrumb.count == 1);
                                array_unordered_remove_by_index(*test_name_breadcrumb, 0);
                            }

                            cp := quiesce_checkpoint();
                            defer cleanup_and_report_test_leaks(cp);

                            absolute_file_path_string: napi_value;
                            napi_check(napi_create_string_utf8(napi_env_instance, absolute.data, cast(u64) absolute.count, *absolute_file_path_string));

                            result: napi_value;
                            napi_check(napi_call_function(
                                napi_env_instance, 
                                napi_global, 
                                testa_run_fn, 
                                1, 
                                *absolute_file_path_string, 
                                *result
                            ));
                            node_perform_microtask_checkpoint(node_setup);

                            run_promise := v8_promise_ref(result);
                            defer v8_promise_unref(run_promise);
                            while v8_promise_state(run_promise) == kPending && atomic_load(*interruption) != .SIGINT && node_spin_event_loop_once(node_setup) {}
                            if v8_promise_state(run_promise) == kRejected {
                                print("Failed to load %", relative);
                                return;
                            }

                            run_pending_thing :: (i: *s64) {
                                it := pending[i.*];

                                array_add(*test_name_breadcrumb, it.name);
                                defer array_unordered_remove_by_index(*test_name_breadcrumb, test_name_breadcrumb.count - 1);

                                callback, this: napi_value;
                                napi_check(napi_get_reference_value(napi_env_instance, it.callback, *callback));
                                napi_check(napi_get_reference_value(napi_env_instance, it.this, *this));
                                defer napi_check(napi_delete_reference(napi_env_instance, it.callback));
                                defer napi_check(napi_delete_reference(napi_env_instance, it.this));

                                if it.suite {
                                    suite_configuration: SuiteConfiguration;
                                    suite_configuration.timeout_ms = it.timeout_ms;
                                    suite_configuration.pending_count = 0;
                                    suite_configuration.index = i.*;
                                    array_add(*suite_configurations, suite_configuration);
                                    defer array_unordered_remove_by_index(*suite_configurations, suite_configurations.count - 1);

                                    cp := quiesce_checkpoint();
                                    success, exception := call_testing_function(
                                        callback, 
                                        this, 
                                        ifx it.timeout_ms > NULL_TIMEOUT it.timeout_ms else 5000
                                    );

                                    if success {
                                        j: s64 = 0;
                                        while j < suite_configurations[suite_configurations.count - 1].pending_count && atomic_load(*interruption) != .SIGINT {
                                            i.* += 1;
                                            run_pending_thing(i);

                                            j += 1;
                                        }
                                    } else {
                                        i.* += suite_configurations[suite_configurations.count - 1].pending_count;
                                    }

                                    print_test_exception(exception);

                                    set_print_color(.brightBlack);
                                    set_print_dim();
                                    cleanup_and_report_test_leaks(cp);
                                    reset_print_styling();
                                } else {
                                    test_state.timeout_ms = it.timeout_ms;
                                    test_state.start = current_time_monotonic();
                                    test_state.passed = true;
                                    test_state.expected_to_fail = it.expected_to_fail;
                                    defer test_state.expected_to_fail = false;

                                    cp := quiesce_checkpoint();
                                    success, exception := call_testing_function(callback, this, test_state.timeout_ms);
                                    if !success {
                                        test_state.passed = false;
                                    }

                                    if test_state.expected_to_fail {
                                        test_state.passed = !test_state.passed;
                                    }

                                    if test_state.passed {
                                        set_print_color(.green);
                                        print("✔ ");
                                        reset_print_styling();

                                        print_test_path();
                                        if test_state.expected_to_fail {
                                            set_print_color(.brightBlack);
                                            set_print_dim();
                                            print("[test.failing]");
                                        }
                                        passed += 1;
                                    } else {
                                        set_print_color(.red);
                                        print("✘ ");
                                        reset_print_styling();
                                        print_test_path();
                                        if test_state.expected_to_fail {
                                            set_print_color(.brightBlack);
                                            set_print_dim();
                                            print("[test.failing]");
                                        }
                                        failed += 1;
                                    }
                                    duration := current_time_monotonic() - test_state.start;

                                    set_print_color(.brightBlack);
                                    set_print_dim();
                                    if (to_seconds(duration) > 0) {
                                        print(" %s\n", to_seconds(duration));
                                    } else if (to_milliseconds(duration) > 0) {
                                        print(" %ms\n", to_milliseconds(duration));
                                    } else if (to_microseconds(duration) > 0) {
                                        print(" %μs\n", to_microseconds(duration));
                                    } else if (to_nanoseconds(duration) > 0) {
                                        // I don't think this can ever be the case, but just to be safe, this is literally a catch-all for 
                                        // the time a modern computer can take to do a single operation
                                        print(" %ns\n", to_nanoseconds(duration));
                                    }
                                    reset_print_styling();

                                    print_test_exception(exception);

                                    set_print_color(.brightBlack);
                                    set_print_dim();
                                    cleanup_and_report_test_leaks(cp);
                                    reset_print_styling();
                                };
                            }

                            // though I hate the fact that we're collecting to run, this is required if we want to provide a good experience to users, so
                            // the performance cost should not be relevant to that in this case.
                            //
                            // in the future, we will have an API for defining tests that does not use this stupid callback pattern for various reasons,
                            // and this is one of the things we would not have to do with it.
                            i: s64 = 0;
                            // while loop because Jai's for loop copies the array's data and count which will change since this will run suites and
                            // aggregate more pending tests
                            while i < pending.count && atomic_load(*interruption) != .SIGINT {
                                defer i += 1;

                                // if we're gathering, we will need to allocate the data elsewhere to use once all tests are done and we can show the test output
                                // process_output_capture: ProcessOutputCapture;
                                // init_process_output_capture(*process_output_capture);
                                // defer deinit_process_output_capture(*process_output_capture);

                                run_pending_thing(*i);
                            }

                        }
                        assert(suite_configurations.count == 0);
                        assert(test_name_breadcrumb.count == 0);
                        array_reset(*suite_configurations);
                        array_reset(*test_name_breadcrumb);
                        array_reset(*pending);
                    }
                } else {
                    if info.short_name == "node_modules" || info.short_name == ".git" {
                        info.descend_into_directory = false;
                    } else {
                        info.descend_into_directory = filters.count == 0;
                        for filters {
                            if !it.anchored || begins_with(lowered, it.text) || begins_with(it.text, lowered) {
                                info.descend_into_directory = true;
                                break;
                            }
                        }
                    }
                }
            }
            reset(*test_pool);
        }
        visit_files(".", recursive=true, null, file_visitor, visit_directories=true);
    }

    set_print_color(.red);
    print("% failed", failed);
    reset_print_styling();

    set_print_dim();
    print(", ");
    reset_print_styling();

    set_print_color(.green);
    print("% passed", passed);
    reset_print_styling();

    if skipped > 0 {
        set_print_dim();
        print(", ");
        reset_print_styling();

        set_print_color(.yellow);
        print("% skipped", skipped);
        reset_print_styling();
    }

    if todo > 0 {
        set_print_dim();
        print(", ");
        reset_print_styling();

        set_print_color(.brightBlack);
        set_print_dim();
        print("% todo", todo);
        reset_print_styling();
    }

    if test_files == 0 && filters.count > 0 {
        set_print_dim();
        print(", no test files found for filter:");
        args := get_command_line_arguments();
        for 1..args.count - 1 {
            print(" %", args[it]);
        }
        reset_print_styling();
    }

    print("\n");

    #if DEBUG {
        release(*pool);
        report_memory_leaks();
    }

    if atomic_load(*interruption) == .SIGINT {
        exit(130);
    }
    if failed > 0 || (test_files == 0 && filters.count > 0) {
        exit(1);
    }
}
