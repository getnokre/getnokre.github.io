//! The generator is a platform shell.
//!
//! nokre's five shells all do the same two things: hand the app events,
//! and take the frame it renders (docs/internals/platform-shells.md,
//! which holds the count of record).
//! This one has no events and its frame is HTML, but it sits in exactly
//! the same seat, so it owes the same C hooks a shell owes — today
//! that is the locale pair a native build links (install, and the
//! uninstall App.deinit disarms it with — src/services/locale/locale.h)
//! and open_url's one verb (src/services/open_url/open_url.h).
//!
//! Only the generator links this. The live half (`web.zig`) is not a
//! shell — the browser is — and the locale service's own web leg
//! exports the lane the driver seeds `navigator.language` through.
//!
//! The tag it reports is `en`, flat — and it decides nothing. A
//! generator writes every page of every locale its catalog carries
//! (main.zig's loop over `l10n.locales`), so which language a page is
//! in comes from the axis and never from the machine the build ran on;
//! this hook answers for that machine, which is a claim about a laptop
//! and not about the site. Reporting anything else would be a shell
//! lying about the device, which is a strange thing for a page about
//! determinism to ship — and a build whose output depended on the
//! answer would be a stranger one.

const std = @import("std");

const Callback = *const fn (ctx: ?*anyopaque, tag: [*]const u8, len: usize) callconv(.c) void;

const tag = "en";

/// Stores nothing: a generator's locale cannot change mid-run, so the
/// synchronous install-time fire is the whole contract and there is no
/// change lane to keep a handle for.
export fn nokre_locale_install(ctx: ?*anyopaque, cb: Callback) void {
    cb(ctx, tag.ptr, tag.len);
}

/// Deinit's half of the contract: forget the stored ctx + cb, so a
/// change can never land on freed app state. This shell stored nothing
/// — the synchronous fire above was the whole exchange — so there is
/// nothing to forget.
export fn nokre_locale_uninstall() void {}

/// open_url's verb, which this shell can never be asked to perform: the
/// hook fires from activation, and a generator has no user whose press
/// could activate anything. The external links it writes are anchors —
/// the reader's browser does the opening, on the reader's machine, long
/// after this process exited. The export exists because a shell owes it
/// (src/services/open_url/open_url.h), not because it will ever run —
/// and if it somehow did, "did not start" is the truthful answer, since
/// no browser was asked.
export fn nokre_open_url_open(url: [*]const u8, len: usize) c_int {
    _ = url;
    _ = len;
    return 1;
}
