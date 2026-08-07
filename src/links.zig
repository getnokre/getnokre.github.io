//! Where a reference points.
//!
//! nokre navigates its own screens and nothing else: a `[label](dest)`
//! in a document is an in-app route reference, resolved by the router
//! at activation (`docs/markdown.md`). nokre's docs are written that
//! way — `[elements.md](elements.md)`, `[color.zig](../src/core/color.zig)`
//! — and every one of those destinations is a legal route name, because
//! `.` and `-` are legal argument bytes and `/` is only ever rejected
//! at resolution.
//!
//! So this module is the router's `resolve` for the HTML edition, and
//! it has the same posture: a reference either names something this
//! site has, or the build fails. Nothing degrades quietly into a 404.
//!
//! The one thing it does that nokre's router will not: a destination
//! that lands outside `docs/` resolves to the file on GitHub. Those are
//! the only external URLs on this site, they are marked as external
//! wherever they are drawn, and the colophon says so.

const std = @import("std");
const nok = @import("nokre");
const pages = @import("pages.zig");

const L = @import("l10n.zig").L;
const dom = nok.render.dom;

pub const repo_url = "https://github.com/getnokre/nokre";
pub const branch = "main";

/// The documentation tree this site renders its pages from, on GitHub —
/// the footer's one inline destination (`content.footer`).
///
/// `sourceHref` builds the same shape for a file a document cites, and
/// it stays a function because a path and a `#L20` arrive at runtime.
/// This one is a constant because the footer's sentence names a fixed
/// directory, and a constant is what a `Span.external` wants: no
/// allocation and no lifetime, on a builder the live driver runs once
/// per frame.
///
/// There is no `external_attrs` here any more. `target="_blank"` and
/// `rel="noopener noreferrer"` were this site's own bytes for as long
/// as it wrote raw anchors; the last of those was the footer, and the
/// emitter has written the pair on every `.external` destination since
/// (`Emitter.hrefExternal`). The site now says only *where* a link goes
/// and the library says what that means — which also means the footer's
/// outbound links wear the same external mark every other one on the
/// site wears, having quietly gone without it while they were markup.
pub const docs_dir_url = repo_url ++ "/tree/" ++ branch ++ "/docs";

/// A resolved target as the destination nokre's `Refs` hook answers
/// with: pages and anchors are this site's own hrefs, a source file is
/// an external URL — and the emitter writes the whole attribute either
/// way, external posture included. The one conversion, shared by both
/// resolvers, where each used to write its own bytes.
fn destOf(gpa: std.mem.Allocator, loc: L.Locale, target: Target) !dom.Dest {
    return switch (target) {
        .page => |t| .{ .internal = try pageHref(gpa, loc, t.index, t.frag) },
        .anchor => |a| .{ .internal = try std.fmt.allocPrint(gpa, "#{s}", .{a}) },
        .source => |s| .{ .external = try sourceHref(gpa, s.path, s.dir, s.frag) },
    };
}

/// A reference the edition asked this site to resolve, kept for the
/// link check that runs once every page has been built.
pub const Seen = struct {
    from: usize,
    /// Which copy of the site the reference was written on. A heading
    /// id is derived from the heading's words, so what a `#frag` may
    /// name is a per-locale fact — one anchor set shared across the
    /// axis would check a Persian fragment against English ids and pass.
    locale: L.Locale,
    /// Exactly as the document wrote it, for the error message.
    raw: []const u8,
    target: Target,
};

/// The site's `dom.Refs`: nokre's edition hands over a route reference
/// and this decides what destination it names.
///
/// The edition's own default answers `#note~42`, the fragment the web
/// shell mirrors routes into — right for one page holding a whole app,
/// wrong for a site that publishes one file per screen. So this
/// installs the other answer, and records what it resolved on the way
/// past: a reference this site cannot honor is a build error, not a
/// 404.
pub const Resolver = struct {
    gpa: std.mem.Allocator,
    seen: *std.ArrayList(Seen),

    pub fn refs(self: *Resolver) dom.Refs {
        return .{ .ctx = self, .resolve = resolveHook };
    }

    /// Which page a reference is *from* comes from the app the emitter
    /// is walking, the same way the live resolver below reads it. It
    /// used to be a `page` field the generator set before each screen —
    /// a second statement of what the router already knew, and one that
    /// could be a screen behind without anything failing. One
    /// resolution mechanism, spent by both drivers.
    fn resolveHook(ctx: ?*anyopaque, em: *dom.Emitter, route: []const u8) anyerror!dom.Dest {
        const self: *Resolver = @ptrCast(@alignCast(ctx.?));
        const from = currentPage(em.app) orelse return error.UnknownRoute;
        const p = pages.all[from];
        const loc = localeOf(em.app);
        const target = resolve(self.gpa, route, baseOf(p)) catch |err| {
            std.debug.print("unknown route \"{s}\" on page \"{s}\"\n", .{ route, p.name });
            return err;
        };
        try self.seen.append(self.gpa, .{ .from = from, .locale = loc, .raw = route, .target = target });
        return destOf(self.gpa, loc, target);
    }
};

/// Which locale's copy of the site a reference is being resolved for.
///
/// Read off the app rather than carried beside it, exactly the way
/// `currentPage` reads the route: the generator's loop sets the locale
/// with `App.setLocale` before it builds a screen, and the live driver
/// is handed the page's own locale by `mount` — so both drivers have
/// one answer and neither states it twice. A generator field would be
/// the second statement that can be an iteration behind, which is the
/// defect the `page` field already was.
fn localeOf(app: *const nok.App) L.Locale {
    return L.of(app).locale;
}

/// The same resolution, for the same site, running in a browser.
///
/// The live driver re-renders the screen the file already holds, so it
/// has to write the *file's* hrefs: without this the edition falls back
/// to its own default and every link on the page turns into `#routing`
/// the moment the module boots — a URL this site publishes nothing at.
/// One mapping, stated once, spent by both drivers (`nokreWebRefs` in
/// live.zig).
///
/// What it does not do is record or fail. Which references exist was
/// settled at build time, over these same rules, and a reference that
/// named nothing failed the build then; there is nobody to tell here,
/// and a page that got past that check has none.
pub const Live = struct {
    /// Reset per reference. A frame writes a few hundred of these and
    /// the browser holds the module for as long as the tab lives, so a
    /// href that outlived its own attribute would be a leak with a
    /// scroll bar.
    arena: std.heap.ArenaAllocator,

    pub fn refs(self: *Live) dom.Refs {
        return .{ .ctx = self, .resolve = resolveHook };
    }

    fn resolveHook(ctx: ?*anyopaque, em: *dom.Emitter, route: []const u8) anyerror!dom.Dest {
        const self: *Live = @ptrCast(@alignCast(ctx.?));
        _ = self.arena.reset(.retain_capacity);
        const gpa = self.arena.allocator();

        const from = currentPage(em.app) orelse return dom.Refs.fragment(null, em, route);
        const target = resolve(gpa, route, baseOf(pages.all[from])) catch {
            return dom.Refs.fragment(null, em, route);
        };
        return destOf(gpa, localeOf(em.app), target);
    }
};

/// The page the app is on: `Router.current()` is exactly the name
/// without its arguments, so nothing here splits a reference by hand.
/// No screen on this site takes an argument — every page is a flat name
/// (pages.zig) — but reading a reference *as* a name would be a bug
/// waiting for the first one that does, and the router has already
/// answered the question.
fn currentPage(app: *const nok.App) ?usize {
    return pages.indexOf(app.router.current() orelse return null);
}

/// The directory a page's Markdown lives in, for relative destinations.
/// A screen this site builds by hand writes route names, which resolve
/// before any of this is consulted.
pub fn baseOf(p: pages.Page) []const u8 {
    if (p.md.len == 0) return "docs";
    return if (std.mem.indexOfScalar(u8, p.md, '/') != null) "docs/internals" else "docs";
}

pub const Target = union(enum) {
    /// A screen this site has. `frag` is the heading anchor, "" for none.
    page: struct { index: usize, frag: []const u8 },
    /// A heading on the current screen.
    anchor: []const u8,
    /// A file in the nokre repository. `path` is repo-relative, so the
    /// build can check it exists before writing a link to it. `frag` is
    /// the anchor as on `page` — a line reference like `#L20` means
    /// nothing to the existence check but everything to the reader.
    source: struct { path: []const u8, dir: bool, frag: []const u8 },
};

pub const Error = error{ UnknownRoute, OutOfMemory };

/// `dest` as written in the document; `base` is the directory the
/// document itself lives in, repo-relative (`docs`, `docs/internals`).
pub fn resolve(gpa: std.mem.Allocator, dest: []const u8, base: []const u8) Error!Target {
    if (dest.len == 0) return error.UnknownRoute;

    // A bare fragment is this screen's own heading.
    if (dest[0] == '#') return .{ .anchor = dest[1..] };

    const hash = std.mem.indexOfScalar(u8, dest, '#');
    const path = if (hash) |h| dest[0..h] else dest;
    const frag = if (hash) |h| dest[h + 1 ..] else "";

    // A name this site has is a name this site has. Checked first so a
    // page can link to `elements` without pretending to be a file.
    if (pages.indexOf(path)) |i| return .{ .page = .{ .index = i, .frag = frag } };

    const joined = try normalize(gpa, base, path);
    if (routeFor(joined)) |i| return .{ .page = .{ .index = i, .frag = frag } };
    // A document under `docs/` that this site does not publish is a
    // mistake — every one of them is a page here. Markdown living
    // anywhere else in the repository is a file like any other, and a
    // link to it goes where the file is.
    if (std.mem.startsWith(u8, joined, "docs/") and std.mem.endsWith(u8, joined, ".md")) {
        return error.UnknownRoute;
    }
    return .{ .source = .{
        .path = std.mem.trimEnd(u8, joined, "/"),
        .dir = joined.len != 0 and joined[joined.len - 1] == '/',
        .frag = frag,
    } };
}

/// The route a `docs/`-relative Markdown file is published as. The two
/// READMEs are the track indexes; everything else keeps its stem, with
/// the internals track carrying a `internals.` prefix that is part of
/// the name and not a level (see pages.zig).
fn routeFor(repo_path: []const u8) ?usize {
    // The repository's own README is the argument this site opens with,
    // support matrix included, so a doc citing it lands on the front
    // page rather than leaving for GitHub.
    if (std.mem.eql(u8, repo_path, "README.md")) return pages.indexOf("home");

    const rest = strip(repo_path, "docs/") orelse return null;
    if (!std.mem.endsWith(u8, rest, ".md")) return null;
    const stem = rest[0 .. rest.len - ".md".len];

    if (std.mem.eql(u8, stem, "README")) return pages.indexOf("docs");
    if (std.mem.eql(u8, stem, "internals/README")) return pages.indexOf("internals");

    if (strip(stem, "internals/")) |leaf| {
        var buf: [64]u8 = undefined;
        if (leaf.len + "internals.".len > buf.len) return null;
        const name = std.fmt.bufPrint(&buf, "internals.{s}", .{leaf}) catch return null;
        return pages.indexOf(name);
    }
    return pages.indexOf(stem);
}

fn strip(s: []const u8, prefix: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, s, prefix)) s[prefix.len..] else null;
}

/// `base` + `rel`, with `.` and `..` folded out. Repo-relative, no
/// leading slash, trailing slash preserved (it is what says "directory").
fn normalize(gpa: std.mem.Allocator, base: []const u8, rel: []const u8) error{OutOfMemory}![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(gpa);

    if (rel.len != 0 and rel[0] != '/') {
        var it = std.mem.tokenizeScalar(u8, base, '/');
        while (it.next()) |p| try parts.append(gpa, p);
    }
    var it = std.mem.tokenizeScalar(u8, rel, '/');
    while (it.next()) |p| {
        if (std.mem.eql(u8, p, ".")) continue;
        if (std.mem.eql(u8, p, "..")) {
            if (parts.items.len != 0) _ = parts.pop();
            continue;
        }
        try parts.append(gpa, p);
    }

    var out: std.ArrayList(u8) = .empty;
    for (parts.items, 0..) |p, i| {
        if (i != 0) try out.append(gpa, '/');
        try out.appendSlice(gpa, p);
    }
    if (rel.len != 0 and rel[rel.len - 1] == '/') try out.append(gpa, '/');
    return out.toOwnedSlice(gpa);
}

/// The absolute path one locale's copy of a page is served at:
/// `/{tag}/`, or `/{tag}/{route}/`.
///
/// **The prefix is this file's and nokre computes none of it.** The
/// library takes paths and joins them to an origin; which segments a
/// site puts in front of a route is the driver's whole (`dom.Alternates`
/// says so in as many words, and the per-locale generation loop that
/// would have made a prefix scheme the library's business was refused
/// rather than written — docs/internals/dom-edition.md, "The locale
/// axis"). The segment is `L.tag(loc)` rather than a string typed here,
/// so the directory a page lands in, the `hreflang` on the link to it
/// and the `lang` on the page itself are one fact out of the catalog.
///
/// Every locale gets a prefix, the default one included, and the
/// unprefixed path is `stubHref` — a real page in every language, and
/// one address that is about the reader. `/en/x` is never redirected.
pub fn pageHref(gpa: std.mem.Allocator, loc: L.Locale, index: usize, frag: []const u8) ![]const u8 {
    const p = pages.all[index];
    const tag = L.tag(loc);
    const base = if (std.mem.eql(u8, p.name, "home"))
        try std.fmt.allocPrint(gpa, "/{s}/", .{tag})
    else
        try std.fmt.allocPrint(gpa, "/{s}/{s}/", .{ tag, p.name });
    if (frag.len == 0) return base;
    defer gpa.free(base);
    return std.fmt.allocPrint(gpa, "{s}#{s}", .{ base, frag });
}

/// The unprefixed path — where this page's chooser stub stands, and
/// where every link written before the locale axis existed still points.
///
/// It is the path `pageHref` used to answer with, unchanged, which is
/// what makes the move free for a reader: `/accessibility/` still
/// resolves, and what it now holds is a page that sends them to the
/// copy in their own language (`dom.localeStub`). It is also what
/// `x-default` names, because that is what a chooser is.
pub fn stubHref(gpa: std.mem.Allocator, index: usize) ![]const u8 {
    const p = pages.all[index];
    if (std.mem.eql(u8, p.name, "home")) return gpa.dupe(u8, "/");
    return std.fmt.allocPrint(gpa, "/{s}/", .{p.name});
}

test "a page's path is its stub's path with a locale in front of it" {
    // The property that made the URL move free, stated where it can
    // fail: every address this site published before the axis is still
    // an address, and the copy it chooses between is the same path with
    // one segment prepended. A scheme that drifted — a localized slug, a
    // stub at a different route — would break here rather than in a
    // reader's bookmark.
    var arena = testArena();
    defer arena.deinit();
    const gpa = arena.allocator();
    inline for (@import("l10n.zig").locales) |loc| {
        for (pages.all, 0..) |p, i| {
            if (p.kind == .not_found) continue;
            const stub = try stubHref(gpa, i);
            const page = try pageHref(gpa, loc, i, "");
            const want = try std.fmt.allocPrint(gpa, "/{s}{s}", .{ L.tag(loc), stub });
            try std.testing.expectEqualStrings(want, page);
            // …and the stub is what a pre-axis link named: the root for
            // home, `/<route>/` for everything else.
            const before = if (std.mem.eql(u8, p.name, "home"))
                try gpa.dupe(u8, "/")
            else
                try std.fmt.allocPrint(gpa, "/{s}/", .{p.name});
            try std.testing.expectEqualStrings(before, stub);
        }
    }
}

test "a fragment rides on the locale's copy, not on the chooser" {
    var arena = testArena();
    defer arena.deinit();
    const i = pages.indexOf("testing").?;
    const href = try pageHref(arena.allocator(), L.default_locale, i, "the-input-driver");
    try std.testing.expectEqualStrings("/en/testing/#the-input-driver", href);
}

pub fn sourceHref(gpa: std.mem.Allocator, path: []const u8, dir: bool, frag: []const u8) ![]const u8 {
    const base = try std.fmt.allocPrint(gpa, repo_url ++ "/{s}/" ++ branch ++ "/{s}", .{
        if (dir) "tree" else "blob",
        path,
    });
    if (frag.len == 0) return base;
    defer gpa.free(base);
    return std.fmt.allocPrint(gpa, "{s}#{s}", .{ base, frag });
}

test {
    // Only the wasm build references `Live`, and analysis is lazy —
    // without this line `zig build test` would compile every resolver
    // path except the browser's.
    _ = &Live.resolveHook;
}

// The generator runs on one arena for the whole process — resolution
// hands back slices of intermediate joins, and an arena is what makes
// that a non-question. The tests say it the same way.
fn testArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.testing.allocator);
}

test "doc-relative destinations resolve to flat routes" {
    var arena = testArena();
    defer arena.deinit();
    const gpa = arena.allocator();
    const cases = .{
        .{ "elements.md", "docs", "elements" },
        .{ "internals/pixel-model.md", "docs", "internals.pixel-model" },
        .{ "../introduction.md", "docs/internals", "introduction" },
        .{ "README.md", "docs/internals", "internals" },
        .{ "../README.md", "docs/internals", "docs" },
        .{ "internals/secure_store.md", "docs", "internals.secure_store" },
    };
    inline for (cases) |c| {
        const t = try resolve(gpa, c[0], c[1]);
        try std.testing.expectEqualStrings(c[2], pages.all[t.page.index].name);
        try std.testing.expectEqualStrings("", t.page.frag);
    }
}

test "fragments survive resolution" {
    var arena = testArena();
    defer arena.deinit();
    const t = try resolve(arena.allocator(), "testing.md#where-the-harness-stops", "docs");
    try std.testing.expectEqualStrings("testing", pages.all[t.page.index].name);
    try std.testing.expectEqualStrings("where-the-harness-stops", t.page.frag);
}

test "destinations outside docs are source files" {
    var arena = testArena();
    defer arena.deinit();
    const gpa = arena.allocator();

    const t = try resolve(gpa, "../src/core/color.zig", "docs");
    try std.testing.expectEqualStrings("src/core/color.zig", t.source.path);
    try std.testing.expect(!t.source.dir);
    try std.testing.expectEqualStrings("", t.source.frag);

    // A line reference rides along to the file host, the way a heading
    // fragment rides to a page.
    const l = try resolve(gpa, "../src/core/color.zig#L20", "docs");
    try std.testing.expectEqualStrings("src/core/color.zig", l.source.path);
    try std.testing.expectEqualStrings("L20", l.source.frag);

    const d = try resolve(gpa, "../../deps/qrcodegen/", "docs/internals");
    try std.testing.expectEqualStrings("deps/qrcodegen", d.source.path);
    try std.testing.expect(d.source.dir);
}

const LinkDest = struct { route: []const u8 };

fn buildLink(ctx: ?*anyopaque, app: *nok.App) anyerror!void {
    const dest: *const LinkDest = @ptrCast(@alignCast(ctx.?));
    try nok.cursor.root(app).link(.{ .label = "See", .route = dest.route });
}

const resolver_routes = [_]nok.RouteDef{
    .{ .name = "routing", .title = .{ .fixed = "Routing" }, .build = buildLink },
    .{ .name = "internals.dom-edition", .title = .{ .fixed = "DOM edition" }, .build = buildLink },
};

test "the resolver reads which page a reference is from off the app" {
    // It used to be a `page` field the generator set before each
    // screen — a second statement of what the router already knew, and
    // one nothing would notice being a screen behind. What proves the
    // difference is `baseOf`: the *same* bare destination resolves to
    // two different pages depending on which document it is written in,
    // so a stale `from` is a wrong answer rather than a slower one.
    const gpa = std.testing.allocator;
    var arena = testArena();
    defer arena.deinit();
    var seen: std.ArrayList(Seen) = .empty;
    defer seen.deinit(arena.allocator());
    var resolver: Resolver = .{ .gpa = arena.allocator(), .seen = &seen };

    var dest: LinkDest = .{ .route = "../elements.md" };
    var app = try nok.App.init(gpa, .{
        .viewport = .{ .w = 900, .h = 600 },
        .routes = &resolver_routes,
        .ctx = &dest,
        .services = .mocks(),
    });
    defer app.deinit();

    for ([_][]const u8{ "routing", "internals.dom-edition" }) |page| {
        try app.switchTo(page);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        var em: dom.Emitter = .{
            .gpa = gpa,
            .app = &app,
            .out = &out,
            .options = .{ .refs = resolver.refs() },
        };
        defer em.deinit();
        try dom.content(&em);
    }

    try std.testing.expectEqual(@as(usize, 2), seen.items.len);
    // From `routing` (which lives in docs/), `../elements.md` leaves the
    // documentation tree entirely and is a repository file…
    try std.testing.expectEqual(pages.indexOf("routing").?, seen.items[0].from);
    try std.testing.expectEqualStrings("elements.md", seen.items[0].target.source.path);
    // …and from `internals.dom-edition` (docs/internals/) the same eleven
    // bytes are `docs/elements.md`, a page this site publishes. Nothing
    // but `from` changed between the two.
    try std.testing.expectEqual(pages.indexOf("internals.dom-edition").?, seen.items[1].from);
    try std.testing.expectEqualStrings(
        "elements",
        pages.all[seen.items[1].target.page.index].name,
    );
}

test "a doc this site does not publish fails the build" {
    var arena = testArena();
    defer arena.deinit();
    try std.testing.expectError(error.UnknownRoute, resolve(arena.allocator(), "nope.md", "docs"));
}

test "Markdown outside docs/ is a file, not a missing page" {
    var arena = testArena();
    defer arena.deinit();
    const t = try resolve(arena.allocator(), "../../shim/freestanding/README.md", "docs/internals");
    try std.testing.expectEqualStrings("shim/freestanding/README.md", t.source.path);
}
