const std = @import("std");

const P = std.fs.path.sep_str;
fn package_dir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const src_path = package_dir() ++ P ++ "src";
const lib_src_path = src_path ++ P ++ "lib";
const libcpp_src_path = src_path ++ P ++ "libcpp";
const compat_src_path = src_path ++ P ++ "compat";
const data_path = package_dir() ++ P ++ "data";

const cflags = [_][]const u8{
    "-DPUBLIC",
    "-D_XOPEN_SOURCE=700",
    "-DPRIVATE",
    "-D_GNU_SOURCE",
    "-D_DEFAULT_SOURCE",
    "-Wall",
    "-Wno-deprecated-pragma",
    "-Wno-deprecated-declarations",
    "-Wno-bitwise-instead-of-logical",
    "-Wno-unused-but-set-variable",
    "-Werror",
    "-fno-sanitize=undefined",
};

const cppflags = [_][]const u8{
    "-Wnull-dereference",
    "-Wunused",
    "-Wno-c99-extensions",
    "-Wall",
    "-Wno-deprecated-pragma",
    "-Wno-bitwise-instead-of-logical",
    "-Werror",
    "-fno-strict-aliasing",
    "-ffunction-sections",
    "-fno-rtti",
    "-std=c++20",
    "-fno-sanitize=undefined",
};

pub fn build(b: *std.build.Builder) void {
    const enable_ffmpeg = b.option(bool, "enable_ffmpeg", "Enable ffmpeg for media decoding") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gpm_dep = b.dependency("gpm", .{ .target = target, .optimize = optimize });
    const libdeflate_dep = b.dependency("libdeflate", .{ .target = target, .optimize = optimize });
    const ncurses_dep = b.dependency("ncurses", .{ .target = target, .optimize = optimize });
    const libunistring_dep = b.dependency("libunistring", .{ .target = target, .optimize = optimize });
    const ffmpeg_dep = b.dependency("ffmpeg", .{ .target = target, .optimize = optimize });

    const lib = b.addStaticLibrary(.{
        .name = "notcurses",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkLibrary(gpm_dep.artifact("gpm"));
    lib.linkLibrary(libdeflate_dep.artifact("deflate"));
    lib.linkLibrary(ncurses_dep.artifact("ncurses"));
    lib.linkLibrary(libunistring_dep.artifact("libunistring"));
    if (enable_ffmpeg) lib.linkLibrary(ffmpeg_dep.artifact("ffmpeg"));

    const version_header = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "version.h",
    }, .{
        .NOTCURSES_VERNUM_MAJOR = 3,
        .NOTCURSES_VERNUM_MINOR = 0,
        .NOTCURSES_VERNUM_PATCH = 9,
        .NOTCURSES_VERNUM_TWEAK = 0,
        .NOTCURSES_VERSION_MAJOR = "3",
        .NOTCURSES_VERSION_MINOR = "0",
        .NOTCURSES_VERSION_PATCH = "9",
        .NOTCURSES_VERSION_TWEAK = "0",
    });
    lib.addConfigHeader(version_header);

    const builddef_header = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "builddef.h",
    }, .{
        .DFSG_BUILD = null,
        .USE_ASAN = null,
        .USE_DEFLATE = 1,
        .USE_GPM = 1,
        .USE_QRCODEGEN = null,
        .USE_FFMPEG = if (enable_ffmpeg) @as(u32, 1) else null,
        .USE_OIIO = null,
        .NOTCURSES_USE_MULTIMEDIA = if (enable_ffmpeg) @as(u32, 1) else null,
        .NOTCURSES_SHARE = data_path,
    });
    lib.addConfigHeader(builddef_header);

    lib.addIncludePath("include");
    lib.addIncludePath("src");

    addCSourceDir(lib, b, lib_src_path, &cflags);
    addCSourceDir(lib, b, compat_src_path, &cflags);
    lib.addCSourceFile("src/media/shim.c", &cflags);
    if (enable_ffmpeg) lib.addCSourceFile("src/media/ffmpeg.c", &cflags);
    lib.addCSourceFile("src/media/none.c", &cflags);

    b.installArtifact(lib);
    lib.installConfigHeader(version_header, .{});
    lib.installHeadersDirectory("include/notcurses", "notcurses");

    const libcpp = b.addStaticLibrary(.{
        .name = "notcurses++",
        .target = target,
        .optimize = optimize,
    });
    libcpp.linkLibCpp();
    libcpp.linkLibrary(lib);
    libcpp.addIncludePath("include");
    libcpp.addIncludePath("src");

    addCSourceDir(libcpp, b, libcpp_src_path, &cppflags);

    b.installArtifact(libcpp);
    libcpp.installHeadersDirectory("include/ncpp", "ncpp");

    const info_exe = b.addExecutable(.{
        .name = "notcurses-info",
        .target = target,
        .optimize = optimize,
    });
    info_exe.linkLibC();
    info_exe.linkLibrary(lib);
    info_exe.linkLibrary(gpm_dep.artifact("gpm"));
    info_exe.linkLibrary(libdeflate_dep.artifact("deflate"));
    info_exe.linkLibrary(ncurses_dep.artifact("ncurses"));
    info_exe.linkLibrary(libunistring_dep.artifact("libunistring"));
    info_exe.addCSourceFile("src/info/main.c", &cflags);
    info_exe.addConfigHeader(version_header);
    info_exe.addConfigHeader(builddef_header);
    info_exe.addIncludePath("include");
    info_exe.addIncludePath("src");
    b.installArtifact(info_exe);

    const input_exe = b.addExecutable(.{
        .name = "notcurses-input",
        .target = target,
        .optimize = optimize,
    });
    input_exe.linkLibCpp();
    input_exe.linkLibrary(lib);
    input_exe.linkLibrary(libcpp);
    input_exe.linkLibrary(gpm_dep.artifact("gpm"));
    input_exe.linkLibrary(libdeflate_dep.artifact("deflate"));
    input_exe.linkLibrary(ncurses_dep.artifact("ncurses"));
    input_exe.linkLibrary(libunistring_dep.artifact("libunistring"));
    input_exe.addCSourceFile("src/input/input.cpp", &cppflags);
    input_exe.addConfigHeader(version_header);
    input_exe.addConfigHeader(builddef_header);
    input_exe.addIncludePath("include");
    input_exe.addIncludePath("src");
    b.installArtifact(input_exe);

    const tetris_exe = b.addExecutable(.{
        .name = "notcurses-tetris",
        .target = target,
        .optimize = optimize,
    });
    tetris_exe.linkLibCpp();
    tetris_exe.linkLibrary(lib);
    tetris_exe.linkLibrary(libcpp);
    tetris_exe.linkLibrary(gpm_dep.artifact("gpm"));
    tetris_exe.linkLibrary(libdeflate_dep.artifact("deflate"));
    tetris_exe.linkLibrary(ncurses_dep.artifact("ncurses"));
    tetris_exe.linkLibrary(libunistring_dep.artifact("libunistring"));
    tetris_exe.addCSourceFile("src/tetris/main.cpp", &cppflags);
    tetris_exe.addConfigHeader(version_header);
    tetris_exe.addConfigHeader(builddef_header);
    tetris_exe.addIncludePath("include");
    tetris_exe.addIncludePath("src");
    b.installArtifact(tetris_exe);

    const fetch_exe = b.addExecutable(.{
        .name = "notcurses-fetch",
        .target = target,
        .optimize = optimize,
    });
    fetch_exe.linkLibCpp();
    fetch_exe.linkLibrary(lib);
    fetch_exe.linkLibrary(gpm_dep.artifact("gpm"));
    fetch_exe.linkLibrary(libdeflate_dep.artifact("deflate"));
    fetch_exe.linkLibrary(ncurses_dep.artifact("ncurses"));
    fetch_exe.linkLibrary(libunistring_dep.artifact("libunistring"));
    fetch_exe.addCSourceFile("src/fetch/main.c", &cflags);
    fetch_exe.addCSourceFile("src/fetch/ncart.c", &cflags);
    fetch_exe.addConfigHeader(version_header);
    fetch_exe.addConfigHeader(builddef_header);
    fetch_exe.addIncludePath("include");
    fetch_exe.addIncludePath("src");
    b.installArtifact(fetch_exe);
}

fn addCSourceDir(self: *std.build.CompileStep, b: *std.build.Builder, dir_path: []const u8, flags: []const []const u8) void {
    var lib_Dir = std.fs.openIterableDirAbsolute(dir_path, .{}) catch unreachable;
    defer lib_Dir.close();
    var iter = lib_Dir.iterate();

    while (iter.next() catch unreachable) |entry| {
        if (entry.kind == .File) {
            const ext = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".cc")) {
                const path = std.fs.path.join(b.allocator, &.{ dir_path, entry.name }) catch unreachable;
                self.addCSourceFile(path, flags);
                b.allocator.free(path);
            }
        }
    }
}
