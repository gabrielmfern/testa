// Thin 1:1 C wrappers over the Node.js / V8 C++ embedding API. Each function
// maps to exactly one C++ call; no orchestration lives here. C++ types that
// can't cross a C boundary are represented as opaque handles:
//   - pointers (Isolate*, Environment*, ...) pass straight through;
//   - owning C++ returns (platform, the array-buffer allocator, the uv loop)
//     become raw owned handles with an explicit *_free / *_close;
//   - RAII stack guards (Locker, *Scope, TryCatch) and the init result are
//     placement-constructed into caller-owned storage (a sized, aligned union
//     declared below): reserve one on the stack, *_init into it, *_deinit in
//     reverse construction order (Zig `defer` does this). No heap, no free;
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

typedef struct v8_platform v8_platform;
typedef struct uv_loop uv_loop;
typedef struct node_array_buffer_allocator node_array_buffer_allocator;
typedef struct v8_isolate v8_isolate;
typedef struct node_isolate_data node_isolate_data;
typedef struct node_environment node_environment;
typedef struct v8_local_context v8_local_context;
typedef struct v8_local_value v8_local_value;
// A v8::FunctionCallbackInfo<Value>&, opaque. v8 passes the callback a
// reference; a reference is a pointer at the ABI level, so the Zig callback
// receives this as a plain pointer.
typedef struct v8_function_callback_info v8_function_callback_info;
typedef void (*v8_function_callback)(const v8_function_callback_info *info);

// ===== Caller-owned storage for stack-allocated C++ objects =====
// These C++ objects (the init result's shared_ptr, the v8 RAII guards, and
// TryCatch) used to be heap-boxed in node_embed.cpp. Instead the caller reserves
// one of these blobs on its stack, hands the address to the matching *_init, and
// tears it down with *_deinit. The C++ side placement-constructs the real object
// into the blob, so there is no heap allocation and nothing to free. Each blob's
// byte count is an upper bound on its object's size (static_assert'd in
// node_embed.cpp; bump it if one fires); the void* member forces the pointer
// alignment every boxed type needs.
typedef union { void *_align; unsigned char _bytes[16]; } node_init_result;
typedef union { void *_align; unsigned char _bytes[24]; } v8_locker;
typedef union { void *_align; unsigned char _bytes[8]; } v8_isolate_scope;
typedef union { void *_align; unsigned char _bytes[40]; } v8_handle_scope;
typedef union { void *_align; unsigned char _bytes[8]; } v8_context_scope;
typedef union { void *_align; unsigned char _bytes[64]; } v8_try_catch;

// node::ProcessInitializationFlags::Flags (the values this example uses)
enum {
  NODE_INIT_NO_INITIALIZE_V8 = 1 << 6,
  NODE_INIT_NO_INITIALIZE_NODE_V8_PLATFORM = 1 << 7,
};

// ===== node::InitializeOncePerProcess / TearDownOncePerProcess =====
// Calls uv_setup_args(argc, argv) then InitializeOncePerProcess, storing the
// resulting shared_ptr into caller-owned `out`. `flags` is an OR of the
// NODE_INIT_* values above.
void node_initialize_once_per_process(int argc, char **argv, uint64_t flags, node_init_result *out);
void node_teardown_once_per_process(void); // node::TearDownOncePerProcess

// node::InitializationResult accessors
int node_init_result_exit_code(node_init_result *r);
bool node_init_result_early_return(node_init_result *r);
int node_init_result_error_count(node_init_result *r);
const char *node_init_result_error_at(node_init_result *r, int i);
void node_init_result_deinit(node_init_result *r); // destroys the shared_ptr in place

// ===== node::MultiIsolatePlatform =====
v8_platform *node_multi_isolate_platform_create(int thread_pool_size); // ::Create(n)
void node_multi_isolate_platform_free(v8_platform *p);

// ===== v8::V8 =====
void v8_initialize_platform(v8_platform *platform); // V8::InitializePlatform
bool v8_initialize(void);                           // V8::Initialize
bool v8_dispose(void);                              // V8::Dispose
void v8_dispose_platform(void);                     // V8::DisposePlatform

// node::EnvironmentFlags::Flags, the subset the runner sets (OR them for
// node_create_environment). kDefaultFlags keeps the full Node runtime; the two
// No* flags drop only the inspector agent and its SIGUSR1 debug i/o thread.
enum {
  NODE_ENV_DEFAULT_FLAGS = 1 << 0,
  NODE_ENV_NO_CREATE_INSPECTOR = 1 << 9,
  NODE_ENV_NO_START_DEBUG_SIGNAL_HANDLER = 1 << 10,
};

// ===== Node environment primitives (assembled into a setup by main.zig) =====
// One C++ call each; the create/teardown ORDER lives in Zig. We build the
// environment from these instead of node::CommonEnvironmentSetup so the caller
// owns the EnvironmentFlags (see NODE_ENV_* above) — CommonEnvironmentSetup always
// owns and starts the inspector agent, whose Agent::Start spawns a debug i/o
// thread we never use. Every user-facing Node global (process, Buffer, fs, timers,
// console, fetch, ...) stays available; only the inspector/debugger is dropped.
// Create order: loop -> allocator -> isolate -> (enter Locker/scopes) ->
// isolate_data -> context -> environment. Teardown is the reverse, with
// free_environment/free_isolate_data while the isolate is still entered, then
// unregister + dispose + drain the loop (via the finished callback) + close.
uv_loop *node_uv_loop_create(void);    // new uv_loop_t + uv_loop_init
void node_uv_loop_close(uv_loop *l);   // uv_loop_close + delete
int node_uv_run_once(uv_loop *l);      // uv_run(l, UV_RUN_ONCE); nonzero => still alive
node_array_buffer_allocator *node_array_buffer_allocator_create(void); // node::CreateArrayBufferAllocator
void node_array_buffer_allocator_free(node_array_buffer_allocator *a);  // node::FreeArrayBufferAllocator
v8_isolate *node_new_isolate(node_array_buffer_allocator *a, uv_loop *l, v8_platform *p); // node::NewIsolate
node_isolate_data *node_create_isolate_data(v8_isolate *isolate, uv_loop *l, v8_platform *p, node_array_buffer_allocator *a); // node::CreateIsolateData
v8_local_context *node_new_context(v8_isolate *isolate); // node::NewContext (NULL if empty)
// node::CreateEnvironment(d, ctx, r->args(), r->exec_args(), flags). flags is an OR
// of NODE_ENV_*; `r` is the init result. NULL on failure (e.g. a pending exception
// thrown during bootstrap).
node_environment *node_create_environment(node_isolate_data *d, v8_local_context *ctx, node_init_result *r, uint64_t flags);
void node_free_environment(node_environment *e);    // node::FreeEnvironment
void node_free_isolate_data(node_isolate_data *d);  // node::FreeIsolateData
void node_isolate_dispose(v8_isolate *isolate);     // isolate->Dispose()
void node_platform_unregister_isolate(v8_platform *p, v8_isolate *isolate); // ->UnregisterIsolate
// ->AddIsolateFinishedCallback: the platform calls cb(data) once the isolate's
// resources are released. Used to drain the loop before closing it.
void node_platform_add_isolate_finished_callback(v8_platform *p, v8_isolate *isolate, void (*cb)(void *), void *data);

// ===== v8 RAII guards (construct into caller storage, deinit in reverse order) =====
void v8_locker_init(v8_locker *l, v8_isolate *isolate);
void v8_locker_deinit(v8_locker *l);
void v8_isolate_scope_init(v8_isolate_scope *s, v8_isolate *isolate);
void v8_isolate_scope_deinit(v8_isolate_scope *s);
void v8_handle_scope_init(v8_handle_scope *s, v8_isolate *isolate);
void v8_handle_scope_deinit(v8_handle_scope *s);
void v8_context_scope_init(v8_context_scope *s, v8_local_context *ctx);
void v8_context_scope_deinit(v8_context_scope *s);

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
// Drain the microtask queue now. Under Node's explicit microtask policy, promise
// continuations (async/await) don't run between event-loop turns on their own;
// call this at the top level (never re-entrantly from inside a callback) to flush
// them. A safe no-op when microtasks can't currently run.
void v8_isolate_perform_microtask_checkpoint(v8_isolate *isolate); // ->PerformMicrotaskCheckpoint()

// ===== v8::Object =====
v8_local_value *v8_object_new(v8_isolate *isolate);                                              // Object::New
void v8_object_set(v8_local_context *ctx, v8_local_value *obj, const char *key, v8_local_value *value); // ->Set
v8_local_value *v8_object_get(v8_local_context *ctx, v8_local_value *obj, const char *key);       // ->Get; NULL if it threw

// ===== v8::Boolean =====
v8_local_value *v8_boolean_new(v8_isolate *isolate, bool value); // Boolean::New

// ===== v8::Function =====
v8_local_value *v8_function_new(v8_local_context *ctx, v8_function_callback cb, v8_local_value *data); // Function::New
// f->Call(ctx, recv, argc, argv); NULL if it threw.
v8_local_value *v8_function_call(v8_local_context *ctx, v8_local_value *fn, v8_local_value *recv, int argc, v8_local_value **argv);

// ===== v8::Promise =====
// v8::Promise::PromiseState, mirrored. The return of v8_promise_state.
enum {
  V8_PROMISE_PENDING = 0,
  V8_PROMISE_FULFILLED,
  V8_PROMISE_REJECTED,
};
bool v8_value_is_promise(v8_local_value *v);   // v->IsPromise()
int v8_promise_state(v8_local_value *promise); // Promise::Cast(v)->State()
// ->Result(): the fulfilled value or the rejection reason. Only meaningful once
// the promise has left the V8_PROMISE_PENDING state.
v8_local_value *v8_promise_result(v8_local_value *promise);
// Mark a promise as handled so Node won't report its rejection as an unhandled
// rejection (which it treats as fatal). Set it up front on a promise whose result
// you inspect yourself, before it has a chance to reject.
void v8_promise_mark_as_handled(v8_local_value *promise); // Promise::Cast(v)->MarkAsHandled()

// ===== v8::FunctionCallbackInfo accessors =====
v8_isolate *v8_function_callback_info_isolate(const v8_function_callback_info *info); // ->GetIsolate()
int v8_function_callback_info_length(const v8_function_callback_info *info);          // ->Length()
v8_local_value *v8_function_callback_info_get(const v8_function_callback_info *info, int i); // info[i]
v8_local_value *v8_function_callback_info_data(const v8_function_callback_info *info);       // ->Data()
void v8_function_callback_info_set_return_value(const v8_function_callback_info *info, v8_local_value *v); // ->GetReturnValue().Set

// ===== v8::TryCatch =====
void v8_try_catch_init(v8_try_catch *tc, v8_isolate *isolate);
bool v8_try_catch_has_caught(v8_try_catch *tc);          // ->HasCaught()
v8_local_value *v8_try_catch_exception(v8_try_catch *tc); // ->Exception()
void v8_try_catch_deinit(v8_try_catch *tc);

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
