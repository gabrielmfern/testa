#include "node_embed.h"

#include "node.h"
#include "uv.h"
#include "v8.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

// The init result and the v8 RAII guards (Locker, *Scope, TryCatch) own real
// C++ state but never need the heap: the caller hands us a sized, aligned
// storage blob (see node_embed.h) and we placement-construct the object into it,
// destroying it in place on teardown. construct_in/destroy_in are the only code
// that touches that storage. (v8::Local<T> handles are NOT boxed at all: they're
// a single pointer-sized GC handle, handed across as the opaque pointer itself;
// see the wrap/as_* helpers.)
//
// ::new (the global placement operator from <new>) is required, not plain
// `new`: HandleScope and TryCatch declare a private member operator new to ban
// heap allocation, which would otherwise hide the placement form and fail to
// compile.
template <class T, class Storage, class... Args>
static T *construct_in(Storage *s, Args &&...args) {
  static_assert(sizeof(T) <= sizeof(Storage), "storage blob too small for T");
  static_assert(alignof(Storage) % alignof(T) == 0,
                "storage blob underaligned for T");
  return ::new (static_cast<void *>(s)) T(std::forward<Args>(args)...);
}
// Recover the live T placement-constructed into the blob. std::launder is what
// makes reading it back through the storage pointer well-defined.
template <class T, class Storage> static T *object_in(Storage *s) {
  return std::launder(reinterpret_cast<T *>(s));
}
template <class T, class Storage> static void destroy_in(Storage *s) {
  object_in<T>(s)->~T();
}

// The init result's owned state is just node's shared_ptr, living in the blob.
using node_init_state = std::shared_ptr<node::InitializationResult>;
static node_init_state &init_state(node_init_result *r) {
  return *object_in<node_init_state>(r);
}

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

void node_initialize_once_per_process(int argc, char **argv, uint64_t flags,
                                      node_init_result *out) {
  argv = uv_setup_args(argc, argv);
  // Forced: InitializeOncePerProcess takes a const std::vector<std::string>&,
  // so argv has to be repackaged as one. Runs once at startup.
  std::vector<std::string> args(argv, argv + argc);
  construct_in<node_init_state>(
      out, node::InitializeOncePerProcess(
               args, static_cast<node::ProcessInitializationFlags::Flags>(flags)));
}
void node_teardown_once_per_process(void) { node::TearDownOncePerProcess(); }

int node_init_result_exit_code(node_init_result *r) {
  return init_state(r)->exit_code();
}
bool node_init_result_early_return(node_init_result *r) {
  return init_state(r)->early_return();
}
int node_init_result_error_count(node_init_result *r) {
  return static_cast<int>(init_state(r)->errors().size());
}
const char *node_init_result_error_at(node_init_result *r, int i) {
  return init_state(r)->errors()[i].c_str();
}
void node_init_result_deinit(node_init_result *r) { destroy_in<node_init_state>(r); }

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

static node::ArrayBufferAllocator *aballoc(node_array_buffer_allocator *p) {
  return reinterpret_cast<node::ArrayBufferAllocator *>(p);
}
static node::IsolateData *isodata(node_isolate_data *p) {
  return reinterpret_cast<node::IsolateData *>(p);
}
static uv_loop_t *uvloop(uv_loop *p) { return reinterpret_cast<uv_loop_t *>(p); }

uv_loop *node_uv_loop_create(void) {
  auto *loop = new uv_loop_t;
  uv_loop_init(loop);
  return reinterpret_cast<uv_loop *>(loop);
}
void node_uv_loop_close(uv_loop *l) {
  uv_loop_close(uvloop(l));
  delete uvloop(l);
}
int node_uv_run_once(uv_loop *l) { return uv_run(uvloop(l), UV_RUN_ONCE); }

node_array_buffer_allocator *node_array_buffer_allocator_create(void) {
  return reinterpret_cast<node_array_buffer_allocator *>(
      node::CreateArrayBufferAllocator());
}
void node_array_buffer_allocator_free(node_array_buffer_allocator *a) {
  node::FreeArrayBufferAllocator(aballoc(a));
}

v8_isolate *node_new_isolate(node_array_buffer_allocator *a, uv_loop *l,
                             v8_platform *p) {
  return reinterpret_cast<v8_isolate *>(
      node::NewIsolate(aballoc(a), uvloop(l), plat(p)));
}
node_isolate_data *node_create_isolate_data(v8_isolate *isolate, uv_loop *l,
                                            v8_platform *p,
                                            node_array_buffer_allocator *a) {
  return reinterpret_cast<node_isolate_data *>(
      node::CreateIsolateData(iso(isolate), uvloop(l), plat(p), aballoc(a)));
}
v8_local_context *node_new_context(v8_isolate *isolate) {
  return wrap(node::NewContext(iso(isolate)));
}
node_environment *node_create_environment(node_isolate_data *d,
                                          v8_local_context *ctx,
                                          node_init_result *r, uint64_t flags) {
  return reinterpret_cast<node_environment *>(node::CreateEnvironment(
      isodata(d), as_ctx(ctx), init_state(r)->args(), init_state(r)->exec_args(),
      static_cast<node::EnvironmentFlags::Flags>(flags)));
}
void node_free_environment(node_environment *e) { node::FreeEnvironment(env_(e)); }
void node_free_isolate_data(node_isolate_data *d) { node::FreeIsolateData(isodata(d)); }
void node_isolate_dispose(v8_isolate *isolate) { iso(isolate)->Dispose(); }
void node_platform_unregister_isolate(v8_platform *p, v8_isolate *isolate) {
  plat(p)->UnregisterIsolate(iso(isolate));
}
void node_platform_add_isolate_finished_callback(v8_platform *p,
                                                 v8_isolate *isolate,
                                                 void (*cb)(void *),
                                                 void *data) {
  plat(p)->AddIsolateFinishedCallback(iso(isolate), cb, data);
}

void v8_locker_init(v8_locker *l, v8_isolate *isolate) {
  construct_in<v8::Locker>(l, iso(isolate));
}
void v8_locker_deinit(v8_locker *l) { destroy_in<v8::Locker>(l); }
void v8_isolate_scope_init(v8_isolate_scope *s, v8_isolate *isolate) {
  construct_in<v8::Isolate::Scope>(s, iso(isolate));
}
void v8_isolate_scope_deinit(v8_isolate_scope *s) {
  destroy_in<v8::Isolate::Scope>(s);
}
void v8_handle_scope_init(v8_handle_scope *s, v8_isolate *isolate) {
  construct_in<v8::HandleScope>(s, iso(isolate));
}
void v8_handle_scope_deinit(v8_handle_scope *s) {
  destroy_in<v8::HandleScope>(s);
}
void v8_context_scope_init(v8_context_scope *s, v8_local_context *ctx) {
  construct_in<v8::Context::Scope>(s, as_ctx(ctx));
}
void v8_context_scope_deinit(v8_context_scope *s) {
  destroy_in<v8::Context::Scope>(s);
}

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
v8_string_bytes v8_value_string_bytes(v8_isolate *isolate,
                                      v8_local_value *value) {
  auto i = iso(isolate);
  v8::Local<v8::String> s;
  if (!as_value(value)->ToString(i->GetCurrentContext()).ToLocal(&s))
    s = v8::String::Empty(i);
  // ValueView borrows V8's native Latin1/UTF-16 storage with no copy and pins it
  // against GC only while it lives. We return the borrowed pointer, so once this
  // returns the bytes are unpinned — the caller must read them before the next
  // V8 call, since any V8 allocation can move the string (see the header note).
  v8::String::ValueView view(i, s);
  const void *data = view.is_one_byte()
                         ? static_cast<const void *>(view.data8())
                         : static_cast<const void *>(view.data16());
  return v8_string_bytes{data, view.length(), view.is_one_byte()};
}

bool v8_value_is_null(v8_local_value *v) { return as_value(v)->IsNull(); }
bool v8_value_is_undefined(v8_local_value *v) { return as_value(v)->IsUndefined(); }
bool v8_value_is_string(v8_local_value *v) { return as_value(v)->IsString(); }
bool v8_value_is_number(v8_local_value *v) { return as_value(v)->IsNumber(); }
bool v8_value_is_array(v8_local_value *v) { return as_value(v)->IsArray(); }
bool v8_value_is_object(v8_local_value *v) { return as_value(v)->IsObject(); }
bool v8_value_is_function(v8_local_value *v) { return as_value(v)->IsFunction(); }
bool v8_value_is_reg_exp(v8_local_value *v) { return as_value(v)->IsRegExp(); }
bool v8_value_is_date(v8_local_value *v) { return as_value(v)->IsDate(); }
bool v8_value_is_map(v8_local_value *v) { return as_value(v)->IsMap(); }
bool v8_value_is_set(v8_local_value *v) { return as_value(v)->IsSet(); }
bool v8_value_boolean_value(v8_isolate *isolate, v8_local_value *v) {
  return as_value(v)->BooleanValue(iso(isolate));
}
double v8_value_number_value(v8_local_context *ctx, v8_local_value *v) {
  return as_value(v)->NumberValue(as_ctx(ctx)).FromMaybe(std::nan(""));
}
v8_local_value *v8_value_type_of(v8_isolate *isolate, v8_local_value *v) {
  return wrap(as_value(v)->TypeOf(iso(isolate)).As<v8::Value>());
}
bool v8_value_instance_of(v8_local_context *ctx, v8_local_value *v,
                          v8_local_value *ctor) {
  return as_value(v)
      ->InstanceOf(as_ctx(ctx), as_value(ctor).As<v8::Object>())
      .FromMaybe(false);
}
uint32_t v8_array_length(v8_local_value *array) {
  return as_value(array).As<v8::Array>()->Length();
}
v8_local_value *v8_map_as_array(v8_local_value *map) {
  return wrap(as_value(map).As<v8::Map>()->AsArray().As<v8::Value>());
}
v8_local_value *v8_set_as_array(v8_local_value *set) {
  return wrap(as_value(set).As<v8::Set>()->AsArray().As<v8::Value>());
}
v8_local_value *v8_string_new(v8_isolate *isolate, const char *utf8,
                              int length) {
  return wrap(v8::String::NewFromUtf8(iso(isolate), utf8,
                                      v8::NewStringType::kNormal, length)
                  .ToLocalChecked()
                  .As<v8::Value>());
}

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
void v8_isolate_perform_microtask_checkpoint(v8_isolate *isolate) {
  iso(isolate)->PerformMicrotaskCheckpoint();
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
v8_local_value *v8_object_get(v8_local_context *ctx, v8_local_value *obj,
                              const char *key) {
  auto context = as_ctx(ctx);
  auto k = v8::String::NewFromUtf8(v8::Isolate::GetCurrent(), key).ToLocalChecked();
  v8::Local<v8::Value> v;
  if (!as_value(obj).As<v8::Object>()->Get(context, k).ToLocal(&v))
    return nullptr;
  return wrap(v);
}
v8_local_value *v8_object_get_index(v8_local_context *ctx, v8_local_value *obj,
                                    uint32_t index) {
  v8::Local<v8::Value> v;
  if (!as_value(obj).As<v8::Object>()->Get(as_ctx(ctx), index).ToLocal(&v))
    return nullptr;
  return wrap(v);
}
v8_local_value *v8_object_get_value(v8_local_context *ctx, v8_local_value *obj,
                                    v8_local_value *key) {
  v8::Local<v8::Value> v;
  if (!as_value(obj).As<v8::Object>()->Get(as_ctx(ctx), as_value(key)).ToLocal(&v))
    return nullptr;
  return wrap(v);
}
bool v8_object_has_own(v8_local_context *ctx, v8_local_value *obj,
                       v8_local_value *key) {
  return as_value(obj)
      .As<v8::Object>()
      ->HasOwnProperty(as_ctx(ctx), as_value(key).As<v8::Name>())
      .FromMaybe(false);
}
v8_local_value *v8_object_own_keys(v8_local_context *ctx, v8_local_value *obj) {
  v8::Local<v8::Array> a;
  if (!as_value(obj).As<v8::Object>()->GetOwnPropertyNames(as_ctx(ctx)).ToLocal(&a))
    return nullptr;
  return wrap(a.As<v8::Value>());
}
v8_local_value *v8_object_new_with_proto(v8_isolate *isolate,
                                         v8_local_value *prototype) {
  return wrap(
      v8::Object::New(iso(isolate), as_value(prototype), nullptr, nullptr, 0));
}

v8_local_value *v8_boolean_new(v8_isolate *isolate, bool value) {
  return wrap(v8::Boolean::New(iso(isolate), value));
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
  // Each v8_local_value* IS the bit pattern of a v8::Local<v8::Value> (see the
  // wrap/as_value helpers), so argv is already a v8::Local<Value> array —
  // reinterpret it in place instead of copying into a std::vector.
  auto r = as_value(fn).As<v8::Function>()->Call(
      as_ctx(ctx), as_value(recv), argc,
      reinterpret_cast<v8::Local<v8::Value> *>(argv));
  if (r.IsEmpty())
    return nullptr;
  return wrap(r.ToLocalChecked());
}

bool v8_value_is_promise(v8_local_value *v) { return as_value(v)->IsPromise(); }
int v8_promise_state(v8_local_value *promise) {
  return static_cast<int>(as_value(promise).As<v8::Promise>()->State());
}
v8_local_value *v8_promise_result(v8_local_value *promise) {
  return wrap(as_value(promise).As<v8::Promise>()->Result());
}
void v8_promise_mark_as_handled(v8_local_value *promise) {
  as_value(promise).As<v8::Promise>()->MarkAsHandled();
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
v8_local_value *v8_function_callback_info_this(
    const v8_function_callback_info *info) {
  return wrap(fci(info)->This().As<v8::Value>());
}
void v8_function_callback_info_set_return_value(
    const v8_function_callback_info *info, v8_local_value *v) {
  fci(info)->GetReturnValue().Set(as_value(v));
}

void v8_try_catch_init(v8_try_catch *tc, v8_isolate *isolate) {
  construct_in<v8::TryCatch>(tc, iso(isolate));
}
bool v8_try_catch_has_caught(v8_try_catch *tc) {
  return object_in<v8::TryCatch>(tc)->HasCaught();
}
v8_local_value *v8_try_catch_exception(v8_try_catch *tc) {
  return wrap(object_in<v8::TryCatch>(tc)->Exception());
}
void v8_try_catch_deinit(v8_try_catch *tc) { destroy_in<v8::TryCatch>(tc); }

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
  // Module specifiers are short paths; copy into a stack buffer instead of
  // heap-allocating a v8::String::Utf8Value. WriteUtf8V2 always null-terminates
  // (capacity >= 1) and never writes a partial UTF-8 sequence, so it's safe to
  // pass straight to the resolver even if a pathological specifier is truncated.
  char spec[1024];
  specifier->WriteUtf8V2(v8::Isolate::GetCurrent(), spec, sizeof(spec),
                         v8::String::WriteFlags::kNullTerminate);
  v8_module *res = g_resolve(wrap(context), spec, wrap(referrer));
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
