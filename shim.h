#pragma once
#include "js_native_api.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef napi_value (*testa_register_func)(napi_env env, napi_value exports);

void testa_set_register(testa_register_func fn);
int testa_run(const char* script);

#ifdef __cplusplus
}
#endif
