//! Generates getnokre.github.io.
//!
//! One nokre app, every screen of it, written out by nokre's DOM
//! edition ([render/dom](https://github.com/getnokre/nokre/tree/main/src/render/dom)).
//! Everything below is the *driver*: which screens exist, what a
//! reference resolves to, and the document a browser needs around a
//! screen. The markup and the stylesheet are the library's.
//!
//! The order of events is the point: build the tree, audit the tree,
//! resolve every reference against the route table, and only then write
//! a file. A page that would have been wrong is a build that fails.
//!
//! It runs that whole pass **once per locale in the catalog**
//! (l10n.zig), and publishes every page at `/{tag}/…` — the default
//! locale included, with no bare-default copy anywhere. What stands at
//! each unprefixed path instead is nokre's chooser (`dom.localeStub`),
//! so every URL this site published before the axis existed still
//! resolves and lands on the copy in the reader's own language. A
//! prefixed URL is never redirected: one address showing different
//! content to different readers is what breaks sharing and
//! canonicalisation both.
//!
//! The prefix is this driver's, entirely. nokre computes no path here —
//! it takes the ones `links.zig` answers with, joins them to the origin
//! and checks the join.

const std = @import("std");
const nok = @import("nokre");
const opts = @import("site_options");
const web_assets = @import("web_assets");

const content = @import("content.zig");
const icons = @import("icons.zig");
const css_check = @import("css.zig");
const l10n = @import("l10n.zig");
const links = @import("links.zig");
const pages = @import("pages.zig");

const audit = nok.testing.audit;
const dom = nok.render.dom;
const L = l10n.L;

/// This page's alternate set: one URL per locale, plus the `x-default`
/// that names the chooser. One value per route, built once before
/// anything is written and handed to both writers that spend it — the
/// head's `hreflang` block and the sitemap's `<xhtml:link>`s — which is
/// what makes them the same set rather than two derivations that agree
/// today (`dom.Alternates`).
const AlternateSet = dom.Alternates(L).Set;

comptime {
    _ = @import("shell.zig");
}

const nokre_revision = 84;
comptime {
    if (nok.revision != nokre_revision) @compileError(std.fmt.comptimePrint(
        "written against nokre revision {d}, the checkout is at {d} — survey the generator before bumping",
        .{ nokre_revision, nok.revision },
    ));
}

const origin = "https://getnokre.github.io";

const viewport: nok.Size = .{ .w = 1280, .h = 1024 };

const driver_sources = dom.driver_sources;

const font_files = [_][]const u8{
    "prose.woff2",        "prose-bold.woff2",
    "prose-italic.woff2", "prose-bolditalic.woff2",
    "mono.woff2",         "mono-bold.woff2",
    "mono-italic.woff2",  "mono-bolditalic.woff2",
    "arabic.woff2",       "arabic-bold.woff2",
    "icons.woff2",
    // The vendor sign-in marks: no page here draws one, but the
    // stylesheet nokre emits declares the face, and a declared face is
    // served (five glyphs, ~1 KB).
           "brand.woff2",
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;
    const cwd: std.Io.Dir = .cwd();

    var sources = try gpa.alloc([]const u8, pages.all.len);
    for (pages.all, 0..) |p, i| {
        if (p.md.len == 0) {
            sources[i] = "";
            continue;
        }
        const path = try std.fs.path.join(gpa, &.{ opts.docs_dir, p.md });
        sources[i] = cwd.readFileAlloc(io, path, gpa, .limited(4 << 20)) catch |err| {
            std.debug.print("cannot read {s}: {t}\n", .{ path, err });
            return err;
        };
    }
    var site: content.Site = .{ .gpa = gpa, .sources = sources };

    var app = try nok.App.init(gpa, .{
        .viewport = viewport,
        .routes = &content.routes,
        .ctx = &site,
    });
    defer app.deinit();

    var destinations: [pages.destinations.len]nok.Destination = undefined;
    for (pages.destinations, 0..) |name, i| {
        destinations[i] = .{ .route = name, .icon = pages.find(name).?.icon };
    }
    try app.setNav(&destinations);

    var alternates = try gpa.alloc([]const dom.Alternate, pages.all.len);
    for (pages.all, 0..) |p, i| {
        if (p.kind == .not_found) {
            alternates[i] = &.{};
            continue;
        }
        var spec: dom.Alternates(L) = .{ .stub = try links.stubHref(gpa, i), .paths = undefined };
        inline for (l10n.locales) |loc| {
            @field(spec.paths, @tagName(loc)) = try links.pageHref(gpa, loc, i, "");
        }
        const set = try gpa.create(AlternateSet);
        set.* = spec.set();
        alternates[i] = set;
    }

    var seen: std.ArrayList(links.Seen) = .empty;
    var resolver: links.Resolver = .{ .gpa = gpa, .seen = &seen };

    var documents: [l10n.locales.len][][]const u8 = undefined;
    var anchors: [l10n.locales.len][][]const []const u8 = undefined;
    for (&documents) |*d| d.* = try gpa.alloc([]const u8, pages.all.len);
    for (&anchors) |*a| a.* = try gpa.alloc([]const []const u8, pages.all.len);

    for (l10n.locales, 0..) |loc, li| {
        try app.setLocale(L.tag(loc));
        app.setChrome(L.chrome(loc));
        app.setDirection(L.dir(loc));

        for (pages.all, 0..) |p, i| {
            try app.router.switchTo(&app, p.name);
            {
                var violations: std.ArrayList(audit.Violation) = .empty;
                defer violations.deinit(gpa);
                try audit.collect(&app, &violations, .{ .skip = &.{.unresolvable_route} });
                if (violations.items.len != 0) {
                    for (violations.items) |v| {
                        std.debug.print("a11y audit: {s} (node label: \"{s}\")\n", .{
                            @tagName(v.rule),
                            app.tree.getConst(v.id).?.label(),
                        });
                    }
                    std.debug.print("accessibility audit failed on \"{s}\" in {s}\n", .{ p.name, L.tag(loc) });
                    return error.A11yAuditFailed;
                }
            }

            var out: std.ArrayList(u8) = .empty;
            var em: dom.Emitter = .{
                .gpa = gpa,
                .app = &app,
                .out = &out,
                .options = .{ .refs = resolver.refs(), .node_ids = true },
            };
            try writeDocument(&em, loc, i, alternates[i]);
            documents[li][i] = out.items;
            anchors[li][i] = try em.takeAnchors(gpa);
            em.deinit();
        }
    }

    var stubs = try gpa.alloc([]const u8, pages.all.len);
    for (pages.all, 0..) |p, i| {
        if (p.kind == .not_found) {
            stubs[i] = "";
            continue;
        }
        var out: std.ArrayList(u8) = .empty;
        var em: dom.Emitter = .{ .gpa = gpa, .app = &app, .out = &out };
        defer em.deinit();
        try writeStub(&em, i);
        stubs[i] = out.items;
    }

    var broken: usize = 0;
    for (seen.items) |ref| {
        const page_anchors = anchors[@intFromEnum(ref.locale)];
        switch (ref.target) {
            .page => |t| {
                if (t.frag.len != 0 and !has(page_anchors[t.index], t.frag)) {
                    std.debug.print("{s} ({s}): \"{s}\" names no heading on \"{s}\"\n", .{
                        pages.all[ref.from].name, L.tag(ref.locale), ref.raw, pages.all[t.index].name,
                    });
                    broken += 1;
                }
            },
            .anchor => |a| {
                if (!has(page_anchors[ref.from], a)) {
                    std.debug.print("{s} ({s}): \"#{s}\" names no heading on this page\n", .{
                        pages.all[ref.from].name, L.tag(ref.locale), a,
                    });
                    broken += 1;
                }
            },
            .source => |s| {
                const path = try std.fs.path.join(gpa, &.{ opts.repo_dir, s.path });
                cwd.access(io, path, .{}) catch {
                    std.debug.print("{s}: \"{s}\" is not a file in the repository\n", .{
                        pages.all[ref.from].name, ref.raw,
                    });
                    broken += 1;
                };
            },
        }
    }
    if (broken != 0) {
        std.debug.print("{d} reference(s) name nothing\n", .{broken});
        return error.BrokenReferences;
    }

    const css = try stylesheet(gpa);
    try checkStylesheet(gpa, css);

    var markup = try gpa.alloc([]const u8, l10n.locales.len * pages.all.len + pages.all.len);
    var n_markup: usize = 0;
    for (documents) |per_locale| for (per_locale) |d| {
        markup[n_markup] = d;
        n_markup += 1;
    };
    for (stubs) |s| {
        if (s.len == 0) continue;
        markup[n_markup] = s;
        n_markup += 1;
    }
    markup = markup[0..n_markup];

    const subset = try icons.parse(gpa, icons.py);
    const emitted = try icons.collectEmitted(gpa, markup, css);
    var uncovered: usize = 0;
    for (emitted) |cp| {
        if (icons.covered(subset, cp)) continue;
        std.debug.print("icon U+{X:0>4} ({s}) is not in tools/build-fonts.py's ICONS\n", .{ cp, icons.nameOf(cp) });
        uncovered += 1;
    }
    if (uncovered != 0) {
        std.debug.print("{d} icon(s) would render as tofu: add them to ICONS and re-run the subset\n", .{uncovered});
        return error.IconNotInFontSubset;
    }

    const out_dir = opts.out_dir;
    try cwd.createDirPath(io, out_dir);

    for (l10n.locales, 0..) |loc, li| {
        for (pages.all, 0..) |p, i| {
            const path = try outPath(gpa, out_dir, loc, p) orelse continue;
            if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);
            try cwd.writeFile(io, .{ .sub_path = path, .data = documents[li][i] });
        }
    }

    for (pages.all, 0..) |p, i| {
        if (stubs[i].len == 0) continue;
        const path = try stubPath(gpa, out_dir, p);
        if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);
        try cwd.writeFile(io, .{ .sub_path = path, .data = stubs[i] });
    }

    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "style.css" }),
        .data = css,
    });

    try cwd.createDirPath(io, try std.fs.path.join(gpa, &.{ out_dir, "assets/fonts" }));
    for (font_files) |f| {
        const src = try std.fs.path.join(gpa, &.{ "assets/fonts", f });
        const bytes = try cwd.readFileAlloc(io, src, gpa, .limited(4 << 20));
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "assets/fonts", f }),
            .data = bytes,
        });
    }

    var script_bytes: usize = 0;
    for (driver_sources) |src| {
        script_bytes += src.bytes.len;
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, src.name }),
            .data = src.bytes,
        });
    }

    try cwd.createDirPath(io, try std.fs.path.join(gpa, &.{ out_dir, "md" }));
    for (pages.all, 0..) |p, i| {
        if (p.md.len == 0) continue;
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "md", try std.fmt.allocPrint(gpa, "{s}.md", .{p.name}) }),
            .data = sources[i],
        });
    }

    try writeExtras(gpa, io, cwd, out_dir, alternates);
    try failOnStale(gpa, io, cwd, out_dir);

    std.debug.print("{d} locale(s), {d} screens each, {d} stubs, {d} references, {d} bytes of markup, {d} bytes of driver\n", .{
        l10n.locales.len,
        pages.all.len,
        n_markup - l10n.locales.len * pages.all.len,
        seen.items.len,
        total(markup),
        script_bytes,
    });
}

fn total(documents: []const []const u8) usize {
    var n: usize = 0;
    for (documents) |d| n += d.len;
    return n;
}

fn has(list: []const []const u8, needle: []const u8) bool {
    for (list) |s| {
        if (std.mem.eql(u8, s, needle)) return true;
    }
    return false;
}

fn failOnStale(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, out_dir: []const u8) !void {
    var stale: usize = 0;

    var root = try cwd.openDir(io, out_dir, .{ .iterate = true });
    defer root.close(io);
    var it = root.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (isPublishedLocale(entry.name)) {
            stale += try staleInLocale(gpa, io, cwd, out_dir, entry.name);
            continue;
        }
        const index = try std.fs.path.join(gpa, &.{ out_dir, entry.name, "index.html" });
        cwd.access(io, index, .{}) catch continue;
        if (writesPageDir(entry.name)) continue;
        std.debug.print("stale page: {s} — no route writes it\n", .{index});
        stale += 1;
    }

    const md_dir_path = try std.fs.path.join(gpa, &.{ out_dir, "md" });
    var md_dir = try cwd.openDir(io, md_dir_path, .{ .iterate = true });
    defer md_dir.close(io);
    var md_it = md_dir.iterate();
    while (try md_it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        const stem = entry.name[0 .. entry.name.len - ".md".len];
        if (pages.find(stem)) |p| {
            if (p.md.len != 0) continue;
        }
        std.debug.print("stale source: {s}/{s} — no route writes it\n", .{ md_dir_path, entry.name });
        stale += 1;
    }

    if (stale != 0) {
        std.debug.print("{d} stale file(s) left published by a rename or removal\n", .{stale});
        return error.StaleOutput;
    }
}

fn staleInLocale(
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    out_dir: []const u8,
    tag: []const u8,
) !usize {
    var stale: usize = 0;
    const dir_path = try std.fs.path.join(gpa, &.{ out_dir, tag });
    var dir = try cwd.openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const index = try std.fs.path.join(gpa, &.{ dir_path, entry.name, "index.html" });
        cwd.access(io, index, .{}) catch continue;
        if (writesPageDir(entry.name)) continue;
        std.debug.print("stale page: {s} — no route writes it\n", .{index});
        stale += 1;
    }
    return stale;
}

fn isPublishedLocale(name: []const u8) bool {
    for (l10n.locales) |loc| {
        if (std.mem.eql(u8, L.tag(loc), name)) return true;
    }
    return false;
}

fn writesPageDir(name: []const u8) bool {
    const p = pages.find(name) orelse return false;
    return !std.mem.eql(u8, p.name, "home") and p.kind != .not_found;
}

fn outPath(gpa: std.mem.Allocator, out_dir: []const u8, loc: L.Locale, p: pages.Page) !?[]const u8 {
    const tag = L.tag(loc);
    if (p.kind == .not_found) {
        if (loc != L.default_locale) return null;
        return try std.fs.path.join(gpa, &.{ out_dir, "404.html" });
    }
    if (std.mem.eql(u8, p.name, "home")) {
        return try std.fmt.allocPrint(gpa, "{s}/{s}/index.html", .{ out_dir, tag });
    }
    return try std.fmt.allocPrint(gpa, "{s}/{s}/{s}/index.html", .{ out_dir, tag, p.name });
}

fn stubPath(gpa: std.mem.Allocator, out_dir: []const u8, p: pages.Page) ![]const u8 {
    if (std.mem.eql(u8, p.name, "home")) {
        return std.fs.path.join(gpa, &.{ out_dir, "index.html" });
    }
    return std.fmt.allocPrint(gpa, "{s}/{s}/index.html", .{ out_dir, p.name });
}

fn writeDocument(em: *dom.Emitter, loc: L.Locale, i: usize, alts: []const dom.Alternate) !void {
    const p = pages.all[i];
    const home = std.mem.eql(u8, p.name, "home");
    const canonical = try links.pageHref(em.gpa, loc, i, "");

    var head: std.ArrayList(u8) = .empty;
    defer head.deinit(em.gpa);
    try writeHead(em, &head);

    try dom.document(em, .{
        .title = try documentTitle(em.gpa, loc, i),
        .description = L.trAny(loc, p.blurb),
        .stylesheet = "/style.css",
        .meta = .{
            .origin = origin,
            .path = if (p.kind == .not_found) null else canonical,
            .alternates = alts,
            .site_name = "nokre",
            .title = if (home) "nokre" else L.trAny(loc, p.title),
            .image = .{
                .path = web_assets.share_card_path,
                .shape = .banner,
                .size = .{ .w = web_assets.share_card_width, .h = web_assets.share_card_height },
            },
        },
        .head = head.items,
        .chrome_id = "chrome",
        .content_id = "content",
        .content_class = "page",
        .skip = L.tr(loc, .skipToContent),
        .boot = .{
            .wasm = "/app.wasm",
            .addressing = .documents,
            .seed = if (p.md.len != 0) try sourceUrl(em.gpa, p) else "",
        },
        .csp = .{},
    });
}

fn writeHead(em: *dom.Emitter, out: *std.ArrayList(u8)) !void {
    var h = em.fragment(out);
    defer h.deinit();

    try h.raw(web_assets.head_icon_links);
    try h.raw(
        \\<link rel="preload" href="/assets/fonts/prose.woff2" as="font" type="font/woff2" crossorigin>
        \\
    );
}

fn sourceUrl(gpa: std.mem.Allocator, p: pages.Page) ![]const u8 {
    return std.fmt.allocPrint(gpa, "/md/{s}.md", .{p.name});
}

fn writeStub(em: *dom.Emitter, i: usize) !void {
    const gpa = em.gpa;
    const def = L.default_locale;

    var choices: @FieldType(dom.LocaleStub(L), "choices") = undefined;
    inline for (l10n.locales) |loc| {
        @field(choices, @tagName(loc)) = .{
            .href = try links.pageHref(gpa, loc, i, ""),
            .label = comptime L.tr(loc, .language),
        };
    }

    var head: std.ArrayList(u8) = .empty;
    defer head.deinit(gpa);
    try writeHead(em, &head);

    try dom.localeStub(em, L, .{
        .title = try documentTitle(gpa, def, i),
        .stylesheet = "/style.css",
        .heading = L.tr(def, .chooseLanguage),
        .head = head.items,
        .csp = .{},
        .published = .{ .origin = origin, .path = try links.stubHref(gpa, i) },
        .choices = choices,
    });
}

fn documentTitle(gpa: std.mem.Allocator, loc: L.Locale, i: usize) ![]const u8 {
    const p = pages.all[i];
    if (std.mem.eql(u8, p.name, "home")) return L.tr(loc, .documentTitleHome);
    return std.fmt.allocPrint(gpa, "{s} — nokre", .{L.trAny(loc, p.title)});
}

const external_mark_css = std.fmt.comptimePrint(
    \\
    \\a.link[href^="https://"]::after {{
    \\  content: "\{x}";
    \\  font-family: icons;
    \\  font-size: var(--px-small);
    \\  margin-inline-start: 2px;
    \\  vertical-align: -0.05em;
    \\}}
    \\
, .{@intFromEnum(nok.element.IconName.arrow_up_right)});

fn stylesheet(gpa: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try dom.stylesheet.write(gpa, &out, .{});
    try out.appendSlice(gpa, shell_css);
    return out.toOwnedSlice(gpa);
}

fn checkStylesheet(gpa: std.mem.Allocator, css: []const u8) !void {
    const unresolvable = try css_check.unresolvable(gpa, css, shell_css);
    if (unresolvable.len == 0) return;
    for (unresolvable) |name| {
        std.debug.print("shell CSS spends {s}, which nothing declares at :root\n", .{name});
    }
    std.debug.print("{d} custom propert(ies) resolve to nothing outside .nokre — their whole declarations are dropped\n", .{unresolvable.len});
    return error.UnresolvableCssVar;
}

const shell_css =
    \\
    \\/* The driver's own guard: the edition clips its screen, and this
    \\   keeps the document around it from growing either — a page that
    \\   scrolls sideways leaves every fixed layer covering the wrong
    \\   part of it. */
    \\html { background: var(--paper); overflow-x: clip; }
++ external_mark_css;

fn writeExtras(
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    out_dir: []const u8,
    alternates: []const []const dom.Alternate,
) !void {
    var map: std.ArrayList(u8) = .empty;
    var sm: dom.Sitemap = .init(gpa, origin);
    defer sm.deinit();
    for (l10n.locales) |loc| {
        for (pages.all, 0..) |p, i| {
            if (p.kind == .not_found) continue;
            try sm.url(try links.pageHref(gpa, loc, i, ""), alternates[i]);
        }
    }
    try sm.write(&map);
    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "sitemap.xml" }),
        .data = map.items,
    });

    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "robots.txt" }),
        .data = "User-agent: *\nAllow: /\nSitemap: " ++ origin ++ "/sitemap.xml\n",
    });

    for (web_assets.all) |a| {
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, a.name }),
            .data = a.bytes,
        });
    }

    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, ".nojekyll" }),
        .data = "",
    });
}

test "the external-link mark is nokre's codepoint, spelled as the sheet spells it" {
    try std.testing.expect(std.mem.indexOf(u8, external_mark_css, "content: \"\\e04d\";") != null);
    try std.testing.expectEqual(@as(u21, 0xe04d), @intFromEnum(nok.element.IconName.arrow_up_right));
}

test "every custom property the shell spends is one the document root carries" {
    const gpa = std.testing.allocator;
    const css = try stylesheet(gpa);
    defer gpa.free(css);
    const unresolvable = try css_check.unresolvable(gpa, css, shell_css);
    defer gpa.free(unresolvable);
    for (unresolvable) |name| {
        std.debug.print("shell CSS spends {s}, which nothing declares at :root\n", .{name});
    }
    try std.testing.expectEqual(@as(usize, 0), unresolvable.len);
    const used = try css_check.varsUsed(gpa, shell_css);
    defer gpa.free(used);
    try std.testing.expect(used.len != 0);
}

test {
    _ = pages;
    _ = links;
    _ = icons;
    _ = css_check;
    _ = content;
    _ = &failOnStale;
    _ = &writeExtras;
    _ = &writeDocument;
    _ = &outPath;
    _ = &stubPath;
    _ = &writeStub;
    _ = &documentTitle;
}
