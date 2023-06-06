const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    var webTarget = b.standardTargetOptions(.{});
    webTarget.cpu_arch = .wasm32;
    webTarget.os_tag = .wasi;

    const wasm_lib = b.addStaticLibrary("chibi-scheme", "empty.zig");
    wasm_lib.install();
    wasm_lib.setTarget(webTarget);
    wasm_lib.setBuildMode(std.builtin.Mode.ReleaseSmall);

    // loosely matches Makefile.libs
    const prefix = "/usr/local"; // TODO: std.os.getenv()
    const exec_prefix = prefix;
    const lib_dir = exec_prefix ++ "/lib";
    const data_root_dir = prefix ++ "/share";
    const data_dir = data_root_dir;
    const mod_dir = data_dir ++ "/chibi";
    const so_lib_dir = lib_dir;
    const bin_mod_dir = so_lib_dir ++ "/chibi";

    const c_flags = [_][]const u8{
        "-DSEXP_USE_STRICT_TOPLEVEL_BINDINGS=1",
        "-DSEXP_USE_STRICT_TOPLEVEL_BINDINGS=1",
        "-DSEXP_USE_ALIGNED_BYTECODE=1",
        "-DSEXP_USE_STATIC_LIBS=1",
        "-DSEXP_USE_STATIC_LIBS_NO_INCLUDE=1",
        "-fPIC",
        "-DSEXP_USE_INTTYPES",
        "-DSEXP_USE_DL=0",
        "-Dsexp_so_extension=\".wasm\"", // TODO: import builtin for this
        "-Dsexp_platform=\"wasi\"", // TODO: import builtin for this
        "-Dsexp_default_module_path=\"" ++ mod_dir ++ ":" ++ bin_mod_dir ++ "\"", // TODO: use PREFIX/share
        "-Dsexp_version=\"0.10.0\"", // TODO: read VERSION file
        "-Dsexp_release_name=\"neon\"", // TODO: read RELEASE file
        "-DSEXP_USE_GREEN_THREADS=0",
        "-Dsexp_default_module_path=/",
        // NOTE: can I disable modules and manually load what I need?
        "-DSEXP_USE_MODULES=1",
        // wasi
        //"-D_WASI_EMULATED_PROCESS_CLOCKS",
        //"-D_WASI_EMULATED_SIGNAL",
    };

    // wasm_lib.addCSourceFile("main.c", &c_flags); // don't need main for the library
    wasm_lib.addCSourceFile("gc.c", &c_flags);
    wasm_lib.addCSourceFile("sexp.c", &c_flags);
    wasm_lib.addCSourceFile("bignum.c", &c_flags);
    wasm_lib.addCSourceFile("gc_heap.c", &c_flags);
    wasm_lib.addCSourceFile("opcodes.c", &c_flags);
    wasm_lib.addCSourceFile("vm.c", &c_flags);
    wasm_lib.addCSourceFile("eval.c", &c_flags);
    wasm_lib.addCSourceFile("simplify.c", &c_flags);
    wasm_lib.addIncludePath("./include");
    wasm_lib.linkLibC();
    wasm_lib.linkSystemLibrary("m");
    // uncomment these and above definitions, to enable not
    // removing chibi.process and chibi.time modules in build
    //wasm_lib.linkSystemLibrary("wasi-emulated-process-clocks");
    //wasm_lib.linkSystemLibrary("wasi-emulated-signal");
    //wasm_lib.export_symbol_names = &[_][]const u8{"_main"};
    wasm_lib.export_table = true;

    const make_clibs_cmd = std.fmt.allocPrint(
        b.allocator,
        // FIXME: assumes git
        \\ git ls-files lib '*.sld' | \
        \\     LD_LIBRARY_PATH="." \
        \\     DYLD_LIBRARY_PATH="." \
        \\     CHIBI_IGNORE_SYSTEM_PATH=1 \
        \\     CHIBI_MODULE_PATH=lib \
        \\ ./chibi-scheme \
        \\     -q ./tools/chibi-genstatic \
        \\     -x chibi.emscripten \
        \\     -x chibi.process \
        \\     -x chibi.time \
        \\     -x chibi.net \
        \\     -x chibi.filesystem \
        \\     -x chibi.pty \
        \\     -x chibi.stty \
        \\     -x chibi.system > clibs.c
    , .{
        //std.os.getenv("LD_LIBRARY_PATH") orelse "",
        //std.os.getenv("DYLD_LIBRARY_PATH") orelse "",
    }) catch unreachable;
    defer b.allocator.free(make_clibs_cmd);

    // FIXME: requires chibi to already be built with make, which I am not doing here
    // FIXME: can we generate dependencies for zig build?
    const make_clibs = b.addSystemCommand(&.{
        "bash", "-c", make_clibs_cmd
    });
    wasm_lib.step.dependOn(&make_clibs.step);
    wasm_lib.addCSourceFile("clibs.c", &c_flags);

    const build_wasi = b.step("wasi", "Build a wasi static library");
    build_wasi.dependOn(&wasm_lib.step);
}

