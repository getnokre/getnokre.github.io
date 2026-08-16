const std = @import("std");
const nok = @import("nokre");
const pages = @import("pages.zig");

const L = @import("l10n.zig").L;
const dom = nok.render.dom;

pub const repo_url = "https://github.com/getnokre/nokre";
pub const branch = "main";

pub const docs_dir_url = repo_url ++ "/tree/" ++ branch ++ "/docs";

fn destOf(gpa: std.mem.Allocator, loc: L.Locale, target: Target) !dom.Dest {
    return switch (target) {
        .page => |t| .{ .internal = try pageHref(gpa, loc, t.index, t.frag) },
        .anchor => |a| .{ .internal = try std.fmt.allocPrint(gpa, "#{s}", .{a}) },
        .source => |s| .{ .external = try sourceHref(gpa, s.path, s.dir, s.frag) },
    };
}

pub const Seen = struct {
    from: usize,
    locale: L.Locale,
    raw: []const u8,
    target: Target,
};

pub const Resolver = struct {
    gpa: std.mem.Allocator,
    seen: *std.ArrayList(Seen),

    pub fn refs(self: *Resolver) dom.Refs {
        return .{ .ctx = self, .resolve = resolveHook };
    }

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

fn localeOf(app: *const nok.App) L.Locale {
    return L.of(app).locale;
}

pub const Live = struct {
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

fn currentPage(app: *const nok.App) ?usize {
    return pages.indexOf(app.router.current() orelse return null);
}

pub fn baseOf(p: pages.Page) []const u8 {
    if (p.md.len == 0) return "docs";
    return if (std.mem.indexOfScalar(u8, p.md, '/') != null) "docs/internals" else "docs";
}

pub const Target = union(enum) {
    page: struct { index: usize, frag: []const u8 },
    anchor: []const u8,
    source: struct { path: []const u8, dir: bool, frag: []const u8 },
};

pub const Error = error{ UnknownRoute, OutOfMemory };

pub fn resolve(gpa: std.mem.Allocator, dest: []const u8, base: []const u8) Error!Target {
    if (dest.len == 0) return error.UnknownRoute;

    if (dest[0] == '#') return .{ .anchor = dest[1..] };

    const hash = std.mem.indexOfScalar(u8, dest, '#');
    const path = if (hash) |h| dest[0..h] else dest;
    const frag = if (hash) |h| dest[h + 1 ..] else "";

    if (pages.indexOf(path)) |i| return .{ .page = .{ .index = i, .frag = frag } };

    const joined = try normalize(gpa, base, path);
    if (routeFor(joined)) |i| return .{ .page = .{ .index = i, .frag = frag } };
    if (std.mem.startsWith(u8, joined, "docs/") and std.mem.endsWith(u8, joined, ".md")) {
        return error.UnknownRoute;
    }
    return .{ .source = .{
        .path = std.mem.trimEnd(u8, joined, "/"),
        .dir = joined.len != 0 and joined[joined.len - 1] == '/',
        .frag = frag,
    } };
}

fn routeFor(repo_path: []const u8) ?usize {
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

pub fn stubHref(gpa: std.mem.Allocator, index: usize) ![]const u8 {
    const p = pages.all[index];
    if (std.mem.eql(u8, p.name, "home")) return gpa.dupe(u8, "/");
    return std.fmt.allocPrint(gpa, "/{s}/", .{p.name});
}

test "a page's path is its stub's path with a locale in front of it" {
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
    _ = &Live.resolveHook;
}

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
    try std.testing.expectEqual(pages.indexOf("routing").?, seen.items[0].from);
    try std.testing.expectEqualStrings("elements.md", seen.items[0].target.source.path);
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
