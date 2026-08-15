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

    libnode_dir: string = "vendor/node/out/Release";
    output_filename: string;
    #if OS == .WINDOWS {
        output_filename = "napi-windows.jai";
    } else #if OS == .LINUX {
        output_filename = "napi-linux.jai";
    } else #if OS == .MACOS {
        output_filename = "napi-macos.jai";
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
        "-std=c++20"
    );
    #if OS == .WINDOWS {
        array_add(*extra, tprint("%/node.lib", libnode_dir));
    } else {
        array_add(*extra, tprint("%/libnode.%", libnode_dir, ifx OS == .MACOS then "dylib" else "so.147"));
        #if OS == .MACOS {
            array_add(*extra, "-mmacosx-version-min=13.5");
        }
    }

    if !build_cpp_dynamic_lib("shim", "shim.cpp", debug=debug, extra=extra) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    opts: Generate_Bindings_Options;
    {
        using opts;

        array_add(*libraries, .{filename=tprint("%/libnode", libnode_dir), identifier="libnode"});
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
    #if OS == .LINUX {
        options.additional_linker_arguments = .["-rpath=\\$ORIGIN/vendor/node/out/Release"];
    } else #if OS == .MACOS {
        options.additional_linker_arguments = .["-rpath", "@executable_path/vendor/node/out/Release"];
    }
    set_build_options(options, w);
    add_build_file("testa.jai", w);
}
