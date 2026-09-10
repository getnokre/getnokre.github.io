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

// A generator has no clipboard, and both of these are still linked: the
// edit row a field raises carries Copy and Paste, so every app that can
// hold a caret reaches them (nokre's `overlays.runEditAction`). The
// pages this process writes are built and serialized without anyone
// standing in a field, so neither is ever called — but a symbol that is
// reachable has to resolve, and answering with nothing is the honest
// stub. The web build these pages carry has the real pair, from
// `services.js`.
export fn nokre_shell_write_clipboard(utf8: [*]const u8, len: usize) void {
    _ = utf8;
    _ = len;
}

export fn nokre_shell_request_paste() void {}
