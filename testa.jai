#import "Basic";
#import "File_Utilities";

#load "napi-linux.jai";

callback_ctx: #Context;

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
        global: napi_value;
        napi_get_global(env, *global);
        fn: napi_value;
        napi_create_function(env, "expect".data, "expect".count, expect, null, *fn);
        napi_set_named_property(env, global, "expect".data, fn);
    }
    return exports;
}

SCRIPT :: #string END
process._linkedBinding('testa');
expect(1 + 1).toBe(2);
expect('foo' + 'bar').toBe('foobar');
expect(1.5).toBe(1.5);
expect(1).toBe(2);
END

main :: () {
    arguments = get_command_line_arguments();

    visit_files(ifx arguments.count > 1 arguments[1] else ".");

    callback_ctx = context;
    testa_set_register(register);
    exit_code := testa_run(SCRIPT.data);
    print("passed: %, failed: %, node exit code: %\n", passed, failed, exit_code);
}
