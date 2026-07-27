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

const dom = nok.render.dom;

pub const repo_url = "https://github.com/getnokre/nokre";
pub const branch = "main";

/// A reference the edition asked this site to resolve, kept for the
/// link check that runs once every page has been built.
pub const Seen = struct {
    from: usize,
    /// Exactly as the document wrote it, for the error message.
    raw: []const u8,
    target: Target,
};

/// The site's `dom.Refs`: nokre's edition hands over a route reference
/// and this decides what `href` it becomes.
///
/// The edition's own default writes `#note~42`, the fragment the web
/// shell mirrors routes into — right for one page holding a whole app,
/// wrong for a site that publishes one file per screen. So this
/// installs the other answer, and records what it resolved on the way
/// past: a reference this site cannot honor is a build error, not a
/// 404.
pub const Resolver = struct {
    gpa: std.mem.Allocator,
    seen: *std.ArrayList(Seen),
    /// The page being written. Set before each screen.
    page: usize = 0,

    pub fn refs(self: *Resolver) dom.Refs {
        return .{ .ctx = self, .write = writeHref };
    }

    fn writeHref(ctx: ?*anyopaque, em: *dom.Emitter, route: []const u8) anyerror!void {
        const self: *Resolver = @ptrCast(@alignCast(ctx.?));
        const p = pages.all[self.page];
        const target = resolve(self.gpa, route, baseOf(p)) catch |err| {
            std.debug.print("unknown route \"{s}\" on page \"{s}\"\n", .{ route, p.name });
            return err;
        };
        try self.seen.append(self.gpa, .{ .from = self.page, .raw = route, .target = target });
        switch (target) {
            .page => |t| try em.raw(try pageHref(self.gpa, t.index, t.frag)),
            .anchor => |a| {
                try em.raw("#");
                try em.text(a);
            },
            .source => |s| try em.raw(try sourceHref(self.gpa, s.path, s.dir)),
        }
    }
};

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
        return .{ .ctx = self, .write = writeHref };
    }

    fn writeHref(ctx: ?*anyopaque, em: *dom.Emitter, route: []const u8) anyerror!void {
        const self: *Live = @ptrCast(@alignCast(ctx.?));
        _ = self.arena.reset(.retain_capacity);
        const gpa = self.arena.allocator();

        const from = pages.indexOf(currentName(em.app)) orelse return dom.Refs.fragment(null, em, route);
        const target = resolve(gpa, route, baseOf(pages.all[from])) catch {
            return dom.Refs.fragment(null, em, route);
        };
        switch (target) {
            .page => |t| try em.raw(try pageHref(gpa, t.index, t.frag)),
            .anchor => |a| {
                try em.raw("#");
                try em.text(a);
            },
            .source => |s| try em.raw(try sourceHref(gpa, s.path, s.dir)),
        }
    }
};

/// The route the app is on, without its arguments. No screen here takes
/// any — every page is a flat name (pages.zig) — but a reference is a
/// reference, and reading one as a name would be a bug waiting for the
/// first screen that does.
fn currentName(app: *const nok.App) []const u8 {
    const ref = app.router.currentRef() orelse return "";
    const cut = std.mem.indexOfScalar(u8, ref, nok.router.arg_separator) orelse ref.len;
    return ref[0..cut];
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
    /// build can check it exists before writing a link to it.
    source: struct { path: []const u8, dir: bool },
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

/// The absolute path a page is served at: one flat segment, or the root.
pub fn pageHref(gpa: std.mem.Allocator, index: usize, frag: []const u8) ![]const u8 {
    const p = pages.all[index];
    const base = if (std.mem.eql(u8, p.name, "home"))
        try gpa.dupe(u8, "/")
    else
        try std.fmt.allocPrint(gpa, "/{s}/", .{p.name});
    if (frag.len == 0) return base;
    defer gpa.free(base);
    return std.fmt.allocPrint(gpa, "{s}#{s}", .{ base, frag });
}

pub fn sourceHref(gpa: std.mem.Allocator, path: []const u8, dir: bool) ![]const u8 {
    return std.fmt.allocPrint(gpa, repo_url ++ "/{s}/" ++ branch ++ "/{s}", .{
        if (dir) "tree" else "blob",
        path,
    });
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

    const d = try resolve(gpa, "../../deps/qrcodegen/", "docs/internals");
    try std.testing.expectEqualStrings("deps/qrcodegen", d.source.path);
    try std.testing.expect(d.source.dir);
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
