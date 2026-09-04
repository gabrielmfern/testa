#import "Compiler";
#import "BuildCpp";
#import "Check";
#import "Bindings_Generator";
#import "File";
#import "File_Utilities";
#import "Basic";
#if OS == .LINUX #import "POSIX";


#run build();

build :: () {
    debug := get_build_options().array_bounds_check == .ON;

    set_build_options_dc(.{do_output=false});

    libnode_dir :: "vendor/node/out/Release/lib";
    dist_dir    :: "dist"; // Executable + the shared libraries it needs at runtime, side by side.

    // Shared libraries that have to sit next to the executable at runtime: {source, filename}. On Linux/macOS
    // jai's default link adds an $ORIGIN/@loader_path rpath; on Windows the exe's directory is searched by default.
    output_filename: string;
    runtime_libs: [] [2] string;
    #if OS == .WINDOWS {
        output_filename = "napi-windows.jai";
        runtime_libs = .[.[libnode_dir, "libnode.dll"], .[".", "shim.dll"]];
    } else #if OS == .LINUX {
        output_filename = "napi-linux.jai";
        runtime_libs = .[.[libnode_dir, "libnode.so.137"], .[".", "shim.so"]];
        if !file_exists(tprint("%/libnode.so", libnode_dir)) {
            if symlink("libnode.so.137", tprint("%/libnode.so\0", libnode_dir).data) != 0 {
                compiler_set_workspace_status(.FAILED);
                return;
            }
        }
    } else #if OS == .MACOS {
        output_filename = "napi-macos.jai";
        runtime_libs = .[.[libnode_dir, "libnode.137.dylib"], .[".", "shim.dylib"]];
    } else {
        assert(false);
    }

    options := get_build_options();
    extra: [..] string;
    array_add(
        *extra, 
        "-Ivendor/node/src",
        "-Ivendor/node/deps/uv/include",
        "-Ivendor/node/deps/v8/include",
    );
    #if OS == .WINDOWS {
        // Requires node built as a shared library: `vcbuild.bat dll` (produces libnode.dll + libnode.lib in out/Release).
        // Same defines node uses for executables that consume the shared libnode (see node.gypi),
        // so node/v8/uv symbols are dllimport'ed rather than treated as our own exports.
        array_add(*extra, "/std:c++20", "/Zc:__cplusplus",
            "/DNODE_SHARED_MODE", "/DBUILDING_NODE_EXTENSION", "/DUSING_V8_SHARED", "/DUSING_UV_SHARED", "/DUSING_V8_PLATFORM_SHARED",
            tprint("%/libnode.lib", libnode_dir));
    } else {
        array_add(*extra, "-std=c++20");
        array_add(*extra, tprint("%/libnode.%", libnode_dir, ifx OS == .MACOS then "137.dylib" else "so.137"));
        #if OS == .MACOS {
            array_add(*extra, "-mmacosx-version-min=13.5");
            array_add(*extra, "-Wl,-rpath,@loader_path", tprint("-Wl,-rpath,@loader_path/%", libnode_dir));
        }
    }

    if !build_cpp_dynamic_lib("shim", "shim.cpp", debug=debug, extra=extra) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    opts: Generate_Bindings_Options;
    {
        using opts;

        #if OS == .MACOS {
            array_add(*libraries, .{filename=tprint("%/libnode.137.dylib", libnode_dir), identifier="libnode"});
        } else {
            array_add(*libraries, .{filename=tprint("%/libnode", libnode_dir), identifier="libnode"});
        }
        array_add(*libraries, .{filename="shim"});

        array_add(*source_files, "shim.h", "vendor/node/src/js_native_api.h");
        array_add(*include_paths, "vendor/node/src", "vendor/node/deps/uv/include", "vendor/node/deps/v8/include");
        array_add(*extra_clang_arguments, "-x", "c++", "-std=c++20");

        #if OS == .LINUX {
            array_add(*system_include_paths, "/usr/lib/gcc/x86_64-pc-linux-gnu/16/../../../../include/c++/16");
            array_add(*system_include_paths, "/usr/lib/gcc/x86_64-pc-linux-gnu/16/../../../../include/c++/16/x86_64-pc-linux-gnu");
            array_add(*system_include_paths, "/usr/lib/gcc/x86_64-pc-linux-gnu/16/../../../../include/c++/16/backward");
        }
        array_add(*system_include_paths, ..get_default_system_include_paths());
    }

    if !generate_bindings(opts, output_filename) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    w := compiler_create_workspace("Main program");
    if !debug {
        set_optimization(*options, .OPTIMIZED);
    }
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "testa";
    options.output_path = dist_dir;
    make_directory_if_it_does_not_exist(dist_dir);
    for runtime_libs {
        if !copy_file(tprint("%/%", it[0], it[1]), tprint("%/%", dist_dir, it[1])) {
            compiler_set_workspace_status(.FAILED);
            return;
        }
    }
    set_build_options(options, w);
    add_build_string(tprint("DEBUG :: %;", debug), w);
    add_build_file("testa.jai", w);
}
