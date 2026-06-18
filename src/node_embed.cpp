#include "node_embed.h"

#include "node.h"
#include "uv.h"
#include "v8.h"

#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

// Opaque boxes for the C++ values that own real state and can't cross the C
// boundary as-is. v8::Local<T> handles are NOT here: they're a single
// pointer-sized GC handle, so we hand them across as the opaque pointer itself
// (see the wrap/as_* helpers) instead of heap-boxing them.
struct node_init_result {
  std::shared_ptr<node::InitializationResult> r;
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
struct v8_try_catch {
  v8::TryCatch tc;
  explicit v8_try_catch(v8::Isolate *i) : tc(i) {}
};
// ValueView borrows V8's native string storage (Latin1 or UTF-16) with no copy,
// but pins the string against GC for its whole lifetime — so nothing may
// allocate in V8 while one is alive. Box it like the rest of the RAII guards.
struct v8_string_view {
  v8::String::ValueView v;
  v8_string_view(v8::Isolate *i, v8::Local<v8::String> s) : v(i, s) {}
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

// v8::Local<T> is one pointer-sized, trivially-copyable handle into the live
// HandleScope, so it travels across the C boundary as the opaque handle itself.
// It stays valid until its HandleScope is torn down — the same lifetime a heap
// box gave it, minus the allocation. (Relies on the standard indirect-handle
// build, where GC updates the slot rather than the handle.)
template <class T> static void *local_to_ptr(v8::Local<T> v) {
  static_assert(sizeof(v) == sizeof(void *));
  void *p;
  std::memcpy(&p, &v, sizeof(p));
  return p;
}
template <class T> static v8::Local<T> ptr_to_local(void *p) {
  v8::Local<T> v;
  std::memcpy(&v, &p, sizeof(p));
  return v;
}
static v8::Local<v8::Value> as_value(v8_local_value *p) {
  return ptr_to_local<v8::Value>(p);
}
static v8::Local<v8::Context> as_ctx(v8_local_context *p) {
  return ptr_to_local<v8::Context>(p);
}
static v8::Local<v8::Module> as_mod(v8_module *p) {
  return ptr_to_local<v8::Module>(p);
}
static v8_local_value *wrap(v8::Local<v8::Value> v) {
  return static_cast<v8_local_value *>(local_to_ptr(v));
}
static v8_local_context *wrap(v8::Local<v8::Context> v) {
  return static_cast<v8_local_context *>(local_to_ptr(v));
}
static v8_module *wrap(v8::Local<v8::Module> v) {
  return static_cast<v8_module *>(local_to_ptr(v));
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
  return wrap(setup_(s)->context());
}

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
  return new v8_context_scope(as_ctx(ctx));
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

v8_local_value *v8_undefined(v8_isolate *isolate) {
  return wrap(v8::Undefined(iso(isolate)));
}
bool v8_value_same_value(v8_local_value *a, v8_local_value *b) {
  return as_value(a)->SameValue(as_value(b));
}
v8_local_value *v8_value_to_string(v8_isolate *isolate, v8_local_value *v) {
  auto i = iso(isolate);
  v8::Local<v8::String> s;
  if (!as_value(v)->ToString(i->GetCurrentContext()).ToLocal(&s))
    s = v8::String::Empty(i);
  return wrap(s.As<v8::Value>());
}
v8_string_view *v8_string_view_new(v8_isolate *isolate, v8_local_value *str) {
  return new v8_string_view(iso(isolate), as_value(str).As<v8::String>());
}
bool v8_string_view_is_one_byte(v8_string_view *s) {
  return s->v.is_one_byte();
}
const void *v8_string_view_data(v8_string_view *s) {
  return s->v.is_one_byte() ? static_cast<const void *>(s->v.data8())
                            : static_cast<const void *>(s->v.data16());
}
size_t v8_string_view_len(v8_string_view *s) { return s->v.length(); }
void v8_string_view_free(v8_string_view *s) { delete s; }

v8_local_context *v8_isolate_get_current_context(v8_isolate *isolate) {
  return wrap(iso(isolate)->GetCurrentContext());
}
void v8_isolate_throw_error(v8_isolate *isolate, const char *message_utf8) {
  auto i = iso(isolate);
  i->ThrowException(v8::Exception::Error(
      v8::String::NewFromUtf8(i, message_utf8).ToLocalChecked()));
}
v8_local_value *v8_context_global(v8_local_context *ctx) {
  return wrap(as_ctx(ctx)->Global().As<v8::Value>());
}

v8_local_value *v8_object_new(v8_isolate *isolate) {
  return wrap(v8::Object::New(iso(isolate)));
}
void v8_object_set(v8_local_context *ctx, v8_local_value *obj, const char *key,
                   v8_local_value *value) {
  auto context = as_ctx(ctx);
  auto k = v8::String::NewFromUtf8(v8::Isolate::GetCurrent(), key).ToLocalChecked();
  as_value(obj).As<v8::Object>()->Set(context, k, as_value(value)).Check();
}

v8_local_value *v8_function_new(v8_local_context *ctx, v8_function_callback cb,
                                v8_local_value *data) {
  v8::Local<v8::Value> d = data ? as_value(data) : v8::Local<v8::Value>();
  auto fn = v8::Function::New(as_ctx(ctx),
                              reinterpret_cast<v8::FunctionCallback>(cb), d)
                .ToLocalChecked();
  return wrap(fn);
}
v8_local_value *v8_function_call(v8_local_context *ctx, v8_local_value *fn,
                                 v8_local_value *recv, int argc,
                                 v8_local_value **argv) {
  std::vector<v8::Local<v8::Value>> args;
  args.reserve(argc);
  for (int i = 0; i < argc; i++)
    args.push_back(as_value(argv[i]));
  auto r = as_value(fn).As<v8::Function>()->Call(as_ctx(ctx), as_value(recv),
                                                 argc, args.data());
  if (r.IsEmpty())
    return nullptr;
  return wrap(r.ToLocalChecked());
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
  return wrap((*fci(info))[i]);
}
v8_local_value *v8_function_callback_info_data(
    const v8_function_callback_info *info) {
  return wrap(fci(info)->Data());
}
void v8_function_callback_info_set_return_value(
    const v8_function_callback_info *info, v8_local_value *v) {
  fci(info)->GetReturnValue().Set(as_value(v));
}

v8_try_catch *v8_try_catch_new(v8_isolate *isolate) {
  return new v8_try_catch(iso(isolate));
}
bool v8_try_catch_has_caught(v8_try_catch *tc) { return tc->tc.HasCaught(); }
v8_local_value *v8_try_catch_exception(v8_try_catch *tc) {
  return wrap(tc->tc.Exception());
}
void v8_try_catch_free(v8_try_catch *tc) { delete tc; }

// v8::Module::ResolveModuleCallback is a bare C function pointer with no
// userdata slot, so the Zig resolver is stashed here for the duration of one
// (synchronous, single-threaded under the Locker) InstantiateModule call and
// read back by the trampoline below.
static thread_local v8_resolve_callback g_resolve = nullptr;

static v8::MaybeLocal<v8::Module>
resolve_trampoline(v8::Local<v8::Context> context,
                   v8::Local<v8::String> specifier,
                   v8::Local<v8::FixedArray> import_attributes,
                   v8::Local<v8::Module> referrer) {
  (void)import_attributes;
  if (!g_resolve)
    return v8::MaybeLocal<v8::Module>();
  v8::String::Utf8Value spec(v8::Isolate::GetCurrent(), specifier);
  v8_module *res = g_resolve(wrap(context), *spec ? *spec : "", wrap(referrer));
  if (!res)
    return v8::MaybeLocal<v8::Module>(); // throws in the importing module
  return as_mod(res);
}

v8_module *v8_compile_module(v8_local_context *ctx, const char *source_utf8,
                             const char *resource_name) {
  auto isolate = v8::Isolate::GetCurrent();
  auto src = v8::String::NewFromUtf8(isolate, source_utf8).ToLocalChecked();
  auto name = v8::String::NewFromUtf8(isolate, resource_name).ToLocalChecked();
  // The trailing `true` is ScriptOrigin's is_module flag.
  v8::ScriptOrigin origin(name, 0, 0, false, -1, v8::Local<v8::Value>(), false,
                          false, true);
  v8::ScriptCompiler::Source source(src, origin);
  v8::Local<v8::Module> mod;
  if (!v8::ScriptCompiler::CompileModule(isolate, &source).ToLocal(&mod))
    return nullptr; // syntax error; inspect via a v8_try_catch around this call
  return wrap(mod);
}
int v8_module_identity_hash(v8_module *m) { return as_mod(m)->GetIdentityHash(); }

bool v8_module_instantiate(v8_local_context *ctx, v8_module *m,
                           v8_resolve_callback cb) {
  g_resolve = cb;
  bool ok = as_mod(m)->InstantiateModule(as_ctx(ctx), &resolve_trampoline)
                .FromMaybe(false);
  g_resolve = nullptr;
  return ok;
}
v8_local_value *v8_module_evaluate(v8_local_context *ctx, v8_module *m) {
  v8::Local<v8::Value> result;
  if (!as_mod(m)->Evaluate(as_ctx(ctx)).ToLocal(&result))
    return nullptr;
  return wrap(result);
}
int v8_module_get_status(v8_module *m) {
  return static_cast<int>(as_mod(m)->GetStatus());
}
v8_local_value *v8_module_get_exception(v8_module *m) {
  return wrap(as_mod(m)->GetException());
}

} // extern "C"
