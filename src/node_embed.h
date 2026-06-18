// Thin 1:1 C wrappers over the Node.js / V8 C++ embedding API. Each function
// maps to exactly one C++ call; no orchestration lives here. C++ types that
// can't cross a C boundary are represented as opaque handles:
//   - pointers (Isolate*, Environment*, ...) pass straight through;
//   - std::unique_ptr / std::shared_ptr returns become raw owned handles with
//     an explicit *_free;
//   - RAII stack guards (Locker, *Scope, TryCatch) become heap objects with
//     _new/_free pairs — free them in reverse construction order (Zig `defer`
//     does this);
//   - v8::Local<T> is a single pointer-sized GC handle, so it crosses as the
//     opaque handle itself (v8_local_value / v8_local_context / v8_module), no
//     box and no free; it stays valid until its HandleScope is torn down.
#ifndef NODE_EMBED_H
#define NODE_EMBED_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct node_init_result node_init_result;
typedef struct v8_platform v8_platform;
typedef struct node_common_setup node_common_setup;
typedef struct v8_isolate v8_isolate;
typedef struct node_environment node_environment;
typedef struct v8_local_context v8_local_context;
typedef struct v8_locker v8_locker;
typedef struct v8_isolate_scope v8_isolate_scope;
typedef struct v8_handle_scope v8_handle_scope;
typedef struct v8_context_scope v8_context_scope;
typedef struct v8_local_value v8_local_value;
typedef struct v8_try_catch v8_try_catch;
// A v8::FunctionCallbackInfo<Value>&, opaque. v8 passes the callback a
// reference; a reference is a pointer at the ABI level, so the Zig callback
// receives this as a plain pointer.
typedef struct v8_function_callback_info v8_function_callback_info;
typedef void (*v8_function_callback)(const v8_function_callback_info *info);

// node::ProcessInitializationFlags::Flags (the values this example uses)
enum {
  NODE_INIT_NO_INITIALIZE_V8 = 1 << 6,
  NODE_INIT_NO_INITIALIZE_NODE_V8_PLATFORM = 1 << 7,
};

// ===== node::InitializeOncePerProcess / TearDownOncePerProcess =====
// Calls uv_setup_args(argc, argv) then InitializeOncePerProcess. `flags` is an
// OR of the NODE_INIT_* values above.
node_init_result *node_initialize_once_per_process(int argc, char **argv, uint64_t flags);
void node_teardown_once_per_process(void); // node::TearDownOncePerProcess

// node::InitializationResult accessors
int node_init_result_exit_code(node_init_result *r);
bool node_init_result_early_return(node_init_result *r);
int node_init_result_error_count(node_init_result *r);
const char *node_init_result_error_at(node_init_result *r, int i);
void node_init_result_free(node_init_result *r); // drops the shared_ptr

// ===== node::MultiIsolatePlatform =====
v8_platform *node_multi_isolate_platform_create(int thread_pool_size); // ::Create(n)
void node_multi_isolate_platform_free(v8_platform *p);

// ===== v8::V8 =====
void v8_initialize_platform(v8_platform *platform); // V8::InitializePlatform
bool v8_initialize(void);                           // V8::Initialize
bool v8_dispose(void);                              // V8::Dispose
void v8_dispose_platform(void);                     // V8::DisposePlatform

// ===== node::CommonEnvironmentSetup =====
// ::Create(platform, &errors, r->args(), r->exec_args()). Returns NULL on
// error (errors printed to stderr).
node_common_setup *node_common_environment_setup_create(v8_platform *platform, node_init_result *r);
void node_common_environment_setup_free(node_common_setup *s);
v8_isolate *node_common_environment_setup_isolate(node_common_setup *s);   // ->isolate()
node_environment *node_common_environment_setup_env(node_common_setup *s); // ->env()
v8_local_context *node_common_environment_setup_context(node_common_setup *s); // ->context()

// ===== v8 RAII guards (construct on heap, free in reverse order) =====
v8_locker *v8_locker_new(v8_isolate *isolate);
void v8_locker_free(v8_locker *l);
v8_isolate_scope *v8_isolate_scope_new(v8_isolate *isolate);
void v8_isolate_scope_free(v8_isolate_scope *s);
v8_handle_scope *v8_handle_scope_new(v8_isolate *isolate);
void v8_handle_scope_free(v8_handle_scope *s);
v8_context_scope *v8_context_scope_new(v8_local_context *ctx);
void v8_context_scope_free(v8_context_scope *s);

// ===== node environment execution =====
bool node_load_environment(node_environment *env, const char *main_script_utf8); // !MaybeLocal.IsEmpty()
// LoadEnvironment with an ES Module entry point (ModuleData + ModuleFormat::
// kModule). Unlike the CJS string form, this sets up node's real module loader,
// so userland import()/import of files works. resource_name is the entry's URL.
bool node_load_environment_module(node_environment *env, const char *source_utf8, const char *resource_name);
int node_spin_event_loop(node_environment *env);                                 // SpinEventLoop(env).FromMaybe(1)
int node_stop(node_environment *env);                                            // node::Stop(env)

// ===== v8::Value (Local<Value> carried as an opaque, scope-lived handle) =====
v8_local_value *v8_undefined(v8_isolate *isolate);                  // v8::Undefined
bool v8_value_same_value(v8_local_value *a, v8_local_value *b);     // Value::SameValue (Object.is)
// A string's raw bytes borrowed from V8 with no copy: one_byte true => `data` is
// const uint8_t* (Latin1), false => const uint16_t* (UTF-16); `len` is in
// characters. Kept to 16 bytes so it returns in registers, not via sret.
typedef struct {
  const void *data;
  unsigned int len;
  bool one_byte;
} v8_string_bytes;
// ToString the value (allocates a V8 string for non-strings; no copy on our
// side) and return its native bytes. The v8::String::ValueView that borrows them
// is built and destroyed on the C++ stack — zero allocation here — so the bytes
// are NOT pinned after this returns: read them before the next V8 call, since
// any V8 allocation can move the string.
v8_string_bytes v8_value_string_bytes(v8_isolate *isolate, v8_local_value *value);

// ===== v8::Isolate / v8::Context =====
v8_local_context *v8_isolate_get_current_context(v8_isolate *isolate); // ->GetCurrentContext()
void v8_isolate_throw_error(v8_isolate *isolate, const char *message_utf8); // ThrowException(Exception::Error)
v8_local_value *v8_context_global(v8_local_context *ctx);              // ->Global()

// ===== v8::Object =====
v8_local_value *v8_object_new(v8_isolate *isolate);                                              // Object::New
void v8_object_set(v8_local_context *ctx, v8_local_value *obj, const char *key, v8_local_value *value); // ->Set

// ===== v8::Function =====
v8_local_value *v8_function_new(v8_local_context *ctx, v8_function_callback cb, v8_local_value *data); // Function::New
// f->Call(ctx, recv, argc, argv); NULL if it threw.
v8_local_value *v8_function_call(v8_local_context *ctx, v8_local_value *fn, v8_local_value *recv, int argc, v8_local_value **argv);

// ===== v8::FunctionCallbackInfo accessors =====
v8_isolate *v8_function_callback_info_isolate(const v8_function_callback_info *info); // ->GetIsolate()
int v8_function_callback_info_length(const v8_function_callback_info *info);          // ->Length()
v8_local_value *v8_function_callback_info_get(const v8_function_callback_info *info, int i); // info[i]
v8_local_value *v8_function_callback_info_data(const v8_function_callback_info *info);       // ->Data()
void v8_function_callback_info_set_return_value(const v8_function_callback_info *info, v8_local_value *v); // ->GetReturnValue().Set

// ===== v8::TryCatch =====
v8_try_catch *v8_try_catch_new(v8_isolate *isolate);
bool v8_try_catch_has_caught(v8_try_catch *tc);          // ->HasCaught()
v8_local_value *v8_try_catch_exception(v8_try_catch *tc); // ->Exception()
void v8_try_catch_free(v8_try_catch *tc);

// ===== v8::Module (compile / link / evaluate ES modules yourself) =====
// A v8::Local<v8::Module> carried as an opaque handle, like v8_local_value:
// lives within the enclosing HandleScope, no free.
typedef struct v8_module v8_module;

// v8::Module::Status, mirrored. Valid return of v8_module_get_status.
enum {
  V8_MODULE_UNINSTANTIATED = 0,
  V8_MODULE_INSTANTIATING,
  V8_MODULE_INSTANTIATED,
  V8_MODULE_EVALUATING,
  V8_MODULE_EVALUATED,
  V8_MODULE_ERRORED,
};

// Called by v8 (synchronously, during v8_module_instantiate) once per import in
// the graph. Return the compiled module for `specifier` as imported from
// `referrer`, or NULL to make that import throw. Use v8_module_identity_hash on
// `referrer` to find which file is importing. `ctx` and `referrer` are BORROWED
// for the duration of the call — do NOT free them. Return the same module
// instance for a repeated (referrer, specifier) so cycles terminate.
typedef v8_module *(*v8_resolve_callback)(v8_local_context *ctx,
                                          const char *specifier,
                                          v8_module *referrer);

// ScriptCompiler::CompileModule with is_module origin. resource_name is the
// module's URL/path (used in stack traces and as the resolve base). Returns
// NULL on a syntax error; wrap the call in a v8_try_catch to read it.
v8_module *v8_compile_module(v8_local_context *ctx, const char *source_utf8, const char *resource_name);
int v8_module_identity_hash(v8_module *m); // ->GetIdentityHash(), stable cache key
// ->InstantiateModule(ctx, cb). false if instantiation threw. cb resolves the
// whole graph; only call evaluate after this returns true.
bool v8_module_instantiate(v8_local_context *ctx, v8_module *m, v8_resolve_callback cb);
// ->Evaluate(ctx). Returns the completion value (a Promise under top-level
// await — spin the event loop to settle it). NULL if it threw synchronously.
v8_local_value *v8_module_evaluate(v8_local_context *ctx, v8_module *m);
int v8_module_get_status(v8_module *m);                 // ->GetStatus() (V8_MODULE_*)
v8_local_value *v8_module_get_exception(v8_module *m);  // ->GetException(), valid only when ERRORED

#ifdef __cplusplus
}
#endif

#endif // NODE_EMBED_H
