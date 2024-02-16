const std = @import("std");
const nc = @import("notcurses");

const FPS = 60;
const fg_color: c_int = 0xff16b0;
const bg_color: c_int = 0x070825;

pub fn main() !void {
    var opts = nc.Context.Options{
        .termtype = null,
        .loglevel = @intFromEnum(nc.LogLevel.silent),
        .margin_t = 0,
        .margin_r = 0,
        .margin_b = 0,
        .margin_l = 0,
        .flags = 0,
    };

    const ctx = try nc.Context.core_init(&opts, null);
    defer ctx.stop();

    ctx.mice_enable(nc.mice.ALL_EVENTS) catch {};

    return run(ctx) catch |e| switch (e) {
        error.Quit => {},
        else => e,
    };
}

fn run(ctx: nc.Context) !void {
    const inputview = try init_inputview(ctx);
    defer inputview.deinit();
    var jt = try JitterTest.init(ctx);
    defer jt.deinit();

    _ = try inputview.print("press 'q' to exit\n", .{});

    while (true) {
        try dispatch_input(ctx, inputview);
        try jt.render();
        try ctx.render();
        std.time.sleep(std.time.ns_per_s / FPS);
        // _ = try inputview.print(".", .{});
    }
}

fn init_inputview(ctx: nc.Context) !nc.Plane {
    const parent = ctx.stdplane();
    const height = parent.dim_y();
    const width = parent.dim_x();
    const nopts: nc.Plane.Options = .{
        .y = 0,
        .x = 0,
        .rows = height,
        .cols = width,
        .userptr = null,
        .name = "inputview",
        .resizecb = null,
        .flags = nc.Plane.option.VSCROLL,
        .margin_b = 0,
        .margin_r = 0,
    };
    return nc.Plane.init(&nopts, parent);
}

fn dispatch_input(ctx: nc.Context, n: nc.Plane) !void {
    var input_buffer: [256]nc.Input = undefined;

    while (true) {
        const nivec = try ctx.getvec_nblock(&input_buffer);
        if (nivec.len == 0) break;
        for (nivec) |*ni| {
            try handle_input_event(n, ni);
            if (ni.id == nc.key.RESIZE)
                try resize(ctx, n);
        }
    }
}

fn handle_input_event(n: nc.Plane, ni: *nc.Input) !void {
    const key = if (@hasField(nc.Input, "eff_text")) ni.eff_text[0] else ni.id;
    _ = n.print("\n {s} {s} code:{d} ecg:{d} mods:{d} y:{d} x:{d} ypx:{d} xpx:{d}", .{
        nc.typeToString(ni.evtype),
        nc.key_string(ni),
        ni.id,
        if (@hasField(nc.Input, "eff_text")) ni.eff_text[0] else ni.id,
        ni.modifiers,
        ni.y,
        ni.x,
        ni.ypx,
        ni.xpx,
    }) catch {};
    if (key == 'q')
        return error.Quit;
}

fn resize(ctx: nc.Context, n: nc.Plane) !void {
    const parent = ctx.stdplane();
    return n.resize_simple(parent.dim_y(), parent.dim_x());
}

const JitterTest = struct {
    const eighths_l = [_][]const u8{ "█", "▉", "▊", "▋", "▌", "▍", "▎", "▏" };
    const eighths_r = [_][]const u8{ " ", "▕", "🮇", "🮈", "▐", "🮉", "🮊", "🮋" };
    const eighths_c = eighths_l.len;

    const size: c_int = 20;
    const Self = @This();

    plane: nc.Plane,
    frame: usize = 0,

    fn init(ctx: nc.Context) !JitterTest {
        const parent = ctx.stdplane();
        const rows: c_int = @intCast(parent.dim_y());
        const cols: c_int = @intCast(parent.dim_x());
        const nopts: nc.Plane.Options = .{
            .y = rows - 2,
            .x = cols - size,
            .rows = 1,
            .cols = @intCast(@min(cols, size)),
            .userptr = null,
            .name = @typeName(Self),
            .resizecb = nc.Plane.resize.realign,
            .flags = nc.Plane.option.FIXED | nc.Plane.option.HORALIGNED | nc.Plane.option.VERALIGNED,
            .margin_b = 0,
            .margin_r = 0,
        };

        const plane = try nc.Plane.init(&nopts, parent);
        try plane.move_yx(rows - 1, cols - size);
        return .{ .plane = plane };
    }

    fn deinit(self: *Self) void {
        self.plane.deinit();
    }

    fn render(self: *Self) !void {
        const rows: c_int = @intCast(self.plane.parent().dim_y());
        const cols: c_int = @intCast(self.plane.parent().dim_x());
        try self.plane.move_yx(rows - 1, cols - size);
        var channels: u64 = 0;
        try nc.channels_set_fg_rgb(&channels, fg_color);
        try nc.channels_set_bg_rgb(&channels, bg_color);
        _ = try self.plane.set_base(" ", 0, channels);
        try self.animate();
        self.frame += 1;
    }

    fn animate(self: *Self) !void {
        const width = self.plane.dim_x();
        const positions = eighths_c * (width - 1);
        const frame = @mod(self.frame, positions * 2);
        const pos = if (frame > eighths_c * (width - 1))
            positions * 2 - frame
        else
            frame;

        try smooth_block_at(self.plane, pos);
    }

    fn smooth_block_at(plane: nc.Plane, pos: u64) !void {
        const blk = @mod(pos, eighths_c) + 1;
        const l = eighths_l[eighths_c - blk];
        const r = eighths_r[eighths_c - blk];
        plane.erase();
        try plane.cursor_move_yx(0, @as(c_int, @intCast(@divFloor(pos, eighths_c))));
        _ = try plane.putstr(@ptrCast(r));
        _ = try plane.putstr(@ptrCast(l));
    }
};
