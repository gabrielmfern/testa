#import "Compiler";
#import "BuildCpp";
#import "Check";
#import "Bindings_Generator";
#import "File";
#import "Basic";

#run build();

build :: () {
    set_build_options_dc(.{do_output=false});

    arguments := get_command_line_arguments();

    release := false; 
    for arguments {
        if it == "-release" {
            release = true;
            break;
        }
    }

    libnode_dir: string;
    output_filename: string;
    #if OS == .WINDOWS {
        #if CPU == .X64 {
            libnode_dir = "vendor/libnode/x86_64-windows";
        } else #if CPU == .ARM64 {
            libnode_dir = "vendor/libnode/aarch64-windows";
        }
        output_filename = "napi-windows.jai";
    } else #if OS == .LINUX {
        #if CPU == .X64 {
            libnode_dir = "vendor/libnode/x86_64-linux";
        } else #if CPU == .ARM64 {
            libnode_dir = "vendor/libnode/aarch64-linux";
        }
        output_filename = "napi-linux.jai";
    } else #if OS == .MACOS {
        #if CPU == .X64 {
            libnode_dir = "vendor/libnode/x86_64-macos";
        } else #if CPU == .ARM64 {
            libnode_dir = "vendor/libnode/aarch64-macos";
        }
        output_filename = "napi-macos.jai";
    } else {
        assert(false);
    }

    extra: [..] string;
    array_add(*extra, "-Ivendor/libnode/include/node", "-std=c++20");
    #if OS == .WINDOWS {
        array_add(*extra, tprint("%/node.lib", libnode_dir));
    } else {
        array_add(*extra, tprint("%/libnode.%", libnode_dir, ifx OS == .MACOS then "dylib" else "so"));
        #if OS == .MACOS {
            options := get_build_options();
            array_add(*extra, tprint("-mmacosx-version-min=%.%", options.minimum_os_version.major, options.minimum_os_version.minor));
            array_add(*extra, tprint("-Wl,-rpath,@loader_path/%", libnode_dir));
        } else {
            array_add(*extra, tprint("-Wl,-rpath,$ORIGIN/%", libnode_dir));
        }
    }

    if !build_cpp_dynamic_lib("shim", "shim.cpp", debug=!release, extra=extra) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    opts: Generate_Bindings_Options;
    {
        using opts;

        array_add(*libraries, .{filename=tprint("%/libnode", libnode_dir), identifier="libnode"});
        array_add(*libraries, .{filename="shim"});

        array_add(*source_files, "shim.h", "vendor/libnode/include/node/js_native_api.h");
        array_add(*include_paths, "vendor/libnode/include/node");
        array_add(*extra_clang_arguments, "-x", "c++", "-std=c++20");

        array_add(*system_include_paths, "/usr/lib/gcc/x86_64-pc-linux-gnu/16/../../../../include/c++/16");
        array_add(*system_include_paths, "/usr/lib/gcc/x86_64-pc-linux-gnu/16/../../../../include/c++/16/x86_64-pc-linux-gnu");
        array_add(*system_include_paths, "/usr/lib/gcc/x86_64-pc-linux-gnu/16/../../../../include/c++/16/backward");
        array_add(*system_include_paths, ..get_default_system_include_paths());
    }

    if !generate_bindings(opts, output_filename) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    w := compiler_create_workspace("Main program");
    options := get_build_options();
    if release {
        set_optimization(*options, .OPTIMIZED);
    }
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "testa";
    #if OS != .WINDOWS {
        options.additional_linker_arguments = .[tprint("-rpath='$ORIGIN/%'", libnode_dir)];
    }
    set_build_options(options, w);
    add_build_file("testa.jai", w);
}
