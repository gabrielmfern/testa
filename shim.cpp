#include <cstdio>
#include <memory>
#include <string>
#include <unordered_set>
#include <vector>
#include "node.h"
#include "uv.h"
#include "shim.h"

struct node_initialization_result {
    std::shared_ptr<node::InitializationResult> result;
};

struct node_multi_isolate_platform {
    std::unique_ptr<node::MultiIsolatePlatform> platform;
};

struct node_common_environment_setup {
    std::unique_ptr<node::CommonEnvironmentSetup> setup;
    uv_async_t stop_async;
    std::unordered_set<uv_handle_t*> baseline_handles;
};

struct v8_scope {
    v8::Locker locker;
    v8::Isolate::Scope isolate_scope;
    v8::HandleScope handle_scope;
    v8::Context::Scope context_scope;

    v8_scope(node::CommonEnvironmentSetup* s)
        : locker(s->isolate()),
          isolate_scope(s->isolate()),
          handle_scope(s->isolate()),
          context_scope(s->context()) {}
};

extern "C" {

node_initialization_result* node_initialize_once_per_process(void) {
    std::vector<std::string> args = {"testa", "--experimental-vm-modules", "--disable-warning=ExperimentalWarning"};
    auto result = node::InitializeOncePerProcess(
        args,
        {node::ProcessInitializationFlags::kNoInitializeV8,
         node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
    for (const std::string& error : result->errors())
        fprintf(stderr, "%s\n", error.c_str());
    return new node_initialization_result{std::move(result)};
}

int node_initialization_result_early_return(node_initialization_result* result) {
    return result->result->early_return() ? 1 : 0;
}

int node_initialization_result_exit_code(node_initialization_result* result) {
    return result->result->exit_code();
}

void node_tear_down_once_per_process(void) {
    node::TearDownOncePerProcess();
}

node_multi_isolate_platform* node_multi_isolate_platform_create(int thread_pool_size) {
    return new node_multi_isolate_platform{node::MultiIsolatePlatform::Create(thread_pool_size)};
}

void v8_initialize(node_multi_isolate_platform* platform) {
    v8::V8::InitializePlatform(platform->platform.get());
    v8::V8::Initialize();
}

void v8_dispose(node_multi_isolate_platform* platform) {
    v8::V8::Dispose();
    v8::V8::DisposePlatform();
    delete platform;
}

node_common_environment_setup* node_common_environment_setup_create(node_multi_isolate_platform* platform, node_initialization_result* result) {
    std::vector<std::string> errors;
    auto setup = node::CommonEnvironmentSetup::Create(
        platform->platform.get(), &errors,
        result->result->args(), result->result->exec_args());
    if (!setup) {
        for (const std::string& error : errors)
            fprintf(stderr, "%s\n", error.c_str());
        return nullptr;
    }
    auto wrapper = new node_common_environment_setup{std::move(setup)};
    uv_async_init(wrapper->setup->event_loop(), &wrapper->stop_async,
                  [](uv_async_t* handle) { uv_stop(handle->loop); });
    uv_unref((uv_handle_t*)&wrapper->stop_async);
    return wrapper;
}

node_environment* node_common_environment_setup_env(node_common_environment_setup* setup) {
    return (node_environment*)setup->setup->env();
}

void node_common_environment_setup_destroy(node_common_environment_setup* setup) {
    uv_close((uv_handle_t*)&setup->stop_async, nullptr);
    delete setup;
}

v8_scope* v8_scope_open(node_common_environment_setup* setup) {
    return new v8_scope(setup->setup.get());
}

void v8_scope_close(v8_scope* scope) {
    delete scope;
}

void node_add_linked_binding(node_environment* env, const char* name, napi_addon_register_func fn) {
    node::AddLinkedBinding((node::Environment*)env, name, fn);
}

int node_load_environment(node_environment* env, const char* script) {
    auto ret = node::LoadEnvironment((node::Environment*)env, script);
    return ret.IsEmpty() ? 1 : 0;
}

int node_load_environment_module(node_environment* env, const char* source, const char* resource_name) {
    node::ModuleData entry_point;
    entry_point.set_source(source);
    entry_point.set_format(node::ModuleFormat::kModule);
    entry_point.set_resource_name(resource_name);
    auto ret = node::LoadEnvironment((node::Environment*)env, &entry_point);
    return ret.IsEmpty() ? 1 : 0;
}

int node_spin_event_loop(node_environment* env) {
    return node::SpinEventLoop((node::Environment*)env).FromMaybe(1);
}

int node_stop(node_environment* env) {
    return node::Stop((node::Environment*)env);
}

int node_spin_event_loop_once(node_common_environment_setup* setup) {
    uv_loop_t* loop = setup->setup->event_loop();
    uv_run(loop, UV_RUN_DEFAULT);
    node::GetMultiIsolatePlatform(setup->setup->env())->DrainTasks(setup->setup->isolate());
    if (uv_loop_alive(loop)) return 1;
    if (node::EmitProcessBeforeExit(setup->setup->env()).IsNothing()) return 0;
    return uv_loop_alive(loop);
}

void node_stop_event_loop(node_common_environment_setup* setup) {
    setup->setup->isolate()->TerminateExecution();
    uv_async_send(&setup->stop_async);
}

void node_cancel_terminate_execution(node_common_environment_setup* setup) {
    setup->setup->isolate()->CancelTerminateExecution();
}

void node_snapshot_event_loop(node_common_environment_setup* setup) {
    uv_loop_t* loop = setup->setup->event_loop();
    uv_walk(loop, [](uv_handle_t* handle, void* arg) {
        auto* setup = (node_common_environment_setup*)arg;
        setup->baseline_handles.insert(handle);
    }, setup);
}

void node_purge_event_loop(node_common_environment_setup* setup) {
    uv_loop_t* loop = setup->setup->event_loop();
    uv_walk(loop, [](uv_handle_t* handle, void* arg) {
        auto* setup = (node_common_environment_setup*)arg;
        if (setup->baseline_handles.count(handle)) {
            if (handle->type == UV_TIMER) uv_timer_stop((uv_timer_t*)handle);
            return;
        }
        if (!uv_is_closing(handle)) uv_close(handle, nullptr);
    }, setup);
    uv_run(loop, UV_RUN_NOWAIT);
}

}
