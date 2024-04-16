const std = @import("std");

const cflags_all = [_][]const u8{
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

const cflags_macos = cflags_all ++ [_][]const u8{
    "-D_DARWIN_C_SOURCE",
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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{
        .name = "notcurses",
        .target = target,
        .optimize = optimize,
    });

    const enable_ffmpeg = b.option(bool, "enable_ffmpeg", "Enable ffmpeg for media decoding (default: no)") orelse false;
    const enable_gpm = if (lib.rootModuleTarget().os.tag == .linux)
        b.option(bool, "enable_gpm", "Enable gpm support (default: yes)") orelse true
    else
        b.option(bool, "enable_gpm", "Enable gpm support (default: no)") orelse false;
    const use_system_notcurses = b.option(bool, "use_system_notcurses", "Build against system notcurses (default: no)") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "use_system_notcurses", use_system_notcurses);

    const notcurses_dep = b.dependency("notcurses", .{});
    const gpm_dep = b.dependency("gpm", .{ .target = target, .optimize = optimize });
    const libdeflate_dep = b.dependency("libdeflate", .{ .target = target, .optimize = optimize });
    const ncurses_dep = b.dependency("ncurses", .{ .target = target, .optimize = optimize });
    const libunistring_dep = b.dependency("libunistring", .{ .target = target, .optimize = optimize });
    const ffmpeg_dep = b.dependency("ffmpeg", .{ .target = target, .optimize = optimize });

    const cflags = &switch (lib.rootModuleTarget().os.tag) {
        .macos => cflags_macos,
        else => cflags_all,
    };

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
        .USE_GPM = if (enable_gpm) @as(u32, 1) else null,
        .USE_QRCODEGEN = null,
        .USE_FFMPEG = if (enable_ffmpeg) @as(u32, 1) else null,
        .USE_OIIO = null,
        .NOTCURSES_USE_MULTIMEDIA = if (enable_ffmpeg) @as(u32, 1) else null,
        .NOTCURSES_SHARE = notcurses_dep.path("data").getPath(b),
    });
    lib.addConfigHeader(builddef_header);
    lib.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
    lib.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
    lib.addCSourceFiles(.{
        .root = notcurses_dep.path("src"),
        .files = &[_][]const u8{
            "lib/automaton.c",
            "lib/banner.c",
            "lib/blit.c",
            "lib/debug.c",
            "lib/direct.c",
            "lib/fade.c",
            "lib/fd.c",
            "lib/fill.c",
            "lib/gpm.c",
            "lib/in.c",
            "lib/kitty.c",
            "lib/layout.c",
            "lib/linux.c",
            "lib/menu.c",
            "lib/metric.c",
            "lib/mice.c",
            "lib/notcurses.c",
            "lib/plot.c",
            "lib/progbar.c",
            "lib/reader.c",
            "lib/reel.c",
            "lib/render.c",
            "lib/selector.c",
            "lib/sixel.c",
            "lib/sprite.c",
            "lib/stats.c",
            "lib/tabbed.c",
            "lib/termdesc.c",
            "lib/tree.c",
            "lib/unixsig.c",
            "lib/util.c",
            "lib/visual.c",
            "lib/windows.c",
            "compat/compat.c",
            "media/shim.c",
            "media/none.c",
        },
        .flags = cflags,
    });
    if (enable_ffmpeg) lib.addCSourceFiles(.{
        .root = notcurses_dep.path("src"),
        .files = &[_][]const u8{
            "media/ffmpeg.c",
        },
        .flags = cflags,
    });
    lib.addIncludePath(.{ .path = "include" });
    lib.addCSourceFiles(.{
        .files = &[_][]const u8{
            "src/wrappers.c",
        },
        .flags = cflags,
    });

    b.installArtifact(lib);
    lib.installConfigHeader(version_header);
    lib.installConfigHeader(builddef_header);
    lib.installHeadersDirectory(.{ .path = notcurses_dep.path("include/notcurses").getPath(b) }, "notcurses", .{});

    const mod = b.addModule("notcurses", .{
        .root_source_file = .{ .path = "src/notcurses.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (use_system_notcurses) {
        mod.linkSystemLibrary("notcurses", .{});
        if (lib.rootModuleTarget().os.tag == .macos)
            mod.linkSystemLibrary("notcurses-core", .{});
        mod.linkSystemLibrary("avcodec", .{});
        mod.linkSystemLibrary("avdevice", .{});
        mod.linkSystemLibrary("avutil", .{});
        mod.linkSystemLibrary("avformat", .{});
        mod.linkSystemLibrary("unistring", .{});

        const wrappers = b.addStaticLibrary(.{
            .name = "wrappers",
            .target = target,
            .optimize = optimize,
        });
        wrappers.addIncludePath(.{ .path = "include" });
        wrappers.addCSourceFiles(.{
            .files = &[_][]const u8{
                "src/wrappers.c",
            },
            .flags = cflags,
        });
        wrappers.linkLibC();
        mod.linkLibrary(wrappers);
    } else {
        mod.linkLibrary(lib);
    }
    mod.addIncludePath(.{ .path = "include" });

    const libcpp = b.addStaticLibrary(.{
        .name = "notcurses++",
        .target = target,
        .optimize = optimize,
    });
    libcpp.linkLibCpp();
    libcpp.linkLibrary(lib);
    libcpp.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
    libcpp.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
    libcpp.addCSourceFiles(.{
        .root = notcurses_dep.path("src/libcpp"),
        .files = &[_][]const u8{
            "FDPlane.cc",
            "Menu.cc",
            "MultiSelector.cc",
            "NotCurses.cc",
            "Plane.cc",
            "Plot.cc",
            "Reel.cc",
            "Root.cc",
            "Selector.cc",
            "Subproc.cc",
            "Tablet.cc",
            "Utilities.cc",
        },
        .flags = cflags,
    });
    b.installArtifact(libcpp);
    libcpp.installHeadersDirectory(.{ .path = notcurses_dep.path("include/ncpp").getPath(b) }, "ncpp", .{});

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
    info_exe.addCSourceFiles(.{
        .root = notcurses_dep.path("src/info"),
        .files = &[_][]const u8{"main.c"},
        .flags = cflags,
    });
    info_exe.addConfigHeader(version_header);
    info_exe.addConfigHeader(builddef_header);
    info_exe.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
    info_exe.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
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
    input_exe.addCSourceFiles(.{
        .root = notcurses_dep.path("src/input"),
        .files = &[_][]const u8{"input.cpp"},
        .flags = &cppflags,
    });
    input_exe.addConfigHeader(version_header);
    input_exe.addConfigHeader(builddef_header);
    input_exe.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
    input_exe.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
    b.installArtifact(input_exe);

    const tetris_exe = b.addExecutable(.{
        .name = "nctetris",
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
    tetris_exe.addCSourceFiles(.{
        .root = notcurses_dep.path("src/tetris"),
        .files = &[_][]const u8{"main.cpp"},
        .flags = &cppflags,
    });
    tetris_exe.addConfigHeader(version_header);
    tetris_exe.addConfigHeader(builddef_header);
    tetris_exe.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
    tetris_exe.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
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
    fetch_exe.addCSourceFiles(.{
        .root = notcurses_dep.path("src/fetch"),
        .files = &[_][]const u8{
            "main.c",
            "ncart.c",
        },
        .flags = cflags,
    });
    fetch_exe.addConfigHeader(version_header);
    fetch_exe.addConfigHeader(builddef_header);
    fetch_exe.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
    fetch_exe.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
    b.installArtifact(fetch_exe);

    if (enable_ffmpeg) {
        const player_exe = b.addExecutable(.{
            .name = "ncplayer",
            .target = target,
            .optimize = optimize,
        });
        player_exe.linkLibCpp();
        player_exe.linkLibrary(lib);
        player_exe.linkLibrary(libcpp);
        player_exe.linkLibrary(gpm_dep.artifact("gpm"));
        player_exe.linkLibrary(libdeflate_dep.artifact("deflate"));
        player_exe.linkLibrary(ncurses_dep.artifact("ncurses"));
        player_exe.linkLibrary(libunistring_dep.artifact("libunistring"));
        player_exe.addCSourceFiles(.{
            .root = notcurses_dep.path("src/player"),
            .files = &[_][]const u8{"play.cpp"},
            .flags = &cppflags,
        });
        player_exe.addConfigHeader(version_header);
        player_exe.addConfigHeader(builddef_header);
        player_exe.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
        player_exe.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
        b.installArtifact(player_exe);

        const ls_exe = b.addExecutable(.{
            .name = "ncls",
            .target = target,
            .optimize = optimize,
        });
        ls_exe.linkLibCpp();
        ls_exe.linkLibrary(lib);
        ls_exe.linkLibrary(libcpp);
        ls_exe.linkLibrary(gpm_dep.artifact("gpm"));
        ls_exe.linkLibrary(libdeflate_dep.artifact("deflate"));
        ls_exe.linkLibrary(ncurses_dep.artifact("ncurses"));
        ls_exe.linkLibrary(libunistring_dep.artifact("libunistring"));
        ls_exe.addCSourceFiles(.{
            .root = notcurses_dep.path("src/ls"),
            .files = &[_][]const u8{"main.cpp"},
            .flags = &cppflags,
        });
        ls_exe.addConfigHeader(version_header);
        ls_exe.addConfigHeader(builddef_header);
        ls_exe.addIncludePath(.{ .path = notcurses_dep.path("include").getPath(b) });
        ls_exe.addIncludePath(.{ .path = notcurses_dep.path("src").getPath(b) });
        b.installArtifact(ls_exe);
    }

    const ncinputtest = b.addExecutable(.{
        .name = "ncinputtest",
        .root_source_file = .{ .path = "src/ncinputtest.zig" },
        .target = target,
        .optimize = optimize,
    });
    ncinputtest.root_module.addImport("notcurses", mod);
    b.installArtifact(ncinputtest);
}
