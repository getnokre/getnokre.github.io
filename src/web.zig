//! The same site, live.
//!
//! `main.zig` is this site's static driver: it builds every screen and
//! writes each one out as a file. This is the other half of the pair
//! nokre's DOM edition ships — the identical `App`, over the identical
//! route table, running in the reader's browser on top of the file the
//! generator already wrote (`docs/internals/dom-edition.md`).
//!
//! It exists because a generated page is a screen measured with a ruler
//! that is not the reader's. A build has no font metrics and no
//! viewport, so `text.Measurer.fixed` answers every measured question
//! against a 1280px window: prose wraps somewhere else, and a nav
//! roster that does not fit a phone is never told so, because
//! `navCollapses` was asked about a screen nobody was looking at. Live,
//! the browser is the ruler, and the answers are retaken against the
//! column the reader actually has.
//!
//! Three decls are the whole of the contract (live.zig states it):
//! `nokreWebBuild` is the app, `nokreWebSeed` is this page's Markdown
//! arriving before the first build needs it, and `nokreWebRefs` is the
//! promise that a re-render writes the same hrefs the file has.
//!
//! There is no `shell.zig` here. A generator is a platform shell and
//! owes the locale hook; a wasm module is not — the locale service's
//! own web leg exports the seed lane the driver fills from
//! `navigator.language`.

const std = @import("std");
const nok = @import("nokre");

const content = @import("content.zig");
const links = @import("links.zig");
const pages = @import("pages.zig");

comptime {
    // The exports are nokre's — which edition a wasm build carries is
    // declared there, not here. What this root still owes is the
    // reference: nothing calls into an app on the web (the browser
    // drives the module's exports and `main` never runs), so without
    // this nothing pulls the library into the build and the module
    // comes out empty.
    _ = nok;
}

/// The viewport the app is constructed with, replaced by the real one
/// before a frame is ever rendered: `nokre_dom_boot` reports the mount
/// element's width and the window's height, in that same call. It is a
/// placeholder and nothing reads it, which is why it is the smallest
/// honest thing rather than a second copy of the generator's 1280.
const initial: nok.Size = .{ .w = 320, .h = 568 };

/// One page, one source.
///
/// Every route reference on this site is a real link to a real file, so
/// the live driver never builds a screen other than the one the
/// document already is (live.js's `addressing: "documents"`). The
/// document hands over its own Markdown and every documentation route
/// is given it — an entry only the route it belongs to will ever read.
var sources: [pages.all.len][]const u8 = @splat("");
var site: content.Site = undefined;
var destinations: [pages.destinations.len]nok.Destination = undefined;
var resolver: links.Live = undefined;

/// Before boot, so the first `build` has it (live.zig, and
/// services/locale/web.zig for the ordering rule this follows). The
/// bytes belong to the driver and outlive this call.
pub fn nokreWebSeed(bytes: []const u8) void {
    for (pages.all, 0..) |p, i| {
        if (p.md.len != 0) sources[i] = bytes;
    }
}

pub fn nokreWebBuild(gpa: std.mem.Allocator) !*nok.App {
    site = .{ .gpa = gpa, .sources = &sources };
    resolver = .{ .arena = .init(gpa) };

    const app = try gpa.create(nok.App);
    app.* = try nok.App.init(gpa, .{
        .viewport = initial,
        .routes = &content.routes,
        .ctx = &site,
    });
    for (pages.destinations, 0..) |name, i| {
        destinations[i] = .{ .route = name, .icon = pages.find(name).?.icon };
    }
    try app.setNav(&destinations);
    // A screen to be on if the driver was given no route — the app is
    // its own home page. A generated file always names its screen, and
    // `boot` switches to it before the first frame.
    try app.router.switchTo(app, "home");
    return app;
}

pub fn nokreWebRefs(_: *nok.App) nok.render.dom.Refs {
    return resolver.refs();
}
