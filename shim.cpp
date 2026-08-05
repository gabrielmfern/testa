#include <cstdio>
#include <memory>
#include <string>
#include <vector>
#include "node.h"
#include "shim.h"

static testa_register_func g_register;

extern "C" void testa_set_register(testa_register_func fn) {
    g_register = fn;
}

extern "C" int testa_run(const char* script) {
    std::vector<std::string> args = {"testa"};
    auto result = node::InitializeOncePerProcess(
        args,
        {node::ProcessInitializationFlags::kNoInitializeV8,
         node::ProcessInitializationFlags::kNoInitializeNodeV8Platform});
    for (const std::string& error : result->errors())
        fprintf(stderr, "%s\n", error.c_str());
    if (result->early_return()) return result->exit_code();

    auto platform = node::MultiIsolatePlatform::Create(4);
    v8::V8::InitializePlatform(platform.get());
    v8::V8::Initialize();

    int exit_code = 0;
    std::vector<std::string> errors;
    auto setup = node::CommonEnvironmentSetup::Create(
        platform.get(), &errors, result->args(), result->exec_args());
    if (!setup) {
        for (const std::string& error : errors)
            fprintf(stderr, "%s\n", error.c_str());
        return 1;
    }

    {
        v8::Locker locker(setup->isolate());
        v8::Isolate::Scope isolate_scope(setup->isolate());
        v8::HandleScope handle_scope(setup->isolate());
        v8::Context::Scope context_scope(setup->context());

        if (g_register)
            node::AddLinkedBinding(setup->env(), "testa",
                                   (napi_addon_register_func)g_register);

        auto ret = node::LoadEnvironment(setup->env(), script);
        if (ret.IsEmpty()) exit_code = 1;
        else exit_code = node::SpinEventLoop(setup->env()).FromMaybe(1);
    }

    node::Stop(setup->env());
    setup.reset();

    v8::V8::Dispose();
    v8::V8::DisposePlatform();
    node::TearDownOncePerProcess();
    return exit_code;
}
