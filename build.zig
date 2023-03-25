const std = @import("std");

const P = std.fs.path.sep_str;
fn package_dir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
const src_path = package_dir() ++ P ++ "src";
const lib_src_path = src_path ++ P ++ "lib";
const libcpp_src_path = src_path ++ P ++ "libcpp";
const compat_src_path = src_path ++ P ++ "compat";

const cflags = [_][]const u8{
    "-DPUBLIC", "-D_XOPEN_SOURCE=700", "-DPRIVATE", "-D_GNU_SOURCE", "-D_DEFAULT_SOURCE",
};

const cppflags = [_][]const u8{
    "-Wnull-dereference",
    "-Wunused",
    "-Wno-c99-extensions",
    "-fno-strict-aliasing",
    "-ffunction-sections",
    "-fno-rtti",
    "-std=c++20",
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gpm_dep = b.dependency("gpm", .{ .target = target, .optimize = optimize });
    const libdeflate_dep = b.dependency("libdeflate", .{ .target = target, .optimize = optimize });
    const ncurses_dep = b.dependency("ncurses", .{ .target = target, .optimize = optimize });
    const libunistring_dep = b.dependency("libunistring", .{ .target = target, .optimize = optimize });

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
        .style = .{ .cmake = .{ .path = "tools/builddef.h.in" } },
        .include_path = "builddef.h",
    }, .{
        .DFSG_BUILD = null,
        .USE_ASAN = null,
        .USE_DEFLATE = 1,
        .USE_GPM = 1,
        .USE_QRCODEGEN = null,
        .USE_FFMPEG = null,
        .USE_OIIO = null,
    });
    lib.addConfigHeader(builddef_header);

    lib.addIncludePath("include");
    lib.addIncludePath("src");

    addCSourceDir(lib, b, lib_src_path, &cflags);
    addCSourceDir(lib, b, compat_src_path, &cflags);
    lib.addCSourceFile("src/media/shim.c", &cflags);
    lib.addCSourceFile("src/media/none.c", &cflags);

    lib.install();
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

    libcpp.install();
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
    info_exe.install();
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
