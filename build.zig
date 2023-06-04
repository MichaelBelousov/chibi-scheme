const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    var webTarget = b.standardTargetOptions(.{});
    webTarget.cpu_arch = .wasm32;
    // can't use emscripten target doesn't support a lot of stuff
    // maybe should use freestanding? (also doesn't support stdin/err)
    webTarget.os_tag = .wasi;

    const wasm_lib = b.addSharedLibrary("chibi-scheme", "empty.zig", .unversioned);
    wasm_lib.setTarget(webTarget);
    wasm_lib.setBuildMode(mode);
    wasm_lib.install();

    // matches Makefile.libs
    const prefix = "/usr/local"; // TODO: std.os.getEnv()
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
        "-DSEXP_USE_STATIC_LIBS_NO_INCLUDE=0",
        "-fPIC",
        "-DSEXP_USE_INTTYPES",
        "-DSEXP_USE_DL=0",
        "-Dsexp_so_extension=\".wasm\"", // TODO: import builtin for this
        "-Dsexp_platform=\"none\"", // TODO: import builtin for this
        "-Dsexp_default_module_path=\"" ++ mod_dir ++ ":" ++ bin_mod_dir ++ "\"", // TODO: use PREFIX/share
        "-Dsexp_version=\"0.10.0\"", // TODO: read VERSION file
        "-Dsexp_release_name=\"neon\"", // TODO: read RELEASE file
        "-DSEXP_USE_GREEN_THREADS=0",
        "-DSEXP_USE_MODULES=0",
    };

    wasm_lib.addCSourceFile("main.c", &c_flags);
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

    const make_clibs_cmd = std.fmt.allocPrint(
        b.allocator,
        // FIXME: assumes git
        \\ git ls-files lib '*.sld' | \
        //\\   | LD_LIBRARY_PATH=".:{s}" \
        //\\     DYLD_LIBRARY_PATH=".:{s}" \
        \\     CHIBI_IGNORE_SYSTEM_PATH=1 \
        \\     CHIBI_MODULE_PATH=lib \
        \\ ./chibi-scheme \
        \\     -q ./tools/chibi-genstatic > clibs.c
        \\     -x chibi.emscripten
    , .{
        //std.os.getenv("LD_LIBRARY_PATH") orelse "",
        //std.os.getenv("DYLD_LIBRARY_PATH") orelse "",
    }) catch unreachable;

    // FIXME: requires shibi to already be built or in the system
    // FIXME: can we make it depend upon the state of all the .sld files so it doesn't always run?
    const make_clibs = b.addSystemCommand(&.{
        "bash", "-c", make_clibs_cmd
    });
    wasm_lib.step.dependOn(&make_clibs.step);
    wasm_lib.export_symbol_names = &[_][]const u8{"_main"};

    // const test_step = b.step("test", "Run library tests");
    // test_step.dependOn(&main_tests.step);
}
