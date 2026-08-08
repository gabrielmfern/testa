#pragma once
#include "node_api_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct node_initialization_result node_initialization_result;
typedef struct node_multi_isolate_platform node_multi_isolate_platform;
typedef struct node_common_environment_setup node_common_environment_setup;
typedef struct node_environment node_environment;
typedef struct v8_scope v8_scope;

node_initialization_result* node_initialize_once_per_process(void);
int node_initialization_result_early_return(node_initialization_result* result);
int node_initialization_result_exit_code(node_initialization_result* result);
void node_tear_down_once_per_process(void);

node_multi_isolate_platform* node_multi_isolate_platform_create(int thread_pool_size);

void v8_initialize(node_multi_isolate_platform* platform);
void v8_dispose(node_multi_isolate_platform* platform);

node_common_environment_setup* node_common_environment_setup_create(node_multi_isolate_platform* platform, node_initialization_result* result);
node_environment* node_common_environment_setup_env(node_common_environment_setup* setup);
void node_common_environment_setup_destroy(node_common_environment_setup* setup);

v8_scope* v8_scope_open(node_common_environment_setup* setup);
void v8_scope_close(v8_scope* scope);

void node_add_linked_binding(node_environment* env, const char* name, napi_addon_register_func fn);
int node_load_environment(node_environment* env, const char* script);
int node_load_environment_module(node_environment* env, const char* source, const char* resource_name);
int node_spin_event_loop(node_environment* env);
int node_stop(node_environment* env);
int node_spin_event_loop_once(node_common_environment_setup* setup);
void node_stop_event_loop(node_common_environment_setup* setup);
void node_cancel_terminate_execution(node_common_environment_setup* setup);
void node_snapshot_event_loop(node_common_environment_setup* setup);
typedef struct v8_promise v8_promise;
v8_promise* v8_promise_ref(napi_value value);
int v8_promise_state(v8_promise* promise);
napi_value v8_promise_result(v8_promise* promise);
void v8_promise_unref(v8_promise* promise);
void node_purge_event_loop(node_common_environment_setup* setup);

#ifdef __cplusplus
}
#endif
