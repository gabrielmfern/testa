#import "Basic";
#import "String";
#import "File";
#import "File_Utilities";

#load "napi-linux.jai";

callback_ctx: #Context;

the_env: napi_env;
node_env: *node_environment;

passed := 0;
failed := 0;

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
        if equal passed += 1;
        else     failed += 1;
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
        the_env = env;
        global: napi_value;
        napi_get_global(env, *global);
        fn: napi_value;
        napi_create_function(env, "expect".data, "expect".count, expect, null, *fn);
        napi_set_named_property(env, global, "expect".data, fn);
    }
    return exports;
}

main :: () {
    callback_ctx = context;
    args := get_command_line_arguments();
    dir := ifx args.count > 1 then args[1] else ".";

    init := node_initialize_once_per_process();
    if node_initialization_result_early_return(init) != 0 exit(node_initialization_result_exit_code(init));

    platform := node_multi_isolate_platform_create(4);
    v8_initialize(platform);

    setup := node_common_environment_setup_create(platform, init);
    if !setup exit(1);
    node_env = node_common_environment_setup_env(setup);

    scope := v8_scope_open(setup);
    node_add_linked_binding(node_env, "testa".data, register);
    node_load_environment(node_env, "process._linkedBinding('testa'); const req = require('node:module').createRequire(process.cwd() + '/'); globalThis.__testa_run = p => req(p);".data);
    assert(the_env != null);

    file_visitor :: (info: *File_Visit_Info, user_data: *void) {
        if ends_with(info.short_name, ".test.ts") || 
            ends_with(info.short_name, ".test.js") || 
            ends_with(info.short_name, ".test.mts") || 
            ends_with(info.short_name, ".test.mjs") {
            absolute, success := get_absolute_path(info.full_name);
            if !success {
                log_error("Could not resolve path: %", info.full_name);
                return;
            }
            print("running %\n", info.full_name);
            url := absolute;
            global, fn, arg, result: napi_value;
            napi_get_global(the_env, *global);
            napi_get_named_property(the_env, global, "__testa_run".data, *fn);
            napi_create_string_utf8(the_env, url.data, cast(u64) url.count, *arg);
            napi_call_function(the_env, global, fn, 1, *arg, *result);
            node_spin_event_loop(node_env);
        }
    }
    visit_files(
        dir, 
        recursive=true, 
        cast(*void) null, 
        file_visitor,
    );

    v8_scope_close(scope);
    node_stop(node_env);
    node_common_environment_setup_destroy(setup);
    v8_dispose(platform);
    node_tear_down_once_per_process();

    print("passed: %, failed: %\n", passed, failed);
    if failed exit(1);
}
