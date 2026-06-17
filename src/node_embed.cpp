#include "node_embed.h"

#include "node.h"
#include "uv.h"
#include "v8.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
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
struct v8_local_value {
  v8::Local<v8::Value> val;
};
struct v8_try_catch {
  v8::TryCatch tc;
  explicit v8_try_catch(v8::Isolate *i) : tc(i) {}
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
static const v8::FunctionCallbackInfo<v8::Value> *
fci(const v8_function_callback_info *p) {
  return reinterpret_cast<const v8::FunctionCallbackInfo<v8::Value> *>(p);
}
static char *dup_cstr(const char *p) {
  size_t n = strlen(p) + 1;
  char *out = static_cast<char *>(malloc(n));
  memcpy(out, p, n);
  return out;
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
bool node_load_environment_module(node_environment *env,
                                  const char *source_utf8,
                                  const char *resource_name) {
  node::ModuleData entry;
  entry.set_source(source_utf8);
  entry.set_format(node::ModuleFormat::kModule);
  entry.set_resource_name(resource_name);
  return !node::LoadEnvironment(env_(env), &entry).IsEmpty();
}
int node_spin_event_loop(node_environment *env) {
  return node::SpinEventLoop(env_(env)).FromMaybe(1);
}
int node_stop(node_environment *env) { return node::Stop(env_(env)); }

void v8_local_value_free(v8_local_value *v) { delete v; }
v8_local_value *v8_undefined(v8_isolate *isolate) {
  return new v8_local_value{v8::Undefined(iso(isolate))};
}
bool v8_value_same_value(v8_local_value *a, v8_local_value *b) {
  return a->val->SameValue(b->val);
}
char *v8_value_to_utf8(v8_isolate *isolate, v8_local_value *v) {
  v8::String::Utf8Value s(iso(isolate), v->val);
  return dup_cstr(*s ? *s : "");
}
void v8_utf8_free(char *s) { free(s); }

v8_local_context *v8_isolate_get_current_context(v8_isolate *isolate) {
  return new v8_local_context{iso(isolate)->GetCurrentContext()};
}
void v8_isolate_throw_error(v8_isolate *isolate, const char *message_utf8) {
  auto i = iso(isolate);
  i->ThrowException(v8::Exception::Error(
      v8::String::NewFromUtf8(i, message_utf8).ToLocalChecked()));
}
v8_local_value *v8_context_global(v8_local_context *ctx) {
  return new v8_local_value{ctx->ctx->Global()};
}

v8_local_value *v8_object_new(v8_isolate *isolate) {
  return new v8_local_value{v8::Object::New(iso(isolate))};
}
void v8_object_set(v8_local_context *ctx, v8_local_value *obj, const char *key,
                   v8_local_value *value) {
  auto context = ctx->ctx;
  auto k = v8::String::NewFromUtf8(v8::Isolate::GetCurrent(), key).ToLocalChecked();
  obj->val.As<v8::Object>()->Set(context, k, value->val).Check();
}

v8_local_value *v8_function_new(v8_local_context *ctx, v8_function_callback cb,
                                v8_local_value *data) {
  v8::Local<v8::Value> d = data ? data->val : v8::Local<v8::Value>();
  auto fn = v8::Function::New(ctx->ctx,
                              reinterpret_cast<v8::FunctionCallback>(cb), d)
                .ToLocalChecked();
  return new v8_local_value{fn};
}
v8_local_value *v8_function_call(v8_local_context *ctx, v8_local_value *fn,
                                 v8_local_value *recv, int argc,
                                 v8_local_value **argv) {
  std::vector<v8::Local<v8::Value>> args;
  args.reserve(argc);
  for (int i = 0; i < argc; i++)
    args.push_back(argv[i]->val);
  auto r = fn->val.As<v8::Function>()->Call(ctx->ctx, recv->val, argc,
                                            args.data());
  if (r.IsEmpty())
    return nullptr;
  return new v8_local_value{r.ToLocalChecked()};
}

v8_isolate *v8_function_callback_info_isolate(
    const v8_function_callback_info *info) {
  return reinterpret_cast<v8_isolate *>(fci(info)->GetIsolate());
}
int v8_function_callback_info_length(const v8_function_callback_info *info) {
  return fci(info)->Length();
}
v8_local_value *v8_function_callback_info_get(
    const v8_function_callback_info *info, int i) {
  return new v8_local_value{(*fci(info))[i]};
}
v8_local_value *v8_function_callback_info_data(
    const v8_function_callback_info *info) {
  return new v8_local_value{fci(info)->Data()};
}
void v8_function_callback_info_set_return_value(
    const v8_function_callback_info *info, v8_local_value *v) {
  fci(info)->GetReturnValue().Set(v->val);
}

v8_try_catch *v8_try_catch_new(v8_isolate *isolate) {
  return new v8_try_catch(iso(isolate));
}
bool v8_try_catch_has_caught(v8_try_catch *tc) { return tc->tc.HasCaught(); }
v8_local_value *v8_try_catch_exception(v8_try_catch *tc) {
  return new v8_local_value{tc->tc.Exception()};
}
void v8_try_catch_free(v8_try_catch *tc) { delete tc; }

} // extern "C"
