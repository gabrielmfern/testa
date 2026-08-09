//
// This file was auto-generated using the following command:
//
// jai build.jai
//



NAPI_VERSION_EXPERIMENTAL :: 2147483647;

NAPI_VERSION :: 8;

napi_env__ :: struct {}
// JSVM API types are all opaque pointers for ABI stability
// typedef undefined structs instead of void* for compile time type safety
napi_env :: *napi_env__;

node_api_nogc_env :: *napi_env__;

node_api_basic_env :: node_api_nogc_env;

napi_value__ :: struct {}
napi_value :: *napi_value__;
napi_ref__ :: struct {}
napi_ref :: *napi_ref__;
napi_handle_scope__ :: struct {}
napi_handle_scope :: *napi_handle_scope__;
napi_escapable_handle_scope__ :: struct {}
napi_escapable_handle_scope :: *napi_escapable_handle_scope__;
napi_callback_info__ :: struct {}
napi_callback_info :: *napi_callback_info__;
napi_deferred__ :: struct {}
napi_deferred :: *napi_deferred__;

napi_property_attributes :: enum u32 {
    default            :: 0;
    writable           :: 1;
    enumerable         :: 2;
    configurable       :: 4;

    static             :: 1024;

    default_method     :: 5;

    default_jsproperty :: 7;

    napi_default            :: default;
    napi_writable           :: writable;
    napi_enumerable         :: enumerable;
    napi_configurable       :: configurable;

    napi_static             :: static;

    napi_default_method     :: default_method;

    napi_default_jsproperty :: default_jsproperty;
}

napi_valuetype :: enum u32 {
    undefined :: 0;
    _null     :: 1;
    boolean   :: 2;
    number    :: 3;
    _string   :: 4;
    symbol    :: 5;
    object    :: 6;
    function  :: 7;
    external  :: 8;
    bigint    :: 9;

    napi_undefined :: undefined;
    napi_null      :: _null;
    napi_boolean   :: boolean;
    napi_number    :: number;
    napi_string    :: _string;
    napi_symbol    :: symbol;
    napi_object    :: object;
    napi_function  :: function;
    napi_external  :: external;
    napi_bigint    :: bigint;
}

napi_typedarray_type :: enum u32 {
    int8_array          :: 0;
    uint8_array         :: 1;
    uint8_clamped_array :: 2;
    int16_array         :: 3;
    uint16_array        :: 4;
    int32_array         :: 5;
    uint32_array        :: 6;
    float32_array       :: 7;
    float64_array       :: 8;
    bigint64_array      :: 9;
    biguint64_array     :: 10;

    float16_array       :: 11;

    napi_int8_array          :: int8_array;
    napi_uint8_array         :: uint8_array;
    napi_uint8_clamped_array :: uint8_clamped_array;
    napi_int16_array         :: int16_array;
    napi_uint16_array        :: uint16_array;
    napi_int32_array         :: int32_array;
    napi_uint32_array        :: uint32_array;
    napi_float32_array       :: float32_array;
    napi_float64_array       :: float64_array;
    napi_bigint64_array      :: bigint64_array;
    napi_biguint64_array     :: biguint64_array;

    napi_float16_array       :: float16_array;
}

napi_status :: enum u32 {
    ok                              :: 0;
    invalid_arg                     :: 1;
    object_expected                 :: 2;
    string_expected                 :: 3;
    name_expected                   :: 4;
    function_expected               :: 5;
    number_expected                 :: 6;
    boolean_expected                :: 7;
    array_expected                  :: 8;
    generic_failure                 :: 9;
    pending_exception               :: 10;
    cancelled                       :: 11;
    escape_called_twice             :: 12;
    handle_scope_mismatch           :: 13;
    callback_scope_mismatch         :: 14;
    queue_full                      :: 15;
    closing                         :: 16;
    bigint_expected                 :: 17;
    date_expected                   :: 18;
    arraybuffer_expected            :: 19;
    detachable_arraybuffer_expected :: 20;
    would_deadlock                  :: 21;
    no_external_buffers_allowed     :: 22;
    cannot_run_js                   :: 23;

    napi_ok                              :: ok;
    napi_invalid_arg                     :: invalid_arg;
    napi_object_expected                 :: object_expected;
    napi_string_expected                 :: string_expected;
    napi_name_expected                   :: name_expected;
    napi_function_expected               :: function_expected;
    napi_number_expected                 :: number_expected;
    napi_boolean_expected                :: boolean_expected;
    napi_array_expected                  :: array_expected;
    napi_generic_failure                 :: generic_failure;
    napi_pending_exception               :: pending_exception;
    napi_cancelled                       :: cancelled;
    napi_escape_called_twice             :: escape_called_twice;
    napi_handle_scope_mismatch           :: handle_scope_mismatch;
    napi_callback_scope_mismatch         :: callback_scope_mismatch;
    napi_queue_full                      :: queue_full;
    napi_closing                         :: closing;
    napi_bigint_expected                 :: bigint_expected;
    napi_date_expected                   :: date_expected;
    napi_arraybuffer_expected            :: arraybuffer_expected;
    napi_detachable_arraybuffer_expected :: detachable_arraybuffer_expected;
    napi_would_deadlock                  :: would_deadlock;
    napi_no_external_buffers_allowed     :: no_external_buffers_allowed;
    napi_cannot_run_js                   :: cannot_run_js;
}

// Note: when adding a new enum value to `napi_status`, please also update
//   * `const int last_status` in the definition of `napi_get_last_error_info()'
//     in file js_native_api_v8.cc.
//   * `const char* error_messages[]` in file js_native_api_v8.cc with a brief
//     message explaining the error.
//   * the definition of `napi_status` in doc/api/n-api.md to reflect the newly
//     added value(s).
napi_callback :: #type (env: napi_env, info: napi_callback_info) -> napi_value #c_call;

napi_finalize :: #type (env: napi_env, finalize_data: *void, finalize_hint: *void) -> void #c_call;

node_api_nogc_finalize :: napi_finalize;

node_api_basic_finalize :: node_api_nogc_finalize;

// A finalizer that can be called from any thread and at any time.
node_api_noenv_finalize :: #type (finalize_data: *void, finalize_hint: *void) -> void #c_call;

napi_property_descriptor :: struct {
    // One of utf8name or name should be NULL.
    utf8name:   *u8;
    name:       napi_value;

    method:     napi_callback;
    getter:     napi_callback;
    setter:     napi_callback;
    value:      napi_value;

    attributes: napi_property_attributes;
    data:       *void;
}

napi_extended_error_info :: struct {
    error_message:     *u8;
    engine_reserved:   *void;
    engine_error_code: u32;
    error_code:        napi_status;
}

napi_key_collection_mode :: enum u32 {
    include_prototypes :: 0;
    own_only           :: 1;

    napi_key_include_prototypes :: include_prototypes;
    napi_key_own_only           :: own_only;
}

napi_key_filter :: enum u32 {
    all_properties :: 0;
    writable       :: 1;
    enumerable     :: 2;
    configurable   :: 4;
    skip_strings   :: 8;
    skip_symbols   :: 16;

    napi_key_all_properties :: all_properties;
    napi_key_writable       :: writable;
    napi_key_enumerable     :: enumerable;
    napi_key_configurable   :: configurable;
    napi_key_skip_strings   :: skip_strings;
    napi_key_skip_symbols   :: skip_symbols;
}

napi_key_conversion :: enum u32 {
    keep_numbers       :: 0;
    numbers_to_strings :: 1;

    napi_key_keep_numbers       :: keep_numbers;
    napi_key_numbers_to_strings :: numbers_to_strings;
}

napi_type_tag :: struct {
    lower: u64;
    upper: u64;
}

napi_addon_register_func :: #type (env: napi_env, exports: napi_value) -> napi_value #c_call;

// False positive: https://github.com/cpplint/cpplint/issues/409
// NOLINTNEXTLINE (readability/casting)
node_api_addon_get_api_version_func :: #type () -> s32 #c_call;

napi_callback_scope__ :: struct {}
napi_callback_scope :: *napi_callback_scope__;
napi_async_context__ :: struct {}
napi_async_context :: *napi_async_context__;
napi_async_work__ :: struct {}
napi_async_work :: *napi_async_work__;

napi_cleanup_hook :: #type (arg: *void) -> void #c_call;

napi_threadsafe_function__ :: struct {}
napi_threadsafe_function :: *napi_threadsafe_function__;

napi_threadsafe_function_release_mode :: enum u32 {
    release :: 0;
    abort   :: 1;

    napi_tsfn_release :: release;
    napi_tsfn_abort   :: abort;
}

napi_threadsafe_function_call_mode :: enum u32 {
    nonblocking :: 0;
    blocking    :: 1;

    napi_tsfn_nonblocking :: nonblocking;
    napi_tsfn_blocking    :: blocking;
}

napi_async_execute_callback :: #type (env: napi_env, data: *void) -> void #c_call;
napi_async_complete_callback :: #type (env: napi_env, status: napi_status, data: *void) -> void #c_call;

napi_threadsafe_function_call_js :: #type (env: napi_env, js_callback: napi_value, _context: *void, data: *void) -> void #c_call;

napi_node_version :: struct {
    major:   u32;
    minor:   u32;
    patch:   u32;
    release: *u8;
}

napi_async_cleanup_hook_handle__ :: struct {}
napi_async_cleanup_hook_handle :: *napi_async_cleanup_hook_handle__;
napi_async_cleanup_hook :: #type (handle: napi_async_cleanup_hook_handle, data: *void) -> void #c_call;

node_initialization_result :: struct {}
node_multi_isolate_platform :: struct {}
node_common_environment_setup :: struct {}
node_environment :: struct {}
v8_scope :: struct {}

node_initialize_once_per_process :: () -> *node_initialization_result #foreign shim;
node_initialization_result_early_return :: (result: *node_initialization_result) -> s32 #foreign shim;
node_initialization_result_exit_code :: (result: *node_initialization_result) -> s32 #foreign shim;
node_tear_down_once_per_process :: () -> void #foreign shim;

node_multi_isolate_platform_create :: (thread_pool_size: s32) -> *node_multi_isolate_platform #foreign shim;

v8_initialize :: (platform: *node_multi_isolate_platform) -> void #foreign shim;
v8_dispose :: (platform: *node_multi_isolate_platform) -> void #foreign shim;

node_common_environment_setup_create :: (platform: *node_multi_isolate_platform, result: *node_initialization_result) -> *node_common_environment_setup #foreign shim;
node_common_environment_setup_env :: (setup: *node_common_environment_setup) -> *node_environment #foreign shim;
node_common_environment_setup_destroy :: (setup: *node_common_environment_setup) -> void #foreign shim;

v8_scope_open :: (setup: *node_common_environment_setup) -> *v8_scope #foreign shim;
v8_scope_close :: (scope: *v8_scope) -> void #foreign shim;

node_add_linked_binding :: (env: *node_environment, name: *u8, fn: napi_addon_register_func) -> void #foreign shim;
node_load_environment :: (env: *node_environment, script: *u8) -> s32 #foreign shim;
node_load_environment_module :: (env: *node_environment, source: *u8, resource_name: *u8) -> s32 #foreign shim;
node_spin_event_loop :: (env: *node_environment) -> s32 #foreign shim;
node_stop :: (env: *node_environment) -> s32 #foreign shim;
node_spin_event_loop_once :: (setup: *node_common_environment_setup) -> s32 #foreign shim;
node_stop_event_loop :: (setup: *node_common_environment_setup) -> void #foreign shim;
node_cancel_terminate_execution :: (setup: *node_common_environment_setup) -> void #foreign shim;
node_perform_microtask_checkpoint :: (setup: *node_common_environment_setup) -> void #foreign shim;
v8_promise :: struct {}
v8_promise_ref :: (value: napi_value) -> *v8_promise #foreign shim;
v8_promise_state :: (promise: *v8_promise) -> s32 #foreign shim;
v8_promise_result :: (promise: *v8_promise) -> napi_value #foreign shim;
v8_promise_unref :: (promise: *v8_promise) -> void #foreign shim;

napi_get_last_error_info :: (env: node_api_basic_env, result: **napi_extended_error_info) -> napi_status #foreign libnode;

// Getters for defined singletons
napi_get_undefined :: (env: napi_env, result: *napi_value) -> napi_status #foreign libnode;

napi_get_null :: (env: napi_env, result: *napi_value) -> napi_status #foreign libnode;

napi_get_global :: (env: napi_env, result: *napi_value) -> napi_status #foreign libnode;

napi_get_boolean :: (env: napi_env, value: bool, result: *napi_value) -> napi_status #foreign libnode;

// Methods to create Primitive types/Objects
napi_create_object :: (env: napi_env, result: *napi_value) -> napi_status #foreign libnode;

napi_create_array :: (env: napi_env, result: *napi_value) -> napi_status #foreign libnode;

napi_create_array_with_length :: (env: napi_env, length: u64, result: *napi_value) -> napi_status #foreign libnode;
napi_create_double :: (env: napi_env, value: float64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_int32 :: (env: napi_env, value: s32, result: *napi_value) -> napi_status #foreign libnode;

napi_create_uint32 :: (env: napi_env, value: u32, result: *napi_value) -> napi_status #foreign libnode;

napi_create_int64 :: (env: napi_env, value: s64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_string_latin1 :: (env: napi_env, str: *u8, length: u64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_string_utf8 :: (env: napi_env, str: *u8, length: u64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_string_utf16 :: (env: napi_env, str: *u16, length: u64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_symbol :: (env: napi_env, description: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_create_function :: (env: napi_env, utf8name: *u8, length: u64, cb: napi_callback, data: *void, result: *napi_value) -> napi_status #foreign libnode;

napi_create_error :: (env: napi_env, code: napi_value, msg: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_create_type_error :: (env: napi_env, code: napi_value, msg: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_create_range_error :: (env: napi_env, code: napi_value, msg: napi_value, result: *napi_value) -> napi_status #foreign libnode;

// Methods to get the native napi_value from Primitive type
napi_typeof :: (env: napi_env, value: napi_value, result: *napi_valuetype) -> napi_status #foreign libnode;

napi_get_value_double :: (env: napi_env, value: napi_value, result: *float64) -> napi_status #foreign libnode;

napi_get_value_int32 :: (env: napi_env, value: napi_value, result: *s32) -> napi_status #foreign libnode;

napi_get_value_uint32 :: (env: napi_env, value: napi_value, result: *u32) -> napi_status #foreign libnode;

napi_get_value_int64 :: (env: napi_env, value: napi_value, result: *s64) -> napi_status #foreign libnode;

napi_get_value_bool :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

// Copies LATIN-1 encoded bytes from a string into a buffer.
napi_get_value_string_latin1 :: (env: napi_env, value: napi_value, buf: *u8, bufsize: u64, result: *u64) -> napi_status #foreign libnode;

// Copies UTF-8 encoded bytes from a string into a buffer.
napi_get_value_string_utf8 :: (env: napi_env, value: napi_value, buf: *u8, bufsize: u64, result: *u64) -> napi_status #foreign libnode;

// Copies UTF-16 encoded bytes from a string into a buffer.
napi_get_value_string_utf16 :: (env: napi_env, value: napi_value, buf: *u16, bufsize: u64, result: *u64) -> napi_status #foreign libnode;

// Methods to coerce values
// These APIs may execute user scripts
napi_coerce_to_bool :: (env: napi_env, value: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_coerce_to_number :: (env: napi_env, value: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_coerce_to_object :: (env: napi_env, value: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_coerce_to_string :: (env: napi_env, value: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_get_prototype :: (env: napi_env, object: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_get_property_names :: (env: napi_env, object: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_set_property :: (env: napi_env, object: napi_value, key: napi_value, value: napi_value) -> napi_status #foreign libnode;

napi_has_property :: (env: napi_env, object: napi_value, key: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_get_property :: (env: napi_env, object: napi_value, key: napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_delete_property :: (env: napi_env, object: napi_value, key: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_has_own_property :: (env: napi_env, object: napi_value, key: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_set_named_property :: (env: napi_env, object: napi_value, utf8name: *u8, value: napi_value) -> napi_status #foreign libnode;

napi_has_named_property :: (env: napi_env, object: napi_value, utf8name: *u8, result: *bool) -> napi_status #foreign libnode;

napi_get_named_property :: (env: napi_env, object: napi_value, utf8name: *u8, result: *napi_value) -> napi_status #foreign libnode;

napi_set_element :: (env: napi_env, object: napi_value, index: u32, value: napi_value) -> napi_status #foreign libnode;

napi_has_element :: (env: napi_env, object: napi_value, index: u32, result: *bool) -> napi_status #foreign libnode;

napi_get_element :: (env: napi_env, object: napi_value, index: u32, result: *napi_value) -> napi_status #foreign libnode;

napi_delete_element :: (env: napi_env, object: napi_value, index: u32, result: *bool) -> napi_status #foreign libnode;

napi_define_properties :: (env: napi_env, object: napi_value, property_count: u64, properties: *napi_property_descriptor) -> napi_status #foreign libnode;

// Methods to work with Arrays
napi_is_array :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_get_array_length :: (env: napi_env, value: napi_value, result: *u32) -> napi_status #foreign libnode;

// Methods to compare values
napi_strict_equals :: (env: napi_env, lhs: napi_value, rhs: napi_value, result: *bool) -> napi_status #foreign libnode;

// Methods to work with Functions
napi_call_function :: (env: napi_env, recv: napi_value, func: napi_value, argc: u64, argv: *napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_new_instance :: (env: napi_env, constructor: napi_value, argc: u64, argv: *napi_value, result: *napi_value) -> napi_status #foreign libnode;

napi_instanceof :: (env: napi_env, object: napi_value, constructor: napi_value, result: *bool) -> napi_status #foreign libnode;

// Gets all callback info in a single call. (Ugly, but faster.)
napi_get_cb_info :: (env: napi_env, cbinfo: napi_callback_info, argc: *u64, argv: *napi_value, this_arg: *napi_value, data: **void) -> napi_status #foreign libnode;

napi_get_new_target :: (env: napi_env, cbinfo: napi_callback_info, result: *napi_value) -> napi_status #foreign libnode;

napi_define_class :: (env: napi_env, utf8name: *u8, length: u64, constructor: napi_callback, data: *void, property_count: u64, properties: *napi_property_descriptor, result: *napi_value) -> napi_status #foreign libnode;

// Methods to work with external data objects
napi_wrap :: (env: napi_env, js_object: napi_value, native_object: *void, finalize_cb: node_api_basic_finalize, finalize_hint: *void, result: *napi_ref) -> napi_status #foreign libnode;

napi_unwrap :: (env: napi_env, js_object: napi_value, result: **void) -> napi_status #foreign libnode;

napi_remove_wrap :: (env: napi_env, js_object: napi_value, result: **void) -> napi_status #foreign libnode;

napi_create_external :: (env: napi_env, data: *void, finalize_cb: node_api_basic_finalize, finalize_hint: *void, result: *napi_value) -> napi_status #foreign libnode;

napi_get_value_external :: (env: napi_env, value: napi_value, result: **void) -> napi_status #foreign libnode;

// Set initial_refcount to 0 for a weak reference, >0 for a strong reference.
napi_create_reference :: (env: napi_env, value: napi_value, initial_refcount: u32, result: *napi_ref) -> napi_status #foreign libnode;

// Deletes a reference. The referenced value is released, and may
// be GC'd unless there are other references to it.
napi_delete_reference :: (env: node_api_basic_env, ref: napi_ref) -> napi_status #foreign libnode;

// Increments the reference count, optionally returning the resulting count.
// After this call the  reference will be a strong reference because its
// refcount is >0, and the referenced object is effectively "pinned".
// Calling this when the refcount is 0 and the object is unavailable
// results in an error.
napi_reference_ref :: (env: napi_env, ref: napi_ref, result: *u32) -> napi_status #foreign libnode;

// Decrements the reference count, optionally returning the resulting count.
// If the result is 0 the reference is now weak and the object may be GC'd
// at any time if there are no other references. Calling this when the
// refcount is already 0 results in an error.
napi_reference_unref :: (env: napi_env, ref: napi_ref, result: *u32) -> napi_status #foreign libnode;

// Attempts to get a referenced value. If the reference is weak,
// the value might no longer be available, in that case the call
// is still successful but the result is NULL.
napi_get_reference_value :: (env: napi_env, ref: napi_ref, result: *napi_value) -> napi_status #foreign libnode;

napi_open_handle_scope :: (env: napi_env, result: *napi_handle_scope) -> napi_status #foreign libnode;

napi_close_handle_scope :: (env: napi_env, scope: napi_handle_scope) -> napi_status #foreign libnode;
napi_open_escapable_handle_scope :: (env: napi_env, result: *napi_escapable_handle_scope) -> napi_status #foreign libnode;

napi_close_escapable_handle_scope :: (env: napi_env, scope: napi_escapable_handle_scope) -> napi_status #foreign libnode;

napi_escape_handle :: (env: napi_env, scope: napi_escapable_handle_scope, escapee: napi_value, result: *napi_value) -> napi_status #foreign libnode;

// Methods to support error handling
napi_throw :: (env: napi_env, error: napi_value) -> napi_status #foreign libnode;
napi_throw_error :: (env: napi_env, code: *u8, msg: *u8) -> napi_status #foreign libnode;

napi_throw_type_error :: (env: napi_env, code: *u8, msg: *u8) -> napi_status #foreign libnode;

napi_throw_range_error :: (env: napi_env, code: *u8, msg: *u8) -> napi_status #foreign libnode;

napi_is_error :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

// Methods to support catching exceptions
napi_is_exception_pending :: (env: napi_env, result: *bool) -> napi_status #foreign libnode;

napi_get_and_clear_last_exception :: (env: napi_env, result: *napi_value) -> napi_status #foreign libnode;

// Methods to work with array buffers and typed arrays
napi_is_arraybuffer :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_create_arraybuffer :: (env: napi_env, byte_length: u64, data: **void, result: *napi_value) -> napi_status #foreign libnode;

napi_create_external_arraybuffer :: (env: napi_env, external_data: *void, byte_length: u64, finalize_cb: node_api_basic_finalize, finalize_hint: *void, result: *napi_value) -> napi_status #foreign libnode;

napi_get_arraybuffer_info :: (env: napi_env, arraybuffer: napi_value, data: **void, byte_length: *u64) -> napi_status #foreign libnode;

napi_is_typedarray :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_create_typedarray :: (env: napi_env, type: napi_typedarray_type, length: u64, arraybuffer: napi_value, byte_offset: u64, result: *napi_value) -> napi_status #foreign libnode;

napi_get_typedarray_info :: (env: napi_env, typedarray: napi_value, type: *napi_typedarray_type, length: *u64, data: **void, arraybuffer: *napi_value, byte_offset: *u64) -> napi_status #foreign libnode;

napi_create_dataview :: (env: napi_env, length: u64, arraybuffer: napi_value, byte_offset: u64, result: *napi_value) -> napi_status #foreign libnode;

napi_is_dataview :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

napi_get_dataview_info :: (env: napi_env, dataview: napi_value, bytelength: *u64, data: **void, arraybuffer: *napi_value, byte_offset: *u64) -> napi_status #foreign libnode;

// version management
napi_get_version :: (env: node_api_basic_env, result: *u32) -> napi_status #foreign libnode;

// Promises
napi_create_promise :: (env: napi_env, deferred: *napi_deferred, promise: *napi_value) -> napi_status #foreign libnode;

napi_resolve_deferred :: (env: napi_env, deferred: napi_deferred, resolution: napi_value) -> napi_status #foreign libnode;

napi_reject_deferred :: (env: napi_env, deferred: napi_deferred, rejection: napi_value) -> napi_status #foreign libnode;

napi_is_promise :: (env: napi_env, value: napi_value, is_promise: *bool) -> napi_status #foreign libnode;

// Running a script
napi_run_script :: (env: napi_env, script: napi_value, result: *napi_value) -> napi_status #foreign libnode;

// Memory management
napi_adjust_external_memory :: (env: node_api_basic_env, change_in_bytes: s64, adjusted_value: *s64) -> napi_status #foreign libnode;

// Dates
napi_create_date :: (env: napi_env, time: float64, result: *napi_value) -> napi_status #foreign libnode;

napi_is_date :: (env: napi_env, value: napi_value, is_date: *bool) -> napi_status #foreign libnode;

napi_get_date_value :: (env: napi_env, value: napi_value, result: *float64) -> napi_status #foreign libnode;

// Add finalizer for pointer
napi_add_finalizer :: (env: napi_env, js_object: napi_value, finalize_data: *void, finalize_cb: node_api_basic_finalize, finalize_hint: *void, result: *napi_ref) -> napi_status #foreign libnode;

// BigInt
napi_create_bigint_int64 :: (env: napi_env, value: s64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_bigint_uint64 :: (env: napi_env, value: u64, result: *napi_value) -> napi_status #foreign libnode;

napi_create_bigint_words :: (env: napi_env, sign_bit: s32, word_count: u64, words: *u64, result: *napi_value) -> napi_status #foreign libnode;

napi_get_value_bigint_int64 :: (env: napi_env, value: napi_value, result: *s64, lossless: *bool) -> napi_status #foreign libnode;

napi_get_value_bigint_uint64 :: (env: napi_env, value: napi_value, result: *u64, lossless: *bool) -> napi_status #foreign libnode;

napi_get_value_bigint_words :: (env: napi_env, value: napi_value, sign_bit: *s32, word_count: *u64, words: *u64) -> napi_status #foreign libnode;

// Object
napi_get_all_property_names :: (env: napi_env, object: napi_value, key_mode: napi_key_collection_mode, key_filter: napi_key_filter, key_conversion: napi_key_conversion, result: *napi_value) -> napi_status #foreign libnode;

// Instance data
napi_set_instance_data :: (env: node_api_basic_env, data: *void, finalize_cb: napi_finalize, finalize_hint: *void) -> napi_status #foreign libnode;

napi_get_instance_data :: (env: node_api_basic_env, data: **void) -> napi_status #foreign libnode;

// ArrayBuffer detaching
napi_detach_arraybuffer :: (env: napi_env, arraybuffer: napi_value) -> napi_status #foreign libnode;

napi_is_detached_arraybuffer :: (env: napi_env, value: napi_value, result: *bool) -> napi_status #foreign libnode;

// Type tagging
napi_type_tag_object :: (env: napi_env, value: napi_value, type_tag: *napi_type_tag) -> napi_status #foreign libnode;

napi_check_object_type_tag :: (env: napi_env, value: napi_value, type_tag: *napi_type_tag, result: *bool) -> napi_status #foreign libnode;

napi_object_freeze :: (env: napi_env, object: napi_value) -> napi_status #foreign libnode;

napi_object_seal :: (env: napi_env, object: napi_value) -> napi_status #foreign libnode;

#scope_file

#import "Basic"; // For assert

libnode :: #library "./vendor/libnode/aarch64-macos/libnode";
shim :: #library "./shim";

#run {
    {
        info := type_info(napi_property_descriptor);
        for info.members {
            if it.name == {
                case "utf8name";
                    assert(it.offset_in_bytes == 0, "napi_property_descriptor.utf8name has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.utf8name has unexpected size % instead of 8", it.type.runtime_size);
                case "name";
                    assert(it.offset_in_bytes == 8, "napi_property_descriptor.name has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.name has unexpected size % instead of 8", it.type.runtime_size);
                case "method";
                    assert(it.offset_in_bytes == 16, "napi_property_descriptor.method has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.method has unexpected size % instead of 8", it.type.runtime_size);
                case "getter";
                    assert(it.offset_in_bytes == 24, "napi_property_descriptor.getter has unexpected offset % instead of 24", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.getter has unexpected size % instead of 8", it.type.runtime_size);
                case "setter";
                    assert(it.offset_in_bytes == 32, "napi_property_descriptor.setter has unexpected offset % instead of 32", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.setter has unexpected size % instead of 8", it.type.runtime_size);
                case "value";
                    assert(it.offset_in_bytes == 40, "napi_property_descriptor.value has unexpected offset % instead of 40", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.value has unexpected size % instead of 8", it.type.runtime_size);
                case "attributes";
                    assert(it.offset_in_bytes == 48, "napi_property_descriptor.attributes has unexpected offset % instead of 48", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "napi_property_descriptor.attributes has unexpected size % instead of 4", it.type.runtime_size);
                case "data";
                    assert(it.offset_in_bytes == 56, "napi_property_descriptor.data has unexpected offset % instead of 56", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_property_descriptor.data has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(napi_property_descriptor) == 64, "napi_property_descriptor has size % instead of 64", size_of(napi_property_descriptor));
    }

    {
        info := type_info(napi_extended_error_info);
        for info.members {
            if it.name == {
                case "error_message";
                    assert(it.offset_in_bytes == 0, "napi_extended_error_info.error_message has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_extended_error_info.error_message has unexpected size % instead of 8", it.type.runtime_size);
                case "engine_reserved";
                    assert(it.offset_in_bytes == 8, "napi_extended_error_info.engine_reserved has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_extended_error_info.engine_reserved has unexpected size % instead of 8", it.type.runtime_size);
                case "engine_error_code";
                    assert(it.offset_in_bytes == 16, "napi_extended_error_info.engine_error_code has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "napi_extended_error_info.engine_error_code has unexpected size % instead of 4", it.type.runtime_size);
                case "error_code";
                    assert(it.offset_in_bytes == 20, "napi_extended_error_info.error_code has unexpected offset % instead of 20", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "napi_extended_error_info.error_code has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(napi_extended_error_info) == 24, "napi_extended_error_info has size % instead of 24", size_of(napi_extended_error_info));
    }

    {
        info := type_info(napi_type_tag);
        for info.members {
            if it.name == {
                case "lower";
                    assert(it.offset_in_bytes == 0, "napi_type_tag.lower has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_type_tag.lower has unexpected size % instead of 8", it.type.runtime_size);
                case "upper";
                    assert(it.offset_in_bytes == 8, "napi_type_tag.upper has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_type_tag.upper has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(napi_type_tag) == 16, "napi_type_tag has size % instead of 16", size_of(napi_type_tag));
    }

    {
        info := type_info(napi_node_version);
        for info.members {
            if it.name == {
                case "major";
                    assert(it.offset_in_bytes == 0, "napi_node_version.major has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "napi_node_version.major has unexpected size % instead of 4", it.type.runtime_size);
                case "minor";
                    assert(it.offset_in_bytes == 4, "napi_node_version.minor has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "napi_node_version.minor has unexpected size % instead of 4", it.type.runtime_size);
                case "patch";
                    assert(it.offset_in_bytes == 8, "napi_node_version.patch has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "napi_node_version.patch has unexpected size % instead of 4", it.type.runtime_size);
                case "release";
                    assert(it.offset_in_bytes == 16, "napi_node_version.release has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "napi_node_version.release has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(napi_node_version) == 24, "napi_node_version has size % instead of 24", size_of(napi_node_version));
    }
}

