#import "Compiler";
#import "BuildCpp";
#import "Check";
#import "Bindings_Generator";
#import "File";
#import "Basic";


#run build();

build :: () {
    debug := get_build_options().array_bounds_check == .ON;

    set_build_options_dc(.{do_output=false});

    libnode_dir: string;
    libnode_include_dir := "vendor/libnode/include/node";
    libuv_include_dir: string;
    libuv_lib: string;
    libnode_lib: string;
    output_filename: string;
    #if OS == .LINUX {
        libnode_include_dir = "/usr/include/libnode";
        libnode_lib = "/usr/lib/libnode.so";
        output_filename = "napi-linux.jai";
    } else #if OS == .MACOS {
        brew_prefix: string;
        brew_prefix = "/opt/homebrew/opt/node";
        libnode_dir = tprint("%/lib", brew_prefix);
        libnode_include_dir = tprint("%/include/node", brew_prefix);
        libuv_include_dir = "/opt/homebrew/opt/libuv/include";
        libuv_lib = "/opt/homebrew/opt/libuv/lib/libuv.dylib";
        libnode_lib = tprint("%/libnode.147.dylib", libnode_dir);
        output_filename = "napi-macos.jai";
    } else {
        assert(false);
    }

    extra: [..] string;
    array_add(*extra, tprint("-I%", libnode_include_dir), "-std=c++20");
    if libuv_include_dir  array_add(*extra, tprint("-I%", libuv_include_dir));
    array_add(*extra, libnode_lib);
    if libuv_lib  array_add(*extra, libuv_lib);
    #if OS == .MACOS {
        min_os := get_build_options().minimum_os_version;
        array_add(*extra, tprint("-mmacosx-version-min=%.%", min_os.major, min_os.minor));
    }

    if !build_cpp_dynamic_lib("shim", "shim.cpp", debug=debug, extra=extra) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    opts: Generate_Bindings_Options;
    {
        using opts;

        array_add(*libraries, .{filename=libnode_lib, identifier="libnode"});
        array_add(*libraries, .{filename="shim"});

        array_add(*source_files, "shim.h", tprint("%/js_native_api.h", libnode_include_dir));
        array_add(*include_paths, libnode_include_dir);
        if libuv_include_dir  array_add(*include_paths, libuv_include_dir);
        array_add(*extra_clang_arguments, "-x", "c++", "-std=c++20");

        array_add(*system_include_paths, ..get_default_system_include_paths());
    }

    if !generate_bindings(opts, output_filename) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    w := compiler_create_workspace("Main program");
    options := get_build_options();
    if !debug {
        set_optimization(*options, .OPTIMIZED);
    }
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "testa";
    set_build_options(options, w);
    add_build_file("testa.jai", w);
}
