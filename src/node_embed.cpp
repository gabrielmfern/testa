#include "node_embed.h"

#include "node.h"
#include "uv.h"
#include "v8.h"

#include <cmath>
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
struct v8_module {
  v8::Local<v8::Module> mod;
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
bool v8_value_strict_equals(v8_local_value *a, v8_local_value *b) {
  return a->val->StrictEquals(b->val);
}
char *v8_value_to_utf8(v8_isolate *isolate, v8_local_value *v) {
  auto i = iso(isolate);
  v8::Local<v8::String> str;
  if (!v->val->ToString(i->GetCurrentContext()).ToLocal(&str))
    return dup_cstr("");
  size_t len = str->Utf8LengthV2(i);
  char *out = static_cast<char *>(malloc(len + 1));
  str->WriteUtf8V2(i, out, len + 1, v8::String::WriteFlags::kNullTerminate);
  return out;
}
void v8_utf8_free(char *s) { free(s); }

bool v8_value_is_undefined(v8_local_value *v) { return v->val->IsUndefined(); }
bool v8_value_is_null(v8_local_value *v) { return v->val->IsNull(); }
bool v8_value_is_number(v8_local_value *v) { return v->val->IsNumber(); }
bool v8_value_is_string(v8_local_value *v) { return v->val->IsString(); }
bool v8_value_is_boolean(v8_local_value *v) { return v->val->IsBoolean(); }
bool v8_value_is_array(v8_local_value *v) { return v->val->IsArray(); }
bool v8_value_is_object(v8_local_value *v) { return v->val->IsObject(); }
bool v8_value_is_function(v8_local_value *v) { return v->val->IsFunction(); }
bool v8_value_is_date(v8_local_value *v) { return v->val->IsDate(); }
bool v8_value_is_regexp(v8_local_value *v) { return v->val->IsRegExp(); }
bool v8_value_is_map(v8_local_value *v) { return v->val->IsMap(); }
bool v8_value_is_set(v8_local_value *v) { return v->val->IsSet(); }
bool v8_value_is_promise(v8_local_value *v) { return v->val->IsPromise(); }
double v8_value_number(v8_local_context *ctx, v8_local_value *v) {
  double out;
  if (!v->val->NumberValue(ctx->ctx).To(&out))
    return std::nan("");
  return out;
}
bool v8_value_boolean(v8_isolate *isolate, v8_local_value *v) {
  return v->val->BooleanValue(iso(isolate));
}
char *v8_value_typeof(v8_isolate *isolate, v8_local_value *v) {
  v8::String::Utf8Value s(iso(isolate), v->val->TypeOf(iso(isolate)));
  return dup_cstr(*s ? *s : "");
}
bool v8_value_instance_of(v8_local_context *ctx, v8_local_value *obj,
                          v8_local_value *ctor) {
  if (!ctor->val->IsObject())
    return false;
  bool out;
  if (!obj->val->InstanceOf(ctx->ctx, ctor->val.As<v8::Object>()).To(&out))
    return false;
  return out;
}
int v8_string_length(v8_local_value *v) {
  if (!v->val->IsString())
    return -1;
  return v->val.As<v8::String>()->Length();
}

uint32_t v8_array_length(v8_local_value *v) {
  return v->val.As<v8::Array>()->Length();
}
v8_local_value *v8_array_get(v8_local_context *ctx, v8_local_value *arr,
                             uint32_t i) {
  v8::Local<v8::Value> out;
  if (!arr->val.As<v8::Array>()->Get(ctx->ctx, i).ToLocal(&out))
    return new v8_local_value{v8::Undefined(v8::Isolate::GetCurrent())};
  return new v8_local_value{out};
}
v8_local_value *v8_object_get_key(v8_local_context *ctx, v8_local_value *obj,
                                  const char *key) {
  auto isolate = v8::Isolate::GetCurrent();
  auto k = v8::String::NewFromUtf8(isolate, key).ToLocalChecked();
  v8::Local<v8::Value> out;
  if (!obj->val.As<v8::Object>()->Get(ctx->ctx, k).ToLocal(&out))
    return new v8_local_value{v8::Undefined(isolate)};
  return new v8_local_value{out};
}
bool v8_object_has_key(v8_local_context *ctx, v8_local_value *obj,
                       const char *key) {
  auto isolate = v8::Isolate::GetCurrent();
  auto k = v8::String::NewFromUtf8(isolate, key).ToLocalChecked();
  bool out;
  if (!obj->val.As<v8::Object>()->Has(ctx->ctx, k).To(&out))
    return false;
  return out;
}
v8_local_value *v8_object_own_keys(v8_local_context *ctx, v8_local_value *obj) {
  v8::Local<v8::Array> out;
  if (!obj->val.As<v8::Object>()->GetOwnPropertyNames(ctx->ctx).ToLocal(&out))
    return new v8_local_value{v8::Array::New(v8::Isolate::GetCurrent(), 0)};
  return new v8_local_value{out};
}
void v8_object_set_prototype(v8_local_context *ctx, v8_local_value *obj,
                             v8_local_value *proto) {
  obj->val.As<v8::Object>()->SetPrototypeV2(ctx->ctx, proto->val).Check();
}
v8_local_value *v8_map_as_array(v8_local_value *v) {
  return new v8_local_value{v->val.As<v8::Map>()->AsArray()};
}
v8_local_value *v8_set_as_array(v8_local_value *v) {
  return new v8_local_value{v->val.As<v8::Set>()->AsArray()};
}

v8_local_value *v8_integer_new(v8_isolate *isolate, int32_t value) {
  return new v8_local_value{v8::Integer::New(iso(isolate), value)};
}
v8_local_value *v8_function_callback_info_this(
    const v8_function_callback_info *info) {
  return new v8_local_value{fci(info)->This()};
}

v8_global *v8_global_new(v8_isolate *isolate, v8_local_value *v) {
  return reinterpret_cast<v8_global *>(
      new v8::Global<v8::Value>(iso(isolate), v->val));
}
v8_local_value *v8_global_get(v8_isolate *isolate, v8_global *g) {
  return new v8_local_value{
      reinterpret_cast<v8::Global<v8::Value> *>(g)->Get(iso(isolate))};
}
void v8_global_free(v8_global *g) {
  delete reinterpret_cast<v8::Global<v8::Value> *>(g);
}

int v8_promise_state(v8_local_value *v) {
  return static_cast<int>(v->val.As<v8::Promise>()->State());
}
v8_local_value *v8_promise_result(v8_local_value *v) {
  return new v8_local_value{v->val.As<v8::Promise>()->Result()};
}
void v8_promise_mark_as_handled(v8_local_value *v) {
  v->val.As<v8::Promise>()->MarkAsHandled();
}
void v8_isolate_perform_microtask_checkpoint(v8_isolate *isolate) {
  iso(isolate)->PerformMicrotaskCheckpoint();
}
int v8_event_loop_run_once(v8_isolate *isolate) {
  return uv_run(node::GetCurrentEventLoop(iso(isolate)), UV_RUN_ONCE);
}

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
  v8::Local<v8::Value> this_ =
      recv ? recv->val : v8::Undefined(v8::Isolate::GetCurrent()).As<v8::Value>();
  auto r = fn->val.As<v8::Function>()->Call(ctx->ctx, this_, argc, args.data());
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
  // Borrowed boxes: valid only for this call, Zig must not free them.
  v8_local_context ctx_box{context};
  v8_module ref_box{referrer};
  v8_module *res = g_resolve(&ctx_box, *spec ? *spec : "", &ref_box);
  if (!res)
    return v8::MaybeLocal<v8::Module>(); // throws in the importing module
  return res->mod;
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
  return new v8_module{mod};
}
void v8_module_free(v8_module *m) { delete m; }
int v8_module_identity_hash(v8_module *m) { return m->mod->GetIdentityHash(); }

bool v8_module_instantiate(v8_local_context *ctx, v8_module *m,
                           v8_resolve_callback cb) {
  g_resolve = cb;
  bool ok = m->mod->InstantiateModule(ctx->ctx, &resolve_trampoline)
                .FromMaybe(false);
  g_resolve = nullptr;
  return ok;
}
v8_local_value *v8_module_evaluate(v8_local_context *ctx, v8_module *m) {
  v8::Local<v8::Value> result;
  if (!m->mod->Evaluate(ctx->ctx).ToLocal(&result))
    return nullptr;
  return new v8_local_value{result};
}
int v8_module_get_status(v8_module *m) {
  return static_cast<int>(m->mod->GetStatus());
}
v8_local_value *v8_module_get_exception(v8_module *m) {
  return new v8_local_value{m->mod->GetException()};
}

} // extern "C"
