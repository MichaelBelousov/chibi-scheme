const std = @import("std");
const path = std.fs.path;

const Dirs = struct {
    pub const prefix = "/usr/local"; // TODO: std.os.getenv()
    pub const exec_prefix = prefix;
    pub const lib_dir = exec_prefix ++ "/lib";
    pub const data_root_dir = prefix ++ "/share";
    pub const data_dir = data_root_dir;
    pub const mod_dir = data_dir ++ "/chibi";
    pub const so_lib_dir = lib_dir;
    pub const bin_mod_dir = so_lib_dir ++ "/chibi";
};

pub const c_flags = [_][]const u8{
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
    "-Dsexp_default_module_path=\"" // TODO: don't need this, it's ignored anyway
        ++ Dirs.mod_dir ++ ":"
        ++ Dirs.bin_mod_dir
        ++ "\"",
    "-Dsexp_version=\"0.10.0\"", // TODO: read VERSION file
    "-Dsexp_release_name=\"neon\"", // TODO: read RELEASE file
    "-DSEXP_USE_GREEN_THREADS=0",
    "-Dsexp_default_module_path=/",
    // NOTE: can I disable modules and manually load what I need?
    "-DSEXP_USE_MODULES=1",
    "-DSEXP_USE_UTF8_STRINGS=1", // can't disable while keeping json and bytevector modules?
    //"-DSEXP_USE_STRING_INDEX_TABLE=1",
    // wasi
    //"-D_WASI_EMULATED_PROCESS_CLOCKS",
    //"-D_WASI_EMULATED_SIGNAL",
};

pub fn libPkgStep(b: *std.build.Builder, rel_path: []const u8) !*std.build.LibExeObjStep {
    const aloc = b.allocator;
    const lib = b.addStaticLibrary("chibi-scheme", try path.join(aloc, &.{rel_path, "empty.zig"}));

    // loosely matches Makefile.libs
    // don't need main for the library
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "gc.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "sexp.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "bignum.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "gc_heap.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "opcodes.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "vm.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "eval.c"}), &c_flags);
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "simplify.c"}), &c_flags);
    lib.addIncludePath(try path.join(aloc, &.{rel_path, "./include"}));
    lib.linkLibC();
    lib.linkSystemLibrary("m");
    // uncomment these and above in c_flags, to enable not
    // removing chibi.process and chibi.time modules in build
    //wasm_lib.linkSystemLibrary("wasi-emulated-process-clocks");
    //wasm_lib.linkSystemLibrary("wasi-emulated-signal");
    //wasm_lib.export_symbol_names = &[_][]const u8{"_main"};
    lib.export_table = true;

    const make_clibs_cmd = std.fmt.allocPrint(
        b.allocator,
        \\ cd {s} &&
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
    , .{ rel_path }) catch unreachable;

    defer b.allocator.free(make_clibs_cmd);

    // FIXME: requires chibi to already be built with make, which I am not doing here
    // FIXME: can we generate dependencies for zig build?
    const make_clibs = b.addSystemCommand(&.{
        "bash", "-c", make_clibs_cmd
    });
    lib.step.dependOn(&make_clibs.step);
    // NOTE: generated file
    lib.addCSourceFile(try path.join(aloc, &.{rel_path, "clibs.c"}), &c_flags);

    return lib;
}

pub fn build(b: *std.build.Builder) void {
    var webTarget = b.standardTargetOptions(.{});
    webTarget.cpu_arch = .wasm32;
    webTarget.os_tag = .wasi;

    const lib = libPkgStep(b, ".");
    lib.setTarget(b.standardTargetOptions(.{}));
    lib.setBuildMode(b.standardReleaseOptions(.{}));

    lib.install();
}

