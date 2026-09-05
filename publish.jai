#import "Basic";
#import "Compiler";
#import "File_Utilities";
#import "Process";

#run {
    set_build_options_dc(.{do_output=false});
    if !publish() {
        compiler_set_workspace_status(.FAILED);
    }
}

Platform :: struct {
    dir:   string;
    files: [] string;
}

PLATFORMS :: Platform.[
    .{"linux-x64",    .["testa",     "shim.so",    "libnode.so.137"]},
    .{"darwin-arm64", .["testa",     "shim.dylib", "libnode.137.dylib"]},
    .{"win32-x64",    .["testa.exe", "shim.dll",   "libnode.dll"]},
];

publish :: () -> bool {
    #if OS == .WINDOWS {
        jai :: "jai";
    } else #if OS == .LINUX {
        jai :: "jai-linux";
    } else #if OS == .MACOS {
        jai :: "jai-macos";
    }
    result := run_command(jai, "build.jai", "-optimized");
    if result.exit_code != 0 {
        print("build.jai failed\n");
        return false;
    }

    complete := true;
    for platform: PLATFORMS {
        for platform.files {
            path := tprint("dist/%/%", platform.dir, it);
            if !file_exists(path) {
                print("missing %\n", path);
                complete = false;
            }
        }
    }
    if !complete {
        print("build the missing platforms on their own machines and copy them into dist/ before publishing\n");
        return false;
    }

    result = run_command("npm", "publish");
    return result.exit_code == 0;
}
