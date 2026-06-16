#include "node_embed.h"

#include "node.h"
#include "uv.h"
#include "v8.h"

#include <cstdio>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

// Opaque boxes for the C++ values that can't cross the C boundary as-is.
struct node_init_result {
  std::shared_ptr<node::InitializationResult> r;
};
struct v8_local_context {
  v8::Local<v8::Context> ctx;
};
// RAII guards are non-movable, so construct them in place via a constructor.
struct v8_locker {
  v8::Locker l;
  explicit v8_locker(v8::Isolate *i) : l(i) {}
};
struct v8_isolate_scope {
  v8::Isolate::Scope s;
  explicit v8_isolate_scope(v8::Isolate *i) : s(i) {}
};
struct v8_handle_scope {
  v8::HandleScope s;
  explicit v8_handle_scope(v8::Isolate *i) : s(i) {}
};
struct v8_context_scope {
  v8::Context::Scope s;
  explicit v8_context_scope(v8::Local<v8::Context> c) : s(c) {}
};

// Plain pointers reinterpret directly.
static v8::Isolate *iso(v8_isolate *p) {
  return reinterpret_cast<v8::Isolate *>(p);
}
static node::Environment *env_(node_environment *p) {
  return reinterpret_cast<node::Environment *>(p);
}
static node::MultiIsolatePlatform *plat(v8_platform *p) {
  return reinterpret_cast<node::MultiIsolatePlatform *>(p);
}
static node::CommonEnvironmentSetup *setup_(node_common_setup *p) {
  return reinterpret_cast<node::CommonEnvironmentSetup *>(p);
}

extern "C" {

node_init_result *node_initialize_once_per_process(int argc, char **argv,
                                                   uint64_t flags) {
  argv = uv_setup_args(argc, argv);
  std::vector<std::string> args(argv, argv + argc);
  auto r = node::InitializeOncePerProcess(
      args, static_cast<node::ProcessInitializationFlags::Flags>(flags));
  return new node_init_result{std::move(r)};
}
void node_teardown_once_per_process(void) { node::TearDownOncePerProcess(); }

int node_init_result_exit_code(node_init_result *r) {
  return r->r->exit_code();
}
bool node_init_result_early_return(node_init_result *r) {
  return r->r->early_return();
}
int node_init_result_error_count(node_init_result *r) {
  return static_cast<int>(r->r->errors().size());
}
const char *node_init_result_error_at(node_init_result *r, int i) {
  return r->r->errors()[i].c_str();
}
void node_init_result_free(node_init_result *r) { delete r; }

v8_platform *node_multi_isolate_platform_create(int thread_pool_size) {
  return reinterpret_cast<v8_platform *>(
      node::MultiIsolatePlatform::Create(thread_pool_size).release());
}
void node_multi_isolate_platform_free(v8_platform *p) {
  std::unique_ptr<node::MultiIsolatePlatform>(plat(p));
}

void v8_initialize_platform(v8_platform *platform) {
  v8::V8::InitializePlatform(plat(platform));
}
bool v8_initialize(void) { return v8::V8::Initialize(); }
bool v8_dispose(void) { return v8::V8::Dispose(); }
void v8_dispose_platform(void) { v8::V8::DisposePlatform(); }

node_common_setup *node_common_environment_setup_create(v8_platform *platform,
                                                        node_init_result *r) {
  std::vector<std::string> errors;
  auto setup = node::CommonEnvironmentSetup::Create(
      plat(platform), &errors, r->r->args(), r->r->exec_args());
  if (!setup) {
    for (const std::string &e : errors)
      fprintf(stderr, "node setup error: %s\n", e.c_str());
    return nullptr;
  }
  return reinterpret_cast<node_common_setup *>(setup.release());
}
void node_common_environment_setup_free(node_common_setup *s) {
  std::unique_ptr<node::CommonEnvironmentSetup>(setup_(s));
}
v8_isolate *node_common_environment_setup_isolate(node_common_setup *s) {
  return reinterpret_cast<v8_isolate *>(setup_(s)->isolate());
}
node_environment *node_common_environment_setup_env(node_common_setup *s) {
  return reinterpret_cast<node_environment *>(setup_(s)->env());
}
v8_local_context *node_common_environment_setup_context(node_common_setup *s) {
  return new v8_local_context{setup_(s)->context()};
}
void v8_local_context_free(v8_local_context *ctx) { delete ctx; }

v8_locker *v8_locker_new(v8_isolate *isolate) {
  return new v8_locker(iso(isolate));
}
void v8_locker_free(v8_locker *l) { delete l; }
v8_isolate_scope *v8_isolate_scope_new(v8_isolate *isolate) {
  return new v8_isolate_scope(iso(isolate));
}
void v8_isolate_scope_free(v8_isolate_scope *s) { delete s; }
v8_handle_scope *v8_handle_scope_new(v8_isolate *isolate) {
  return new v8_handle_scope(iso(isolate));
}
void v8_handle_scope_free(v8_handle_scope *s) { delete s; }
v8_context_scope *v8_context_scope_new(v8_local_context *ctx) {
  return new v8_context_scope(ctx->ctx);
}
void v8_context_scope_free(v8_context_scope *s) { delete s; }

bool node_load_environment(node_environment *env,
                           const char *main_script_utf8) {
  return !node::LoadEnvironment(env_(env), std::string_view(main_script_utf8))
              .IsEmpty();
}
int node_spin_event_loop(node_environment *env) {
  return node::SpinEventLoop(env_(env)).FromMaybe(1);
}
int node_stop(node_environment *env) { return node::Stop(env_(env)); }

} // extern "C"
