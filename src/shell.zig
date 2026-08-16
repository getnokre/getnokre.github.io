const std = @import("std");

const Callback = *const fn (ctx: ?*anyopaque, tag: [*]const u8, len: usize) callconv(.c) void;

const tag = "en";

export fn nokre_locale_install(ctx: ?*anyopaque, cb: Callback) void {
    cb(ctx, tag.ptr, tag.len);
}

export fn nokre_locale_uninstall() void {}

export fn nokre_open_url_open(url: [*]const u8, len: usize) c_int {
    _ = url;
    _ = len;
    return 1;
}
