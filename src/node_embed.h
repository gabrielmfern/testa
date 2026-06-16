// Thin 1:1 C wrappers over the Node.js / V8 C++ embedding API. Each function
// maps to exactly one C++ call; no orchestration lives here. C++ types that
// can't cross a C boundary are represented as opaque handles:
//   - pointers (Isolate*, Environment*, ...) pass straight through;
//   - std::unique_ptr / std::shared_ptr returns become raw owned handles with
//     an explicit *_free;
//   - RAII stack guards (Locker, *Scope) become heap objects with _new/_free
//     pairs — free them in reverse construction order (Zig `defer` does this);
//   - v8::Local<T> is a scope-bound GC handle, not a pointer, so it's boxed on
//     the heap (v8_local_context) and freed explicitly.
#ifndef NODE_EMBED_H
#define NODE_EMBED_H

#include <stdbool.h>
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
void v8_local_context_free(v8_local_context *ctx);

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
int node_spin_event_loop(node_environment *env);                                 // SpinEventLoop(env).FromMaybe(1)
int node_stop(node_environment *env);                                            // node::Stop(env)

#ifdef __cplusplus
}
#endif

#endif // NODE_EMBED_H
