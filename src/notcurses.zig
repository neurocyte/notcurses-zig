const std = @import("std");
const c = @cImport({
    @cDefine("_DEFAULT_SOURCE", {});
    @cDefine("_GNU_SOURCE", {});
    @cDefine("PRIVATE", {});
    @cDefine("PUBLIC", {});
    @cDefine("_XOPEN_SOURCE", "700");
    @cInclude("notcurses/notcurses.h");
    @cInclude("notcurses/wrappers.h");
});

threadlocal var egc_buffer: [8191:0]u8 = undefined;
threadlocal var key_string_buffer: [64]u8 = undefined;

pub const Context = struct {
    nc: *c.notcurses,

    pub const Options = c.notcurses_options;
    pub const option = struct {
        pub const INHIBIT_SETLOCALE = c.NCOPTION_INHIBIT_SETLOCALE;
        pub const NO_CLEAR_BITMAPS = c.NCOPTION_NO_CLEAR_BITMAPS;
        pub const NO_WINCH_SIGHANDLER = c.NCOPTION_NO_WINCH_SIGHANDLER;
        pub const NO_QUIT_SIGHANDLERS = c.NCOPTION_NO_QUIT_SIGHANDLERS;
        pub const PRESERVE_CURSOR = c.NCOPTION_PRESERVE_CURSOR;
        pub const SUPPRESS_BANNERS = c.NCOPTION_SUPPRESS_BANNERS;
        pub const NO_ALTERNATE_SCREEN = c.NCOPTION_NO_ALTERNATE_SCREEN;
        pub const NO_FONT_CHANGES = c.NCOPTION_NO_FONT_CHANGES;
        pub const DRAIN_INPUT = c.NCOPTION_DRAIN_INPUT;
        pub const SCROLLING = c.NCOPTION_SCROLLING;
        pub const CLI_MODE = c.NCOPTION_CLI_MODE;
    };

    const Self = @This();

    pub fn core_init(opts: *const Options, fp: ?*c.FILE) !Self {
        return .{ .nc = c.notcurses_core_init(opts, fp) orelse return error.NCInitFailed };
    }

    pub fn stop(self: Self) void {
        _ = c.notcurses_stop(self.nc);
    }

    pub fn mice_enable(self: Self, eventmask: c_uint) !void {
        const result = c.notcurses_mice_enable(self.nc, eventmask);
        if (result != 0)
            return error.NCMiceEnableFailed;
    }

    /// Disable mouse events. Any events in the input queue can still be delivered.
    pub fn mice_disable(self: Self) !void {
        const result = c.notcurses_mice_disable(self.nc);
        if (result != 0)
            return error.NCMiceDisableFailed;
    }

    /// Disable signals originating from the terminal's line discipline, i.e.
    /// SIGINT (^C), SIGQUIT (^\), and SIGTSTP (^Z). They are enabled by default.
    pub fn linesigs_disable(self: Self) !void {
        const result = c.notcurses_linesigs_disable(self.nc);
        if (result != 0)
            return error.NCLinesigsDisableFailed;
    }

    /// Restore signals originating from the terminal's line discipline, i.e.
    /// SIGINT (^C), SIGQUIT (^\), and SIGTSTP (^Z), if disabled.
    pub fn linesigs_enable(self: Self) !void {
        const result = c.notcurses_linesigs_enable(self.nc);
        if (result != 0)
            return error.NCLinesigsEnableFailed;
    }

    /// Refresh the physical screen to match what was last rendered (i.e., without
    /// reflecting any changes since the last call to notcurses_render()). This is
    /// primarily useful if the screen is externally corrupted, or if an
    /// NCKEY_RESIZE event has been read and you're not yet ready to render. The
    /// current screen geometry is returned in 'y' and 'x', if they are not NULL.
    pub fn refresh(self: Self) !void {
        const result = c.notcurses_refresh(self.nc, null, null);
        if (result != 0)
            return error.NCRefreshFailed;
    }

    /// Get a reference to the standard plane (one matching our current idea of the
    /// terminal size) for this terminal. The standard plane always exists, and its
    /// origin is always at the uppermost, leftmost cell of the terminal.
    pub fn stdplane(self: Self) Plane {
        return .{ .n = c.notcurses_stdplane(self.nc) orelse unreachable };
    }

    /// notcurses_stdplane(), plus free bonus dimensions written to non-NULL y/x!
    pub fn stddim_yx(self: Self, y: ?*c_uint, x: ?*c_uint) Plane {
        return .{ .n = c.notcurses_stddim_yx(self.nc, y, x) orelse unreachable };
    }

    /// Return the topmost plane of the standard pile.
    pub fn top(self: Self) Plane {
        return .{ .n = c.notcurses_top(self.nc).? };
    }

    /// Return the bottommost plane of the standard pile.
    pub fn bottom(self: Self) Plane {
        return .{ .n = c.notcurses_bottom(self.nc) };
    }

    /// Renders and rasterizes the standard pile in one shot. Blocking call.
    pub fn render(self: Self) !void {
        const err = c.notcurses_render(self.nc);
        return if (err != 0)
            error.NCRenderFailed
        else {};
    }

    /// Read a UTF-32-encoded Unicode codepoint from input. This might only be part
    /// of a larger EGC. Provide a NULL 'ts' to block at length, and otherwise a
    /// timespec specifying an absolute deadline calculated using CLOCK_MONOTONIC.
    /// Returns a single Unicode code point, or a synthesized special key constant,
    /// or (uint32_t)-1 on error. Returns 0 on a timeout. If an event is processed,
    /// the return value is the 'id' field from that event. 'ni' may be NULL.
    pub fn get(self: Self, ts: ?*const c.struct_timespec, ni: ?*Input) !u32 {
        const ret = c.notcurses_get(self.nc, ts, ni);
        return if (ret < 0)
            error.NCGetFailed
        else
            ret;
    }

    /// Acquire up to 'vcount' ncinputs at the vector 'ni'. The number read will be
    /// returned, or -1 on error without any reads, 0 on timeout.
    pub fn getvec(self: Self, ts: ?*const c.struct_timespec, ni: []Input) ![]Input {
        const ret = c.notcurses_getvec(self.nc, ts, ni.ptr, @intCast(ni.len));
        return if (ret < 0)
            error.NCGetFailed
        else
            ni[0..@intCast(ret)];
    }

    pub fn getvec_nblock(self: Self, ni: []Input) ![]Input {
        const ret = c.notcurses_getvec_nblock(self.nc, ni.ptr, @intCast(ni.len));
        return if (ret < 0)
            error.NCGetFailed
        else
            ni[0..@intCast(ret)];
    }

    /// Get a file descriptor suitable for input event poll()ing. When this
    /// descriptor becomes available, you can call notcurses_get_nblock(),
    /// and input ought be ready. This file descriptor is *not* necessarily
    /// the file descriptor associated with stdin (but it might be!).
    pub fn inputready_fd(self: Self) c_int {
        return c.notcurses_inputready_fd(self.nc);
    }

    /// Enable or disable the terminal's cursor, if supported, placing it at
    /// 'y', 'x'. Immediate effect (no need for a call to notcurses_render()).
    /// It is an error if 'y', 'x' lies outside the standard plane. Can be
    /// called while already visible to move the cursor.
    pub fn cursor_enable(self: Self, y: c_int, x: c_int) !void {
        const err = c.notcurses_cursor_enable(self.nc, y, x);
        return if (err != 0) error.NCCursorEnableFailed else {};
    }

    /// Disable the hardware cursor. It is an error to call this while the
    /// cursor is already disabled.
    pub fn cursor_disable(self: Self) !void {
        const err = c.notcurses_cursor_disable(self.nc);
        return if (err != 0) error.NCCursorDisableFailed else {};
    }

    /// Get the current location of the terminal's cursor, whether visible or not.
    pub fn cursor_yx(self: Self) !struct { y: isize, x: isize } {
        var y: c_int = undefined;
        var x: c_int = undefined;
        const err = c.notcurses_cursor_yx(self.nc, &y, &x);
        return if (err != 0) error.NCCursorYXFailed else .{ .y = y, .x = x };
    }

    /// Shift to the alternate screen, if available. If already using the alternate
    /// screen, this returns 0 immediately. If the alternate screen is not
    /// available, this returns -1 immediately. Entering the alternate screen turns
    /// off scrolling for the standard plane.
    pub fn enter_alternate_screen(self: Self) void {
        _ = c.notcurses_enter_alternate_screen(self.nc);
    }

    /// Exit the alternate screen. Immediately returns 0 if not currently using the
    /// alternate screen.
    pub fn leave_alternate_screen(self: Self) void {
        _ = c.notcurses_leave_alternate_screen(self.nc);
    }
};

pub const LogLevel = enum(c.ncloglevel_e) {
    silent = c.NCLOGLEVEL_SILENT,
    panic = c.NCLOGLEVEL_PANIC,
    fatal = c.NCLOGLEVEL_FATAL,
    error_ = c.NCLOGLEVEL_ERROR,
    warning = c.NCLOGLEVEL_WARNING,
    info = c.NCLOGLEVEL_INFO,
    verbose = c.NCLOGLEVEL_VERBOSE,
    debug = c.NCLOGLEVEL_DEBUG,
    trace = c.NCLOGLEVEL_TRACE,
};

pub const Align = enum(c.ncalign_e) {
    unaligned = c.NCALIGN_UNALIGNED,
    left = c.NCALIGN_LEFT,
    center = c.NCALIGN_CENTER,
    right = c.NCALIGN_RIGHT,
    pub const top = Align.left;
    pub const bottom = Align.right;

    pub fn val(self: Align) c_int {
        return @intCast(@intFromEnum(self));
    }
};

pub const mice = struct {
    pub const NO_EVENTS = c.NCMICE_NO_EVENTS;
    pub const MOVE_EVENT = c.NCMICE_MOVE_EVENT;
    pub const BUTTON_EVENT = c.NCMICE_BUTTON_EVENT;
    pub const DRAG_EVENT = c.NCMICE_DRAG_EVENT;
    pub const ALL_EVENTS = c.NCMICE_ALL_EVENTS;
};

pub const style = struct {
    pub const mask = c.NCSTYLE_MASK;
    pub const italic = c.NCSTYLE_ITALIC;
    pub const underline = c.NCSTYLE_UNDERLINE;
    pub const undercurl = c.NCSTYLE_UNDERCURL;
    pub const bold = c.NCSTYLE_BOLD;
    pub const struck = c.NCSTYLE_STRUCK;
    pub const none = c.NCSTYLE_NONE;
};

pub const Plane = struct {
    n: *c_plane,

    pub const c_plane = c.struct_ncplane;

    pub const Options = c.struct_ncplane_options;
    pub const option = struct {
        pub const HORALIGNED = c.NCPLANE_OPTION_HORALIGNED;
        pub const VERALIGNED = c.NCPLANE_OPTION_VERALIGNED;
        pub const MARGINALIZED = c.NCPLANE_OPTION_MARGINALIZED;
        pub const FIXED = c.NCPLANE_OPTION_FIXED;
        pub const AUTOGROW = c.NCPLANE_OPTION_AUTOGROW;
        pub const VSCROLL = c.NCPLANE_OPTION_VSCROLL;
    };

    const Self = @This();

    /// Create a new ncplane bound to parent plane 'n', at the offset 'y'x'x' (relative to
    /// the origin of 'n') and the specified size. The number of 'rows' and 'cols'
    /// must both be positive. This plane is initially at the top of the z-buffer,
    /// as if ncplane_move_top() had been called on it. The void* 'userptr' can be
    /// retrieved (and reset) later. A 'name' can be set, used in debugging.
    pub fn init(nopts: *const Options, parent_: Self) !Self {
        const child = c.ncplane_create(parent_.n, nopts);
        return if (child) |p| .{ .n = p } else error.OutOfMemory;
    }

    /// Destroy the specified ncplane. None of its contents will be visible after
    /// the next call to notcurses_render(). It is an error to attempt to destroy
    /// the standard plane.
    pub fn deinit(self: Self) void {
        _ = c.ncplane_destroy(self.n);
    }

    /// Extract the Notcurses context to which this plane is attached.
    pub fn context(self: Self) Context {
        return .{ .nc = c.ncplane_notcurses(self.n) orelse unreachable };
    }

    /// Resize the specified ncplane. The four parameters 'keepy', 'keepx',
    /// 'keepleny', and 'keeplenx' define a subset of the ncplane to keep,
    /// unchanged. This may be a region of size 0, though none of these four
    /// parameters may be negative. 'keepx' and 'keepy' are relative to the ncplane.
    /// They must specify a coordinate within the ncplane's totality. 'yoff' and
    /// 'xoff' are relative to 'keepy' and 'keepx', and place the upper-left corner
    /// of the resized ncplane. Finally, 'ylen' and 'xlen' are the dimensions of the
    /// ncplane after resizing. 'ylen' must be greater than or equal to 'keepleny',
    /// and 'xlen' must be greater than or equal to 'keeplenx'. It is an error to
    /// attempt to resize the standard plane. If either of 'keepleny' or 'keeplenx'
    /// is non-zero, both must be non-zero.
    ///
    /// Essentially, the kept material does not move. It serves to anchor the
    /// resized plane. If there is no kept material, the plane can move freely.
    pub fn resize_keep(self: Self, keepy: c_int, keepx: c_int, keepleny: c_uint, keeplenx: c_uint, yoff: c_int, xoff: c_int, ylen: c_uint, xlen: c_uint) !void {
        const err = c.ncplane_resize(self.n, keepy, keepx, keepleny, keeplenx, yoff, xoff, ylen, xlen);
        if (err != 0) return error.NCPResizeFailed;
    }

    /// Resize the plane, retaining what data we can (everything, unless we're
    /// shrinking in some dimension). Keep the origin where it is.
    pub fn resize_simple(self: Self, ylen: c_uint, xlen: c_uint) !void {
        const err = c.ncplane_resize_simple(self.n, ylen, xlen);
        if (err != 0) return error.NCPResizeFailed;
    }

    /// Return the dimensions of this ncplane. y or x may be NULL.
    pub fn dim_yx(self: Self, noalias y_: ?*c_uint, noalias x_: ?*c_uint) void {
        c.ncplane_dim_yx(self.n, y_, x_);
    }

    /// Return the dimensions of this ncplane. y or x may be NULL.
    pub fn dim_y(self: Self) c_uint {
        return c.ncplane_dim_y(self.n);
    }

    /// Return the dimensions of this ncplane. y or x may be NULL.
    pub fn dim_x(self: Self) c_uint {
        return c.ncplane_dim_x(self.n);
    }

    /// Get the origin of plane 'n' relative to its pile. Either or both of 'x' and
    /// 'y' may be NULL.
    pub fn abs_yx(self: Self, noalias y_: ?*c_int, noalias x_: ?*c_int) void {
        c.ncplane_abs_yx(self.n, y_, x_);
    }

    /// Get the origin of plane 'n' relative to its pile. Either or both of 'x' and
    /// 'y' may be NULL.
    pub fn abs_y(self: Self) c_int {
        return c.ncplane_abs_y(self.n);
    }

    /// Get the origin of plane 'n' relative to its pile. Either or both of 'x' and
    /// 'y' may be NULL.
    pub fn abs_x(self: Self) c_int {
        return c.ncplane_abs_x(self.n);
    }

    /// Get the origin of plane 'n' relative to its bound plane, or pile (if 'n' is
    /// a root plane). To get absolute coordinates, use ncplane_abs_yx().
    pub fn yx(self: Self, noalias y_: ?*c_int, noalias x_: ?*c_int) void {
        c.ncplane_yx(self.n, y_, x_);
    }

    /// Get the origin of plane 'n' relative to its bound plane, or pile (if 'n' is
    /// a root plane). To get absolute coordinates, use ncplane_abs_yx().
    pub fn y(self: Self) c_int {
        return c.ncplane_y(self.n);
    }

    /// Get the origin of plane 'n' relative to its bound plane, or pile (if 'n' is
    /// a root plane). To get absolute coordinates, use ncplane_abs_yx().
    pub fn x(self: Self) c_int {
        return c.ncplane_x(self.n);
    }

    /// Return the topmost plane of the pile containing 'n'.
    pub fn top(self: Self) Plane {
        return .{ .n = c.ncpile_top(self.n) };
    }

    /// Return the bottommost plane of the pile containing 'n'.
    pub fn bottom(self: Self) Plane {
        return .{ .n = c.ncpile_bottom(self.n) };
    }

    /// Convert absolute to relative coordinates based on this plane
    pub fn abs_yx_to_rel(self: Self, y_: ?*c_int, x_: ?*c_int) void {
        var origin_y: c_int = undefined;
        var origin_x: c_int = undefined;
        self.abs_yx(&origin_y, &origin_x);
        if (y_) |y__| y__.* = y__.* - origin_y;
        if (x_) |x__| x__.* = x__.* - origin_x;
    }

    /// Convert relative to absolute coordinates based on this plane
    pub fn rel_yx_to_abs(self: Self, y_: ?*c_int, x_: ?*c_int) void {
        var origin_y: c_int = undefined;
        var origin_x: c_int = undefined;
        self.abs_yx(&origin_y, &origin_x);
        if (y_) |y__| y__.* = y__.* + origin_y;
        if (x_) |x__| x__.* = x__.* + origin_x;
    }

    /// Get the plane to which the plane 'n' is bound, if any.
    pub fn parent(self: Self) Plane {
        return .{ .n = c.ncplane_parent(self.n) orelse unreachable };
    }

    /// Return non-zero iff 'n' is a proper descendent of 'ancestor'.
    pub fn descendant_p(self: Self, ancestor: Self) bool {
        return c.ncplane_descendant_p(self.n, ancestor.n) != 0;
    }

    /// Splice ncplane 'n' out of the z-buffer, and reinsert it above 'above'.
    /// Returns non-zero if 'n' is already in the desired location. 'n' and
    /// 'above' must not be the same plane. If 'above' is NULL, 'n' is moved
    /// to the bottom of its pile.
    pub fn move_above(self: Self, above_: Self) bool {
        return c.ncplane_move_above(self.n, above_.n) != 0;
    }

    /// Splice ncplane 'n' out of the z-buffer, and reinsert it below 'below'.
    /// Returns non-zero if 'n' is already in the desired location. 'n' and
    /// 'below' must not be the same plane. If 'below' is NULL, 'n' is moved to
    /// the top of its pile.
    pub fn move_below(self: Self, above_: Self) bool {
        return c.ncplane_move_below(self.n, above_.n) != 0;
    }

    /// Splice ncplane 'n' out of the z-buffer; reinsert it at the top.
    pub fn move_top(self: Self) void {
        _ = c.ncplane_move_below(self.n, null);
    }

    /// Splice ncplane 'n' out of the z-buffer; reinsert it at the bottom.
    pub fn move_bottom(self: Self) void {
        _ = c.ncplane_move_above(self.n, null);
    }

    /// Splice ncplane 'n' and its bound planes out of the z-buffer, and reinsert
    /// them above 'targ'. Relative order will be maintained between the
    /// reinserted planes. For a plane E bound to C, with z-ordering A B C D E,
    /// moving the C family to the top results in C E A B D, while moving it to
    /// the bottom results in A B D C E.
    pub fn move_family_above(self: Self, targ: Self) void {
        _ = c.ncplane_move_family_above(self.n, targ.n);
    }

    /// Splice ncplane 'n' and its bound planes out of the z-buffer, and reinsert
    /// them below 'targ'. Relative order will be maintained between the
    /// reinserted planes. For a plane E bound to C, with z-ordering A B C D E,
    /// moving the C family to the top results in C E A B D, while moving it to
    /// the bottom results in A B D C E.
    pub fn move_family_below(self: Self, targ: Self) void {
        _ = c.ncplane_move_family_below(self.n, targ.n);
    }

    /// Splice ncplane 'n' and its bound planes out of the z-buffer, and reinsert
    /// them at the top. Relative order will be maintained between the
    /// reinserted planes. For a plane E bound to C, with z-ordering A B C D E,
    /// moving the C family to the top results in C E A B D, while moving it to
    /// the bottom results in A B D C E.
    pub fn move_family_top(self: Self) void {
        _ = c.ncplane_move_family_below(self.n, null);
    }

    /// Splice ncplane 'n' and its bound planes out of the z-buffer, and reinsert
    /// them at the bottom. Relative order will be maintained between the
    /// reinserted planes. For a plane E bound to C, with z-ordering A B C D E,
    /// moving the C family to the top results in C E A B D, while moving it to
    /// the bottom results in A B D C E.
    pub fn move_family_bottom(self: Self) void {
        _ = c.ncplane_move_family_above(self.n, null);
    }

    /// Return the plane below this one, or NULL if this is at the bottom.
    pub fn below(self: Self) ?Self {
        return .{ .n = c.ncplane_below(self.n) orelse return null };
    }

    /// Return the plane above this one, or NULL if this is at the top.
    pub fn above(self: Self) ?Self {
        return .{ .n = c.ncplane_above(self.n) orelse return null };
    }

    /// Effect |r| scroll events on the plane |n|. Returns an error if |n| is not
    /// a scrolling plane, and otherwise returns the number of lines scrolled.
    pub fn scrollup(self: Self, r: c_int) c_int {
        return c.ncplane_scrollup(self.n, r);
    }

    /// Scroll |n| up until |child| is no longer hidden beneath it. Returns an
    /// error if |child| is not a child of |n|, or |n| is not scrolling, or |child|
    /// is fixed. Returns the number of scrolling events otherwise (might be 0).
    /// If the child plane is not fixed, it will likely scroll as well.
    pub fn scrollup_child(self: Self, child: Plane) c_int {
        return c.ncplane_scrollup_child(self.n, child.n);
    }

    /// Retrieve the current contents of the cell under the cursor into 'c'. This
    /// cell is invalidated if the associated plane is destroyed. Returns the number
    /// of bytes in the EGC, or -1 on error.
    pub fn at_cursor_cell(self: Self, cell: *Cell) !usize {
        const bytes_in_cell = c.ncplane_at_cursor_cell(self.n, cell);
        return if (bytes_in_cell < 0) error.NCAtCellFailed else @intCast(bytes_in_cell);
    }

    /// Retrieve the current contents of the specified cell into 'c'. This cell is
    /// invalidated if the associated plane is destroyed. Returns the number of
    /// bytes in the EGC, or -1 on error. Unlike ncplane_at_yx(), when called upon
    /// the secondary columns of a wide glyph, the return can be distinguished from
    /// the primary column (nccell_wide_right_p(c) will return true). It is an
    /// error to call this on a sprixel plane (unlike ncplane_at_yx()).
    pub fn at_yx_cell(self: Self, y_: c_int, x_: c_int, cell: *Cell) !usize {
        const bytes_in_cell = c.ncplane_at_yx_cell(self.n, y_, x_, cell);
        return if (bytes_in_cell < 0) error.NCAtCellFailed else @intCast(bytes_in_cell);
    }

    /// Return a heap-allocated copy of the plane's name, or NULL if it has none.
    pub fn name(self: Self, buf: []u8) []u8 {
        const s = c.ncplane_name(self.n);
        defer c.free(s);
        const s_len = std.mem.len(s);
        const s_ = s[0..s_len :0];
        @memcpy(buf[0..s_len], s_);
        return buf[0..s_len];
    }

    /// Erase every cell in the ncplane (each cell is initialized to the null glyph
    /// and the default channels/styles). All cells associated with this ncplane are
    /// invalidated, and must not be used after the call, *excluding* the base cell.
    /// The cursor is homed. The plane's active attributes are unaffected.
    pub fn erase(self: Self) void {
        c.ncplane_erase(self.n);
    }

    /// Erase every cell in the region starting at {ystart, xstart} and having size
    /// {|ylen|x|xlen|} for non-zero lengths. If ystart and/or xstart are -1, the current
    /// cursor position along that axis is used; other negative values are an error. A
    /// negative ylen means to move up from the origin, and a negative xlen means to move
    /// left from the origin. A positive ylen moves down, and a positive xlen moves right.
    /// A value of 0 for the length erases everything along that dimension. It is an error
    /// if the starting coordinate is not in the plane, but the ending coordinate may be
    /// outside the plane.
    ///
    /// For example, on a plane of 20 rows and 10 columns, with the cursor at row 10 and
    /// column 5, the following would hold:
    ///
    ///  (-1, -1, 0, 1): clears the column to the right of the cursor (column 6)
    ///  (-1, -1, 0, -1): clears the column to the left of the cursor (column 4)
    ///  (-1, -1, INT_MAX, 0): clears all rows with or below the cursor (rows 10--19)
    ///  (-1, -1, -INT_MAX, 0): clears all rows with or above the cursor (rows 0--10)
    ///  (-1, 4, 3, 3): clears from row 5, column 4 through row 7, column 6
    ///  (-1, 4, -3, -3): clears from row 5, column 4 through row 3, column 2
    ///  (4, -1, 0, 3): clears columns 5, 6, and 7
    ///  (-1, -1, 0, 0): clears the plane *if the cursor is in a legal position*
    ///  (0, 0, 0, 0): clears the plane in all cases
    pub fn erase_region(self: Self, ystart: isize, xstart: isize, ylen: isize, xlen: isize) !void {
        const ret = c.ncplane_erase_region(self.n, ystart, xstart, ylen, xlen);
        if (ret != 0) return error.NCPEraseFailed;
    }

    /// Set the ncplane's base nccell to 'c'. The base cell is used for purposes of
    /// rendering anywhere that the ncplane's gcluster is 0. Note that the base cell
    /// is not affected by ncplane_erase(). 'c' must not be a secondary cell from a
    /// multicolumn EGC.
    pub fn set_base(self: Self, egc: [*:0]const u8, stylemask: u16, channels_: u64) !isize {
        const bytes_copied = c.ncplane_set_base(self.n, egc, stylemask, channels_);
        return if (bytes_copied < 0) error.NCSetBaseFailed else @intCast(bytes_copied);
    }

    /// Extract the ncplane's base nccell into 'c'. The reference is invalidated if
    /// 'ncp' is destroyed.
    pub fn base(self: Self, cell: *Cell) void {
        _ = c.ncplane_base(self.n, cell);
    }

    /// Set the ncplane's foreground palette index, set the foreground palette index
    /// bit, set it foreground-opaque, and clear the foreground default color bit.
    pub fn set_fg_palindex(self: Self, idx: c_uint) !void {
        const err = c.ncplane_set_fg_palindex(self.n, idx);
        if (err != 0) return error.NCSetPalIndexFailed;
    }

    /// Set the ncplane's background palette index, set the background palette index
    /// bit, set it background-opaque, and clear the background default color bit.
    pub fn set_bg_palindex(self: Self, idx: c_uint) !void {
        const err = c.ncplane_set_bg_palindex(self.n, idx);
        if (err != 0) return error.NCSetPalIndexFailed;
    }

    /// Set the current foreground color using RGB specifications. If the
    /// terminal does not support directly-specified 3x8b cells (24-bit "TrueColor",
    /// indicated by the "RGB" terminfo capability), the provided values will be
    /// interpreted in some lossy fashion. None of r, g, or b may exceed 255.
    /// "HP-like" terminals require setting foreground and background at the same
    /// time using "color pairs"; Notcurses will manage color pairs transparently.
    pub fn set_fg_rgb(self: Self, channel: u32) !void {
        const err = c.ncplane_set_fg_rgb(self.n, channel);
        if (err != 0) return error.NCSetRgbFailed;
    }

    /// Set the current background color using RGB specifications. If the
    /// terminal does not support directly-specified 3x8b cells (24-bit "TrueColor",
    /// indicated by the "RGB" terminfo capability), the provided values will be
    /// interpreted in some lossy fashion. None of r, g, or b may exceed 255.
    /// "HP-like" terminals require setting foreground and background at the same
    /// time using "color pairs"; Notcurses will manage color pairs transparently.
    pub fn set_bg_rgb(self: Self, channel: u32) !void {
        const err = c.ncplane_set_bg_rgb(self.n, channel);
        if (err != 0) return error.NCSetRgbFailed;
    }

    /// Set the alpha parameters for ncplane 'n'.
    pub fn set_bg_alpha(self: Self, alpha: c_int) !void {
        const err = c.ncplane_set_bg_alpha(self.n, alpha);
        if (err != 0) return error.NCSetAlphaFailed;
    }

    /// Set the alpha and coloring bits of the plane's current channels from a
    /// 64-bit pair of channels.
    pub fn set_channels(self: Self, channels_: u64) void {
        c.ncplane_set_channels(self.n, channels_);
    }

    /// Move this plane relative to the standard plane, or the plane to which it is
    /// bound (if it is bound to a plane). It is an error to attempt to move the
    /// standard plane.
    pub fn move_yx(self: Self, y_: c_int, x_: c_int) !void {
        const err = c.ncplane_move_yx(self.n, y_, x_);
        if (err != 0) return error.NCPlaneMoveFailed;
    }

    /// Replace the cell at the specified coordinates with the provided cell 'c',
    /// and advance the cursor by the width of the cell (but not past the end of the
    /// plane). On success, returns the number of columns the cursor was advanced.
    /// 'c' must already be associated with 'n'. On failure, -1 is returned.
    pub fn putc_yx(self: Self, y_: c_int, x_: c_int, cell: *const Cell) !usize {
        const ret = c.ncplane_putc_yx(self.n, y_, x_, cell);
        return if (ret < 0) error.NCPlanePutYZFailed else @intCast(ret);
    }

    /// Call ncplane_putc_yx() for the current cursor location.
    pub fn putc(self: Self, cell: *const Cell) !usize {
        return self.putc_yx(-1, -1, cell);
    }

    /// Write a series of EGCs to the current location, using the current style.
    /// They will be interpreted as a series of columns (according to the definition
    /// of ncplane_putc()). Advances the cursor by some positive number of columns
    /// (though not beyond the end of the plane); this number is returned on success.
    pub fn putstr(self: Self, gclustarr: [*:0]const u8) !usize {
        const ret = c__ncplane_putstr(self.n, gclustarr);
        return if (ret < 0) error.NCPlanePutStrFailed else @intCast(ret);
    }

    /// Write an aligned series of EGCs to the current location, using the current style.
    pub fn putstr_aligned(self: Self, y_: c_int, align_: Align, s: [*:0]const u8) !usize {
        const ret = c__ncplane_putstr_aligned(self.n, y_, @intFromEnum(align_), s);
        return if (ret < 0) error.NCPlanePutStrFailed else @intCast(ret);
    }

    /// Write a zig formatted series of EGCs to the current location, using the current style.
    /// They will be interpreted as a series of columns (according to the definition
    /// of ncplane_putc()). Advances the cursor by some positive number of columns
    /// (though not beyond the end of the plane); this number is returned on success.
    pub fn print(self: Self, comptime fmt: anytype, args: anytype) !usize {
        var buf: [fmt.len + 4096]u8 = undefined;
        const output = try std.fmt.bufPrint(&buf, fmt, args);
        buf[output.len] = 0;
        if (output.len == 0)
            return 0;
        return self.putstr(@ptrCast(output[0 .. output.len - 1]));
    }

    /// Write an aligned zig formatted series of EGCs to the current location, using the current style.
    pub fn print_aligned(self: Self, y_: c_int, align_: Align, comptime fmt: anytype, args: anytype) !usize {
        var buf: [fmt.len + 4096]u8 = undefined;
        const output = try std.fmt.bufPrint(&buf, fmt, args);
        buf[output.len] = 0;
        return self.putstr_aligned(y_, align_, @ptrCast(output[0 .. output.len - 1]));
    }

    /// Get the opaque user pointer associated with this plane.
    pub fn userptr(self: Self) ?*anyopaque {
        return c.ncplane_userptr(self.n);
    }

    /// Set the opaque user pointer associated with this plane.
    /// Returns the previous userptr after replacing it.
    pub fn set_userptr(self: Self, p: ?*anyopaque) ?*anyopaque {
        return c.ncplane_set_userptr(self.n, p);
    }

    /// Utility resize callbacks. When a parent plane is resized, it invokes each
    /// child's resize callback. Any logic can be run in a resize callback, but
    /// these are some generically useful ones.
    pub const resize = struct {
        /// resize the plane to the visual region's size (used for the standard plane).
        pub const maximize = c.ncplane_resize_maximize;

        /// resize the plane to its parent's size, attempting to enforce the margins
        /// supplied along with NCPLANE_OPTION_MARGINALIZED.
        pub const marginalized = c.ncplane_resize_marginalized;

        /// realign the plane 'n' against its parent, using the alignments specified
        /// with NCPLANE_OPTION_HORALIGNED and/or NCPLANE_OPTION_VERALIGNED.
        pub const realign = c.ncplane_resize_realign;

        /// move the plane such that it is entirely within its parent, if possible.
        /// no resizing is performed.
        pub const placewithin = c.ncplane_resize_placewithin;

        pub fn maximize_vertical(n_: ?*c_plane) callconv(.C) c_int {
            if (n_) |p| {
                const self: Plane = .{ .n = p };
                const rows = self.parent().dim_y();
                const cols = self.dim_x();
                self.resize_simple(rows, cols) catch return -1;
            }
            return 0;
        }
    };

    /// realign the plane 'n' against its parent, using the alignments specified
    /// with NCPLANE_OPTION_HORALIGNED and/or NCPLANE_OPTION_VERALIGNED.
    pub fn realign(self: Self) void {
        _ = c.ncplane_resize_realign(self.n);
    }

    /// Replace the ncplane's existing resizecb with 'resizecb' (which may be NULL).
    /// The standard plane's resizecb may not be changed.
    pub fn set_resizecb(self: Self, resizecb: ?*const fn (?*c_plane) callconv(.C) c_int) void {
        return c.ncplane_set_resizecb(self.n, resizecb);
    }

    /// Move the cursor to the specified position (the cursor needn't be visible).
    /// Pass -1 as either coordinate to hold that axis constant. Returns an erro if the
    /// move would place the cursor outside the plane.
    pub fn cursor_move_yx(self: Self, y_: c_int, x_: c_int) !void {
        const err = c.ncplane_cursor_move_yx(self.n, y_, x_);
        if (err != 0) return error.NCPlaneCursorMoveFailed;
    }

    /// Move the cursor relative to the current cursor position (the cursor needn't
    /// be visible). Returns -1 on error, including target position exceeding the
    /// plane's dimensions.
    pub fn cursor_move_rel(self: Self, y_: c_int, x_: c_int) !void {
        const err = c.ncplane_cursor_move_rel(self.n, y_, x_);
        if (err != 0) return error.NCPlaneCursorMoveFailed;
    }

    /// Move the cursor to 0, 0.
    pub fn home(self: Self) void {
        c.ncplane_home(self.n);
    }

    /// Get the current position of the cursor within n. y and/or x may be NULL.
    pub fn cursor_yx(self: Self, noalias y_: *c_uint, noalias x_: *c_uint) void {
        c.ncplane_cursor_yx(self.n, y_, x_);
    }

    /// Get the current y position of the cursor within n.
    pub fn cursor_y(self: Self) c_uint {
        return c.ncplane_cursor_y(self.n);
    }

    /// Get the current x position of the cursor within n.
    pub fn cursor_x(self: Self) c_uint {
        return c.ncplane_cursor_x(self.n);
    }

    /// Get the current colors and alpha values for ncplane 'n'.
    pub fn channels(self: Self) u64 {
        return c.ncplane_channels(self.n);
    }

    /// Get the current styling for the ncplane 'n'.
    pub fn styles(self: Self) u16 {
        return c.ncplane_styles(self.n);
    }

    /// Set the specified style bits for the ncplane 'n', whether they're actively
    /// supported or not.
    pub fn set_styles(self: Self, stylebits: c_uint) void {
        c.ncplane_set_styles(self.n, stylebits);
    }

    /// Add the specified styles to the ncplane's existing spec.
    pub fn on_styles(self: Self, stylebits: c_uint) void {
        c.ncplane_on_styles(self.n, stylebits);
    }

    /// Remove the specified styles from the ncplane's existing spec.
    pub fn off_styles(self: Self, stylebits: c_uint) void {
        c.ncplane_off_styles(self.n, stylebits);
    }

    /// Initialize a cell with the planes current style and channels
    pub fn cell_init(self: Self) Cell {
        return .{
            .gcluster = 0,
            .gcluster_backstop = 0,
            .width = 0,
            .stylemask = self.styles(),
            .channels = self.channels(),
        };
    }

    /// Breaks the UTF-8 string in 'gcluster' down, setting up the nccell 'c'.
    /// Returns the number of bytes copied out of 'gcluster', or -1 on failure. The
    /// styling of the cell is left untouched, but any resources are released.
    pub fn cell_load(self: Self, cell: *Cell, gcluster: [:0]const u8) !usize {
        const ret = c.nccell_load(self.n, cell, gcluster);
        return if (ret < 0) error.NCCellLoadFailed else @intCast(ret);
    }
};

pub const EXIT_SUCCESS = c.EXIT_SUCCESS;
pub const EXIT_FAILURE = c.EXIT_FAILURE;

pub const CHANNELS_INITIALIZER = c.NCCHANNELS_INITIALIZER;
pub fn channels_set_fg_rgb(arg_channels: *u64, arg_rgb: c_uint) !void {
    const err = c.ncchannels_set_fg_rgb(arg_channels, arg_rgb);
    if (err != 0)
        return error.NCInvalidRGBValue;
}
pub fn channels_set_bg_rgb(arg_channels: *u64, arg_rgb: c_uint) !void {
    const err = c.ncchannels_set_bg_rgb(arg_channels, arg_rgb);
    if (err != 0)
        return error.NCInvalidRGBValue;
}
pub fn channels_set_fg_alpha(arg_channels: *u64, arg_alpha: c_uint) !void {
    const err = c.ncchannels_set_fg_alpha(arg_channels, arg_alpha);
    if (err != 0)
        return error.NCInvalidAlphaValue;
}
pub fn channels_set_bg_alpha(arg_channels: *u64, arg_alpha: c_uint) !void {
    const err = c.ncchannels_set_bg_alpha(arg_channels, arg_alpha);
    if (err != 0)
        return error.NCInvalidAlphaValue;
}
pub const channels_set_bchannel = c.ncchannels_set_bchannel;
pub const channels_set_fchannel = c.ncchannels_set_fchannel;

pub const channel_set_rgb8 = c.ncchannel_set_rgb8;
pub const channel_set_rgb8_clipped = c.ncchannel_set_rgb8_clipped;

pub const ALPHA_HIGHCONTRAST = c.NCALPHA_HIGHCONTRAST;
pub const ALPHA_TRANSPARENT = c.NCALPHA_TRANSPARENT;
pub const ALPHA_BLEND = c.NCALPHA_BLEND;
pub const ALPHA_OPAQUE = c.NCALPHA_OPAQUE;

pub const Menu = struct {
    n: *c.ncmenu,

    pub const Options = c.ncmenu_options;
    pub const option = struct {
        pub const BOTTOM = c.NCMENU_OPTION_BOTTOM;
        pub const HIDING = c.NCMENU_OPTION_HIDING;
    };

    const Self = @This();

    /// Create a menu with the specified options, bound to the specified plane.
    pub fn init(parent: Plane, opts: Options) !Menu {
        const opts_ = opts;
        return .{ .n = c.ncmenu_create(parent.n, &opts_) orelse return error.NCMenuCreateFailed };
    }

    /// Destroy a menu created with Menu.init().
    pub fn deinit(self: *Self) void {
        c.ncmenu_destroy(self.n);
    }

    /// Offer the input to the menu. If it's relevant, this function returns true,
    /// and the input ought not be processed further. If it's irrelevant to the
    /// menu, false is returned. Relevant inputs include:
    ///  * mouse movement over a hidden menu
    ///  * a mouse click on a menu section (the section is unrolled)
    ///  * a mouse click outside of an unrolled menu (the menu is rolled up)
    ///  * left or right on an unrolled menu (navigates among sections)
    ///  * up or down on an unrolled menu (navigates among items)
    ///  * escape on an unrolled menu (the menu is rolled up)
    pub fn offer_input(self: *Self, nc: *const c.ncinput) bool {
        return c.ncmenu_offer_input(self.n, nc);
    }

    /// Return the item description corresponding to the mouse click 'click'. The
    /// item must be on an actively unrolled section, and the click must be in the
    /// area of a valid item.
    pub fn mouse_selected(self: Self, click: *const Input) ?[]const u8 {
        const p = c.ncmenu_mouse_selected(self.n, click, null);
        return if (p) |p_| p_[0..std.mem.len(p_)] else null;
    }

    /// Return the selected item description, or NULL if no section is unrolled. If
    /// 'ni' is not NULL, and the selected item has a shortcut, 'ni' will be filled
    /// in with that shortcut--this can allow faster matching.
    pub fn selected(self: *Self, ni: *Input) ?[:0]const u8 {
        const p = c.ncmenu_selected(self.n, ni);
        return if (p) |p_| p_[0..std.mem.len(p_) :0] else null;
    }

    /// Disable or enable a menu item. Returns an error if the item was not found.
    pub fn item_set_status(self: Self, section: [:0]const u8, item: [:0]const u8, enabled: bool) !void {
        const err = c.ncmenu_item_set_status(self.n, section, item, enabled);
        if (err != 0) return error.NCMenuItemNotFound;
    }

    pub const Item = c.ncmenu_item;
    pub const Section = c.ncmenu_section;
};

pub const key = struct {
    pub const INVALID = c.NCKEY_INVALID;
    pub const RESIZE = c.NCKEY_RESIZE;
    pub const UP = c.NCKEY_UP;
    pub const RIGHT = c.NCKEY_RIGHT;
    pub const DOWN = c.NCKEY_DOWN;
    pub const LEFT = c.NCKEY_LEFT;
    pub const INS = c.NCKEY_INS;
    pub const DEL = c.NCKEY_DEL;
    pub const BACKSPACE = c.NCKEY_BACKSPACE;
    pub const PGDOWN = c.NCKEY_PGDOWN;
    pub const PGUP = c.NCKEY_PGUP;
    pub const HOME = c.NCKEY_HOME;
    pub const END = c.NCKEY_END;
    pub const F00 = c.NCKEY_F00;
    pub const F01 = c.NCKEY_F01;
    pub const F02 = c.NCKEY_F02;
    pub const F03 = c.NCKEY_F03;
    pub const F04 = c.NCKEY_F04;
    pub const F05 = c.NCKEY_F05;
    pub const F06 = c.NCKEY_F06;
    pub const F07 = c.NCKEY_F07;
    pub const F08 = c.NCKEY_F08;
    pub const F09 = c.NCKEY_F09;
    pub const F10 = c.NCKEY_F10;
    pub const F11 = c.NCKEY_F11;
    pub const F12 = c.NCKEY_F12;
    pub const F13 = c.NCKEY_F13;
    pub const F14 = c.NCKEY_F14;
    pub const F15 = c.NCKEY_F15;
    pub const F16 = c.NCKEY_F16;
    pub const F17 = c.NCKEY_F17;
    pub const F18 = c.NCKEY_F18;
    pub const F19 = c.NCKEY_F19;
    pub const F20 = c.NCKEY_F20;
    pub const F21 = c.NCKEY_F21;
    pub const F22 = c.NCKEY_F22;
    pub const F23 = c.NCKEY_F23;
    pub const F24 = c.NCKEY_F24;
    pub const F25 = c.NCKEY_F25;
    pub const F26 = c.NCKEY_F26;
    pub const F27 = c.NCKEY_F27;
    pub const F28 = c.NCKEY_F28;
    pub const F29 = c.NCKEY_F29;
    pub const F30 = c.NCKEY_F30;
    pub const F31 = c.NCKEY_F31;
    pub const F32 = c.NCKEY_F32;
    pub const F33 = c.NCKEY_F33;
    pub const F34 = c.NCKEY_F34;
    pub const F35 = c.NCKEY_F35;
    pub const F36 = c.NCKEY_F36;
    pub const F37 = c.NCKEY_F37;
    pub const F38 = c.NCKEY_F38;
    pub const F39 = c.NCKEY_F39;
    pub const F40 = c.NCKEY_F40;
    pub const F41 = c.NCKEY_F41;
    pub const F42 = c.NCKEY_F42;
    pub const F43 = c.NCKEY_F43;
    pub const F44 = c.NCKEY_F44;
    pub const F45 = c.NCKEY_F45;
    pub const F46 = c.NCKEY_F46;
    pub const F47 = c.NCKEY_F47;
    pub const F48 = c.NCKEY_F48;
    pub const F49 = c.NCKEY_F49;
    pub const F50 = c.NCKEY_F50;
    pub const F51 = c.NCKEY_F51;
    pub const F52 = c.NCKEY_F52;
    pub const F53 = c.NCKEY_F53;
    pub const F54 = c.NCKEY_F54;
    pub const F55 = c.NCKEY_F55;
    pub const F56 = c.NCKEY_F56;
    pub const F57 = c.NCKEY_F57;
    pub const F58 = c.NCKEY_F58;
    pub const F59 = c.NCKEY_F59;
    pub const F60 = c.NCKEY_F60;
    pub const ENTER = c.NCKEY_ENTER;
    pub const CLS = c.NCKEY_CLS;
    pub const DLEFT = c.NCKEY_DLEFT;
    pub const DRIGHT = c.NCKEY_DRIGHT;
    pub const ULEFT = c.NCKEY_ULEFT;
    pub const URIGHT = c.NCKEY_URIGHT;
    pub const CENTER = c.NCKEY_CENTER;
    pub const BEGIN = c.NCKEY_BEGIN;
    pub const CANCEL = c.NCKEY_CANCEL;
    pub const CLOSE = c.NCKEY_CLOSE;
    pub const COMMAND = c.NCKEY_COMMAND;
    pub const COPY = c.NCKEY_COPY;
    pub const EXIT = c.NCKEY_EXIT;
    pub const PRINT = c.NCKEY_PRINT;
    pub const REFRESH = c.NCKEY_REFRESH;
    pub const SEPARATOR = c.NCKEY_SEPARATOR;
    pub const CAPS_LOCK = c.NCKEY_CAPS_LOCK;
    pub const SCROLL_LOCK = c.NCKEY_SCROLL_LOCK;
    pub const NUM_LOCK = c.NCKEY_NUM_LOCK;
    pub const PRINT_SCREEN = c.NCKEY_PRINT_SCREEN;
    pub const PAUSE = c.NCKEY_PAUSE;
    pub const MENU = c.NCKEY_MENU;
    pub const MEDIA_PLAY = c.NCKEY_MEDIA_PLAY;
    pub const MEDIA_PAUSE = c.NCKEY_MEDIA_PAUSE;
    pub const MEDIA_PPAUSE = c.NCKEY_MEDIA_PPAUSE;
    pub const MEDIA_REV = c.NCKEY_MEDIA_REV;
    pub const MEDIA_STOP = c.NCKEY_MEDIA_STOP;
    pub const MEDIA_FF = c.NCKEY_MEDIA_FF;
    pub const MEDIA_REWIND = c.NCKEY_MEDIA_REWIND;
    pub const MEDIA_NEXT = c.NCKEY_MEDIA_NEXT;
    pub const MEDIA_PREV = c.NCKEY_MEDIA_PREV;
    pub const MEDIA_RECORD = c.NCKEY_MEDIA_RECORD;
    pub const MEDIA_LVOL = c.NCKEY_MEDIA_LVOL;
    pub const MEDIA_RVOL = c.NCKEY_MEDIA_RVOL;
    pub const MEDIA_MUTE = c.NCKEY_MEDIA_MUTE;
    pub const LSHIFT = c.NCKEY_LSHIFT;
    pub const LCTRL = c.NCKEY_LCTRL;
    pub const LALT = c.NCKEY_LALT;
    pub const LSUPER = c.NCKEY_LSUPER;
    pub const LHYPER = c.NCKEY_LHYPER;
    pub const LMETA = c.NCKEY_LMETA;
    pub const RSHIFT = c.NCKEY_RSHIFT;
    pub const RCTRL = c.NCKEY_RCTRL;
    pub const RALT = c.NCKEY_RALT;
    pub const RSUPER = c.NCKEY_RSUPER;
    pub const RHYPER = c.NCKEY_RHYPER;
    pub const RMETA = c.NCKEY_RMETA;
    pub const L3SHIFT = c.NCKEY_L3SHIFT;
    pub const L5SHIFT = c.NCKEY_L5SHIFT;
    pub const MOTION = c.NCKEY_MOTION;
    pub const BUTTON1 = c.NCKEY_BUTTON1;
    pub const BUTTON2 = c.NCKEY_BUTTON2;
    pub const BUTTON3 = c.NCKEY_BUTTON3;
    pub const BUTTON4 = c.NCKEY_BUTTON4;
    pub const BUTTON5 = c.NCKEY_BUTTON5;
    pub const BUTTON6 = c.NCKEY_BUTTON6;
    pub const BUTTON7 = c.NCKEY_BUTTON7;
    pub const BUTTON8 = c.NCKEY_BUTTON8;
    pub const BUTTON9 = c.NCKEY_BUTTON9;
    pub const BUTTON10 = c.NCKEY_BUTTON10;
    pub const BUTTON11 = c.NCKEY_BUTTON11;
    pub const SIGNAL = c.NCKEY_SIGNAL;
    pub const EOF = c.NCKEY_EOF;
    pub const SCROLL_UP = c.NCKEY_SCROLL_UP;
    pub const SCROLL_DOWN = c.NCKEY_SCROLL_DOWN;
    pub const RETURN = c.NCKEY_RETURN;
    pub const TAB = c.NCKEY_TAB;
    pub const ESC = c.NCKEY_ESC;
    pub const SPACE = c.NCKEY_SPACE;

    /// Is this uint32_t a synthesized event?
    pub fn synthesized_p(w: u32) bool {
        return c.nckey_synthesized_p(w);
    }
};

pub const mod = struct {
    pub const SHIFT = c.NCKEY_MOD_SHIFT;
    pub const ALT = c.NCKEY_MOD_ALT;
    pub const CTRL = c.NCKEY_MOD_CTRL;
    pub const SUPER = c.NCKEY_MOD_SUPER;
    pub const HYPER = c.NCKEY_MOD_HYPER;
    pub const META = c.NCKEY_MOD_META;
    pub const CAPSLOCK = c.NCKEY_MOD_CAPSLOCK;
    pub const NUMLOCK = c.NCKEY_MOD_NUMLOCK;
};

pub fn key_string(ni: *const Input) []const u8 {
    return if (ni.utf8[0] == 0) key_id_string(ni.id) else std.mem.span(@as([*:0]const u8, @ptrCast(&ni.utf8)));
}

pub fn key_id_string(k: u32) []const u8 {
    return switch (k) {
        key.INVALID => "invalid",
        key.RESIZE => "resize",
        key.UP => "up",
        key.RIGHT => "right",
        key.DOWN => "down",
        key.LEFT => "left",
        key.INS => "ins",
        key.DEL => "del",
        key.BACKSPACE => "backspace",
        key.PGDOWN => "pgdown",
        key.PGUP => "pgup",
        key.HOME => "home",
        key.END => "end",
        key.F00 => "f00",
        key.F01 => "f01",
        key.F02 => "f02",
        key.F03 => "f03",
        key.F04 => "f04",
        key.F05 => "f05",
        key.F06 => "f06",
        key.F07 => "f07",
        key.F08 => "f08",
        key.F09 => "f09",
        key.F10 => "f10",
        key.F11 => "f11",
        key.F12 => "f12",
        key.F13 => "f13",
        key.F14 => "f14",
        key.F15 => "f15",
        key.F16 => "f16",
        key.F17 => "f17",
        key.F18 => "f18",
        key.F19 => "f19",
        key.F20 => "f20",
        key.F21 => "f21",
        key.F22 => "f22",
        key.F23 => "f23",
        key.F24 => "f24",
        key.F25 => "f25",
        key.F26 => "f26",
        key.F27 => "f27",
        key.F28 => "f28",
        key.F29 => "f29",
        key.F30 => "f30",
        key.F31 => "f31",
        key.F32 => "f32",
        key.F33 => "f33",
        key.F34 => "f34",
        key.F35 => "f35",
        key.F36 => "f36",
        key.F37 => "f37",
        key.F38 => "f38",
        key.F39 => "f39",
        key.F40 => "f40",
        key.F41 => "f41",
        key.F42 => "f42",
        key.F43 => "f43",
        key.F44 => "f44",
        key.F45 => "f45",
        key.F46 => "f46",
        key.F47 => "f47",
        key.F48 => "f48",
        key.F49 => "f49",
        key.F50 => "f50",
        key.F51 => "f51",
        key.F52 => "f52",
        key.F53 => "f53",
        key.F54 => "f54",
        key.F55 => "f55",
        key.F56 => "f56",
        key.F57 => "f57",
        key.F58 => "f58",
        key.F59 => "f59",
        key.F60 => "f60",
        key.ENTER => "enter", // aka key.RETURN => "return",
        key.CLS => "cls",
        key.DLEFT => "dleft",
        key.DRIGHT => "dright",
        key.ULEFT => "uleft",
        key.URIGHT => "uright",
        key.CENTER => "center",
        key.BEGIN => "begin",
        key.CANCEL => "cancel",
        key.CLOSE => "close",
        key.COMMAND => "command",
        key.COPY => "copy",
        key.EXIT => "exit",
        key.PRINT => "print",
        key.REFRESH => "refresh",
        key.SEPARATOR => "separator",
        key.CAPS_LOCK => "caps_lock",
        key.SCROLL_LOCK => "scroll_lock",
        key.NUM_LOCK => "num_lock",
        key.PRINT_SCREEN => "print_screen",
        key.PAUSE => "pause",
        key.MENU => "menu",
        key.MEDIA_PLAY => "media_play",
        key.MEDIA_PAUSE => "media_pause",
        key.MEDIA_PPAUSE => "media_ppause",
        key.MEDIA_REV => "media_rev",
        key.MEDIA_STOP => "media_stop",
        key.MEDIA_FF => "media_ff",
        key.MEDIA_REWIND => "media_rewind",
        key.MEDIA_NEXT => "media_next",
        key.MEDIA_PREV => "media_prev",
        key.MEDIA_RECORD => "media_record",
        key.MEDIA_LVOL => "media_lvol",
        key.MEDIA_RVOL => "media_rvol",
        key.MEDIA_MUTE => "media_mute",
        key.LSHIFT => "lshift",
        key.LCTRL => "lctrl",
        key.LALT => "lalt",
        key.LSUPER => "lsuper",
        key.LHYPER => "lhyper",
        key.LMETA => "lmeta",
        key.RSHIFT => "rshift",
        key.RCTRL => "rctrl",
        key.RALT => "ralt",
        key.RSUPER => "rsuper",
        key.RHYPER => "rhyper",
        key.RMETA => "rmeta",
        key.L3SHIFT => "l3shift",
        key.L5SHIFT => "l5shift",
        key.MOTION => "motion",
        key.BUTTON1 => "button1",
        key.BUTTON2 => "button2",
        key.BUTTON3 => "button3",
        key.BUTTON4 => "button4", // aka key.SCROLL_UP => "scroll_up",
        key.BUTTON5 => "button5", // aka key.SCROLL_DOWN => "scroll_down",
        key.BUTTON6 => "button6",
        key.BUTTON7 => "button7",
        key.BUTTON8 => "button8",
        key.BUTTON9 => "button9",
        key.BUTTON10 => "button10",
        key.BUTTON11 => "button11",
        key.SIGNAL => "signal",
        key.EOF => "eof",
        key.TAB => "tab",
        key.ESC => "esc",
        key.SPACE => "space",
        else => std.fmt.bufPrint(&key_string_buffer, "{u}", .{@as(u21, @intCast(k))}) catch return "ERROR",
    };
}

pub const Input = c.ncinput;

pub fn input() Input {
    return comptime if (@hasField(Input, "eff_text")) .{
        .id = 0,
        .y = 0,
        .x = 0,
        .utf8 = [_]u8{0} ** 5,
        .alt = false,
        .shift = false,
        .ctrl = false,
        .evtype = 0,
        .modifiers = 0,
        .ypx = 0,
        .xpx = 0,
        .eff_text = [_]u32{0} ** 4,
    } else .{
        .id = 0,
        .y = 0,
        .x = 0,
        .utf8 = [_]u8{0} ** 5,
        .alt = false,
        .shift = false,
        .ctrl = false,
        .evtype = 0,
        .modifiers = 0,
        .ypx = 0,
        .xpx = 0,
    };
}

pub fn isShift(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 1)))) != 0;
}
pub fn isCtrl(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 4)))) != 0;
}
pub fn isAlt(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 2)))) != 0;
}
pub fn isMeta(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 32)))) != 0;
}
pub fn isSuper(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 8)))) != 0;
}
pub fn isHyper(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 16)))) != 0;
}
pub fn isCapslock(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 64)))) != 0;
}
pub fn isNumlock(modifiers: u32) bool {
    return (modifiers & @as(c_uint, @bitCast(@as(c_int, 128)))) != 0;
}

pub const event_type = struct {
    pub const UNKNOWN = c.NCTYPE_UNKNOWN;
    pub const PRESS = c.NCTYPE_PRESS;
    pub const REPEAT = c.NCTYPE_REPEAT;
    pub const RELEASE = c.NCTYPE_RELEASE;
};

pub fn typeToString(t: c.ncintype_e) []const u8 {
    return switch (t) {
        event_type.PRESS => "P",
        event_type.RELEASE => "R",
        event_type.REPEAT => "r",
        else => "U",
    };
}

pub const Cell = c.nccell;
pub const cell_empty = Cell{
    .gcluster = 0,
    .gcluster_backstop = 0,
    .width = 0,
    .stylemask = 0,
    .channels = 0,
};

/// return the number of columns occupied by 'c'. see ncstrwidth() for an
/// equivalent for multiple EGCs.
pub const cell_cols = c.nccell_cols;

/// Is the cell part of a multicolumn element?
pub const cell_double_wide_p = c.nccell_double_wide_p;

/// Is this the right half of a wide character?
pub const cell_wide_right_p = c.nccell_wide_right_p;

/// Is this the left half of a wide character?
pub const cell_wide_left_p = c.nccell_wide_left_p;

/// Set the specified style bits for the nccell 'c', whether they're actively
/// supported or not. Only the lower 16 bits are meaningful.
pub const cell_set_styles = c.nccell_set_styles;

/// Add the specified styles (in the LSBs) to the nccell's existing spec,
/// whether they're actively supported or not.
pub const cell_on_styles = c.nccell_on_styles;

/// Remove the specified styles (in the LSBs) from the nccell's existing spec.
pub const cell_off_styles = c.nccell_off_styles;

/// Returns the number of columns occupied by the longest valid prefix of a
/// multibyte (UTF-8) string. If an invalid character is encountered, -1 will be
/// returned, and the number of valid bytes and columns will be written into
/// *|validbytes| and *|validwidth| (assuming them non-NULL). If the entire
/// string is valid, *|validbytes| and *|validwidth| reflect the entire string.
pub fn wcwidth(egcs: []const u8) !usize {
    var buf = if (egcs.len <= egc_buffer.len) &egc_buffer else return error.Overflow;
    @memcpy(buf[0..egcs.len], egcs);
    buf[egcs.len] = 0;
    return ncstrwidth(buf);
}

/// Returns the number of columns occupied by a multibyte (UTF-8) string.
fn ncstrwidth(egcs: [:0]const u8) !usize {
    var validbytes: c_int = 0;
    var validwidth: c_int = 0;
    const ret = c.ncstrwidth(egcs.ptr, &validbytes, &validwidth);
    return if (ret < 0) error.InvalidChar else @intCast(validwidth);
}

/// Calculate the length and width of the next EGC in the UTF-8 string input.
/// We use libunistring's uc_is_grapheme_break() to segment EGCs. Writes the
/// number of columns to '*colcount'. Returns the number of bytes consumed,
/// not including any NUL terminator. Neither the number of bytes nor columns
/// is necessarily equal to the number of decoded code points. Such are the
/// ways of Unicode. uc_is_grapheme_break() wants UTF-32, which is fine, because
/// we need wchar_t to use wcwidth() anyway FIXME except this doesn't work with
/// 16-bit wchar_t!
pub fn ncegc_len(egcs: []const u8, colcount: *c_int) !usize {
    if (egcs[0] < 128) {
        colcount.* = 1;
        return 1;
    }
    const buf_size = 64;
    var egc_buf: [buf_size:0]u8 = undefined;
    var buf = if (egcs.len <= buf_size)
        &egc_buf
    else if (egcs.len <= egc_buffer.len)
        &egc_buffer
    else
        return error.Overflow;
    @memcpy(buf[0..egcs.len], egcs);
    buf[egcs.len] = 0;
    const ret = c.utf8_egc_len(buf.ptr, colcount);
    return if (ret < 0) error.InvalidChar else @intCast(ret);
}

/// input functions like notcurses_get() return ucs32-encoded uint32_t. convert
/// a series of uint32_t to utf8. result must be at least 4 bytes per input
/// uint32_t (6 bytes per uint32_t will future-proof against Unicode expansion).
/// the number of bytes used is returned, or -1 if passed illegal ucs32, or too
/// small of a buffer.
pub fn ucs32_to_utf8(ucs32: []const u32, utf8: []u8) !usize {
    const ret = c.notcurses_ucs32_to_utf8(ucs32.ptr, @intCast(ucs32.len), utf8.ptr, utf8.len);
    if (ret < 0) return error.Ucs32toUtf8Error;
    return @intCast(ret);
}

// the following functions are workarounds for miscompilation of notcurses.h by cImport

fn c__ncplane_putstr_yx(arg_n: ?*c.struct_ncplane, arg_y: c_int, arg_x: c_int, arg_gclusters: [*c]const u8) callconv(.C) c_int {
    var n = arg_n;
    _ = &n;
    var y = arg_y;
    _ = &y;
    var x = arg_x;
    _ = &x;
    var gclusters = arg_gclusters;
    _ = &gclusters;
    var ret: c_int = 0;
    _ = &ret;
    while (gclusters.* != 0) {
        var wcs: usize = undefined;
        _ = &wcs;
        var cols: c_int = c.ncplane_putegc_yx(n, y, x, gclusters, &wcs);
        _ = &cols;
        if (cols < @as(c_int, 0)) {
            return -ret;
        }
        if (wcs == @as(usize, @bitCast(@as(c_long, @as(c_int, 0))))) {
            break;
        }
        y = -@as(c_int, 1);
        x = -@as(c_int, 1);
        gclusters += wcs;
        ret += cols;
    }
    return ret;
}
fn c__ncplane_putstr(arg_n: ?*c.struct_ncplane, arg_gclustarr: [*:0]const u8) callconv(.C) c_int {
    var n = arg_n;
    _ = &n;
    var gclustarr = arg_gclustarr;
    _ = &gclustarr;
    return c__ncplane_putstr_yx(n, -@as(c_int, 1), -@as(c_int, 1), gclustarr);
}
fn c__ncplane_putstr_aligned(arg_n: ?*c.struct_ncplane, arg_y: c_int, arg_align: c.ncalign_e, arg_s: [*c]const u8) callconv(.C) c_int {
    var n = arg_n;
    _ = &n;
    var y = arg_y;
    _ = &y;
    var @"align" = arg_align;
    _ = &@"align";
    var s = arg_s;
    _ = &s;
    var validbytes: c_int = undefined;
    _ = &validbytes;
    var validwidth: c_int = undefined;
    _ = &validwidth;
    _ = c.ncstrwidth(s, &validbytes, &validwidth);
    var xpos: c_int = c.ncplane_halign(n, @"align", validwidth);
    _ = &xpos;
    if (xpos < @as(c_int, 0)) {
        xpos = 0;
    }
    return c__ncplane_putstr_yx(n, y, xpos, s);
}
