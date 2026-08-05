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

const std = @import("std");
const nok = @import("nokre");
const opts = @import("site_options");

const content = @import("content.zig");
const icons = @import("icons.zig");
const links = @import("links.zig");
const pages = @import("pages.zig");

const audit = nok.testing.audit;
const dom = nok.render.dom;

comptime {
    // This generator is a platform shell; it owes the hooks a shell
    // owes. See shell.zig.
    _ = @import("shell.zig");
}

// The nokre this generator is written against: the sibling checkout is the
// whole dependency, so nokre's hand-bumped `revision` is the only pin a build
// can check. The colophon's git stamp is provenance — which commit was read —
// not a pin; this is the pin. A moved checkout fails here naming both numbers.
const nokre_revision = 23;
comptime {
    if (nok.revision != nokre_revision) @compileError(std.fmt.comptimePrint(
        "written against nokre revision {d}, the checkout is at {d} — survey the generator before bumping",
        .{ nokre_revision, nok.revision },
    ));
}

/// The width the first frame is drawn for.
///
/// Every measured decision on a page — where prose wraps, whether a row
/// of actions folds its tail, whether the nav roster fits on one line —
/// is answered against this, by a stand-in measurer
/// (`text.Measurer.fixed`) rather than a reader's real font. A build has
/// neither the font metrics nor the window, and no number here can be
/// right for every reader.
///
/// Which is why the page ships with the app that wrote it: `web.zig`
/// boots over this frame and retakes those decisions against the column
/// the reader actually has. So the number only decides what the reader
/// who never gets that far sees — script blocked, or the module still
/// in flight — and it is the desktop reading, deliberately: it is the
/// one a crawler, a previewer and a printed page take. The cost is
/// stated rather than hidden: a phone with JavaScript off gets a roster
/// measured for a window it does not have, and the bar overflows. A
/// narrow number would trade that for a collapsed nav on every desktop
/// first paint, which is the same lie pointing the other way.
const viewport: nok.Size = .{ .w = 1280, .h = 1024 };

/// The live driver's browser half, published beside the pages
/// (`docs/internals/dom-edition.md`). The set is nokre's own statement
/// of it, not a re-typed list: this site once re-typed two of the four
/// and shipped a service-worker registration that 404ed on every page
/// load — the list is the library's contract, so it comes from the
/// library.
const driver_files = dom.driver_files;

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

    // ---- sources -----------------------------------------------------
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

    // ---- the app -----------------------------------------------------
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

    // ---- every screen ------------------------------------------------
    var seen: std.ArrayList(links.Seen) = .empty;
    var resolver: links.Resolver = .{ .gpa = gpa, .seen = &seen };

    var documents = try gpa.alloc([]const u8, pages.all.len);
    var anchors = try gpa.alloc([][]const u8, pages.all.len);

    for (pages.all, 0..) |p, i| {
        // switchTo, not push: a visitor arriving at a page has nothing
        // behind them, which is why the framework's Back control is
        // correctly absent (docs/routing.md).
        try app.router.switchTo(&app, p.name);
        // `collect` with `unresolvable_route` skipped: every other rule
        // stays fatal here, and that one's authority this site has
        // deliberately replaced. links.zig is the router's `resolve`
        // for the HTML edition — destinations name pages, anchors and
        // source files, not route-table entries — and it already fails
        // the build on any reference this site cannot honor, which is
        // a stricter check than the table the rule would consult.
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
                std.debug.print("accessibility audit failed on \"{s}\"\n", .{p.name});
                return error.A11yAuditFailed;
            }
        }

        resolver.page = i;
        var out: std.ArrayList(u8) = .empty;
        var em: dom.Emitter = .{
            .gpa = gpa,
            .app = &app,
            .out = &out,
            // Node ids, which a page written to a file has no use for
            // on its own — but this one is the first frame of a live
            // app, and identity across frames is what turns the boot
            // into a patch instead of a replacement. Without them the
            // driver cannot tell that the heading in the file and the
            // heading it just built are the same heading, replaces the
            // subtree wholesale, and takes the reader's scroll position
            // — the anchor they arrived at — with it.
            .options = .{ .refs = resolver.refs(), .node_ids = true },
        };
        try writeDocument(&em, i);
        documents[i] = out.items;
        // The ids the edition minted, kept past the emitter that owns
        // them: they are what another page's `#anchor` has to name.
        anchors[i] = try gpa.dupe([]const u8, em.ids.items);
        for (anchors[i]) |*id| id.* = try gpa.dupe(u8, id.*);
        em.deinit();
    }

    // ---- the link check ----------------------------------------------
    var broken: usize = 0;
    for (seen.items) |ref| {
        switch (ref.target) {
            .page => |t| {
                if (t.frag.len != 0 and !has(anchors[t.index], t.frag)) {
                    std.debug.print("{s}: \"{s}\" names no heading on \"{s}\"\n", .{
                        pages.all[ref.from].name, ref.raw, pages.all[t.index].name,
                    });
                    broken += 1;
                }
            },
            .anchor => |a| {
                if (!has(anchors[ref.from], a)) {
                    std.debug.print("{s}: \"#{s}\" names no heading on this page\n", .{
                        pages.all[ref.from].name, a,
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

    // ---- the icon check ----------------------------------------------
    //
    // The served woff2 draws exactly the codepoints tools/build-fonts.py
    // lists, so an icon in this run's output that the list lacks ships
    // as tofu on every reader's screen — invisible to every check that
    // reads the tree, because the tree only knows names. The list's
    // names and codepoints are themselves proven against nokre by the
    // unit tests (icons.zig); this proves this output against the list.
    // The stylesheet is composed here, before anything is written, so
    // its own icon escapes face the same check the documents do.
    var css: std.ArrayList(u8) = .empty;
    try dom.stylesheet.write(gpa, &css, .{});
    try css.appendSlice(gpa, shell_css);

    const subset = try icons.parse(gpa, icons.py);
    const emitted = try icons.collectEmitted(gpa, documents, css.items);
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

    // ---- write -------------------------------------------------------
    const out_dir = opts.out_dir;
    try cwd.createDirPath(io, out_dir);

    for (pages.all, 0..) |p, i| {
        const path = try outPath(gpa, out_dir, p);
        if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);
        try cwd.writeFile(io, .{ .sub_path = path, .data = documents[i] });
    }

    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "style.css" }),
        .data = css.items,
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

    // The driver, out of the same checkout the documents come from —
    // copied rather than vendored, for the reason the fonts are: a
    // second copy of a library file in this repository is a copy that
    // can be older than the library.
    var script_bytes: usize = 0;
    for (driver_files) |f| {
        const src = try std.fs.path.join(gpa, &.{ opts.repo_dir, "src/render/dom", f });
        const bytes = try cwd.readFileAlloc(io, src, gpa, .limited(1 << 20));
        script_bytes += bytes.len;
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, f }),
            .data = bytes,
        });
    }

    // Each document page's source, for its own boot to fetch. These are
    // the bytes the page was generated from — the same ones, not a
    // rendering of them — because the live app rebuilds the screen from
    // the route's builder and that builder parses Markdown.
    try cwd.createDirPath(io, try std.fs.path.join(gpa, &.{ out_dir, "md" }));
    for (pages.all, 0..) |p, i| {
        if (p.md.len == 0) continue;
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "md", try std.fmt.allocPrint(gpa, "{s}.md", .{p.name}) }),
            .data = sources[i],
        });
    }

    try writeExtras(gpa, io, cwd, out_dir);
    try failOnStale(gpa, io, cwd, out_dir);

    std.debug.print("{d} screens, {d} references, {d} bytes of markup, {d} bytes of driver\n", .{
        pages.all.len,
        seen.items.len,
        total(documents),
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

/// After the write, nothing in the output tree may keep the shape of a
/// generated page this run did not generate. The generator only creates
/// and overwrites, so a renamed or removed route would leave its old
/// `<name>/index.html` and `md/<name>.md` published forever — served,
/// indexed, and invisible to every check that walks the route table,
/// because the route table is exactly what no longer names them. Found
/// ones fail the build rather than being deleted: what a page on its
/// way out becomes — a redirect, a removal commit somebody reviews — is
/// the operator's decision, same fail-forward posture as every other
/// check here. The walk is scoped to the two shapes this run writes,
/// `<route>/index.html` and `md/<route>.md`; everything else in the
/// tree (assets/, the driver files, app.wasm, the extras, 404.html and
/// the root index.html) has a fixed name and a writer of its own.
fn failOnStale(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, out_dir: []const u8) !void {
    var stale: usize = 0;

    var root = try cwd.openDir(io, out_dir, .{ .iterate = true });
    defer root.close(io);
    var it = root.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
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

/// Whether this run wrote `<name>/index.html`: the name must be a
/// route, and one publishing in the directory shape — home lands at the
/// root and the 404 page at `404.html` (`outPath`), so directories by
/// those names would be stale like any other.
fn writesPageDir(name: []const u8) bool {
    const p = pages.find(name) orelse return false;
    return !std.mem.eql(u8, p.name, "home") and p.kind != .not_found;
}

fn outPath(gpa: std.mem.Allocator, out_dir: []const u8, p: pages.Page) ![]const u8 {
    if (std.mem.eql(u8, p.name, "home")) {
        return std.fs.path.join(gpa, &.{ out_dir, "index.html" });
    }
    // The host looks for this one by file name, not by route name.
    if (p.kind == .not_found) return std.fs.path.join(gpa, &.{ out_dir, "404.html" });
    return std.fmt.allocPrint(gpa, "{s}/{s}/index.html", .{ out_dir, p.name });
}

// ------------------------------------------------------------ the shell

/// Everything outside the screen is the driver's, not the tree's.
/// nokre's shells own the window and hand the app events; this one owns
/// the document a browser needs around a screen — a title, a
/// description, a skip link, and the one kind of link nokre has no
/// element for.
///
/// The chrome goes first: the nav leads the focus order as the
/// navigation landmark, which is a property of the tree and not of
/// where CSS ends up putting the bar.
fn writeDocument(em: *dom.Emitter, i: usize) !void {
    const p = pages.all[i];
    const home = std.mem.eql(u8, p.name, "home");
    const canonical = try links.pageHref(em.gpa, i, "");

    try em.raw(
        \\<!doctype html>
        \\<html lang="en">
        \\<head>
        \\<meta charset="utf-8">
        \\<meta name="viewport" content="width=device-width, initial-scale=1">
        \\<title>
    );
    if (home) {
        try em.raw("nokre — a deliberately limited GUI library");
    } else {
        try em.text(p.title);
        try em.raw(" — nokre");
    }
    try em.raw("</title>\n<meta name=\"description\" content=\"");
    try em.text(p.blurb);
    try em.raw("\">\n");
    // The 404 page is served at whatever URL missed, never at its own
    // address — a canonical (or og:url) naming /notfound/ would claim a
    // URL nobody is meant to arrive at. Same posture as the sitemap in
    // writeExtras, which skips this page too.
    if (p.kind != .not_found) {
        try em.print("<link rel=\"canonical\" href=\"https://getnokre.github.io{s}\">\n", .{canonical});
    }
    // theme-color is paper, read from the same ramp the favicon below
    // (writeExtras) reads — a hardcoded pair here would sit still while
    // a ramp change moved every page behind it.
    const paper = nok.Gray.paper;
    try em.print(
        \\<link rel="stylesheet" href="/style.css">
        \\<link rel="icon" href="/favicon.svg" type="image/svg+xml">
        \\<link rel="preload" href="/assets/fonts/prose.woff2" as="font" type="font/woff2" crossorigin>
        \\<meta name="theme-color" media="(prefers-color-scheme: light)" content="#{x:0>2}{x:0>2}{x:0>2}">
        \\<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#{x:0>2}{x:0>2}{x:0>2}">
        \\<meta property="og:type" content="website">
        \\<meta property="og:site_name" content="nokre">
        \\
    , .{
        paper.byte(.light), paper.byte(.light), paper.byte(.light),
        paper.byte(.dark),  paper.byte(.dark),  paper.byte(.dark),
    });
    if (p.kind != .not_found) {
        try em.print("<meta property=\"og:url\" content=\"https://getnokre.github.io{s}\">\n", .{canonical});
    }
    try em.raw("<meta property=\"og:title\" content=\"");
    try em.text(if (home) "nokre" else p.title);
    try em.raw("\">\n<meta property=\"og:description\" content=\"");
    try em.text(p.blurb);
    try em.raw(
        \\">
        \\</head>
        \\<body>
        \\<a class="skip" href="#content">Skip to content</a>
        \\<div id="chrome">
        \\
    );

    // The chrome goes in a mount point of its own rather than loose in
    // the body: the live driver patches the framework's layers as one
    // region and the screen as another, and a region is an element. It
    // costs the document nothing — every layer inside it is fixed, so
    // the div has no size and no effect on where any of them land.
    try dom.chrome(em);
    try em.raw("\n</div>\n<main id=\"content\" class=\"nokre has-chrome page\">\n");
    try dom.content(em);
    try em.raw("\n</main>\n");
    try footer(em);
    try boot(em, i);
    try em.raw("</body>\n</html>\n");
}

/// The upgrade, one script tag wide.
///
/// Everything above this line is a complete page: it reads, it
/// navigates, it prints, and it needs nothing that follows. What
/// follows makes it *true* — a generated page is a screen measured at a
/// width the reader may not have, and only the browser knows the width
/// the reader does have. Boot hands the same app the same route, the
/// measured decisions are retaken against the real column, and the nav
/// roster that could not fit collapses instead of running off the edge.
///
/// A doc page also hands over its Markdown. The driver rebuilds the
/// tree from the route's own builder — that is what makes it the same
/// app rather than a script over some HTML — and that builder expands
/// the source, so the source has to be in hand before the first build.
/// One file per page, fetched alongside the module rather than
/// compiled into it: a reader of one page is not owed the download of
/// every other.
fn boot(em: *dom.Emitter, i: usize) !void {
    const p = pages.all[i];
    try em.raw(
        \\<script type="module">
        \\import { mount } from "/live.js";
        \\mount({
        \\  wasm: "/app.wasm",
        \\  into: document.getElementById("chrome"),
        \\  content: document.getElementById("content"),
        \\  addressing: "documents",
        \\  route: "
    );
    try em.text(p.name);
    try em.raw("\",\n");
    if (p.md.len != 0) {
        try em.print("  seed: \"{s}\",\n", .{try sourceUrl(em.gpa, p)});
    }
    try em.raw("});\n</script>\n");
}

/// Where a page's Markdown is published, for its own boot to fetch.
/// Flat and route-named, like the pages: the route is the key its
/// source is looked up under at build time (pages.zig), and this is the
/// same key with a directory in front of it.
fn sourceUrl(gpa: std.mem.Allocator, p: pages.Page) ![]const u8 {
    return std.fmt.allocPrint(gpa, "/md/{s}.md", .{p.name});
}

fn footer(em: *dom.Emitter) !void {
    // The two repository links leave the site, so they carry the pair
    // every external link here carries (`links.external_attrs`).
    try em.print(
        \\<footer>
        \\<span>MIT licensed. Documentation rendered from the repository at
        \\<a href="{s}/tree/{s}/docs" {s}>docs/</a>.</span>
        \\<span><a href="{s}" {s}>Source on GitHub</a></span>
        \\<span><a href="/colophon/">How this site is built</a></span>
        \\</footer>
        \\
    , .{ links.repo_url, links.branch, links.external_attrs, links.repo_url, links.external_attrs });
}

/// The driver's own rules, appended after the edition's stylesheet.
/// Everything here is about the *document* — its reading column, the
/// skip link, the footer — and none of it restyles an element: there is
/// no styling API to reach for, on this edition either.
const shell_css =
    \\
    \\/* ---- the page ---------------------------------------------------- */
    \\
    \\/* This site's reading column, and its own number — not `--pane`.
    \\   That variable is `metrics.sheet_max_w`, which the library spends
    \\   on the surfaces that hold prose *inside* an app: a sheet, the
    \\   notices pane, a select's picker. Borrowing it for the document
    \\   made the page look like it was obeying a library rule it was in
    \\   fact only agreeing with, and retuning it here would have moved
    \\   every one of those panes and the geometry core derives from them.
    \\
    \\   560 is the phone's answer and the right one there. A desktop
    \\   window reading 560px of a 1400px display looks like a phone
    \\   emulator, so the column steps up once — 760px, still inside the
    \\   65–75 character band prose wants, which is the whole argument for
    \\   capping it at all. One step and no more: the next one buys line
    \\   length nobody asked for. */
    \\:root { --page-col: 560px; }
    \\@media (min-width: 900px) { :root { --page-col: 760px; } }
    \\/* The driver's own guard: the edition clips its screen, and this
    \\   keeps the document around it from growing either — a page that
    \\   scrolls sideways leaves every fixed layer covering the wrong
    \\   part of it. */
    \\html { background: var(--paper); overflow-x: clip; }
    \\/* The cap is on the element the screen is *in*, because that is the
    \\   width the live driver reports to core as the viewport — a column
    \\   the page kept to itself would be one core never heard of, and
    \\   every measured decision (where prose wraps, whether the roster
    \\   fits, whether a track may bleed) would be answered against a
    \\   width nobody is looking at. So the step at 900px is not a page
    \\   style: it is core being handed a wider viewport and answering
    \\   those questions again against it. */
    \\/* `--page-pad` and not `--pad`: the short name is the root stack's
    \\   own field, published on `.nokre` and nowhere above it. The footer
    \\   and the skip link are body children rather than stacks, so every
    \\   `var(--pad)` they were written with resolved to nothing — and a
    \\   custom property that resolves to nothing takes its whole
    \\   declaration with it. The footer had therefore been running
    \\   unpadded and uncapped across the window, which is the one thing
    \\   these two rules exist to prevent. */
    \\main.page, footer {
    \\  max-width: calc(var(--page-col) + 2 * var(--page-pad));
    \\  margin-inline: auto;
    \\}
    \\
    \\footer {
    \\  display: flex;
    \\  flex-wrap: wrap;
    \\  gap: var(--page-gap) var(--page-pad);
    \\  margin-top: var(--page-pad);
    \\  padding: var(--page-pad);
    \\  padding-bottom: calc(var(--nav-content-gap) + var(--nav-slot) + var(--nav-bar-pad-b) + var(--page-pad));
    \\  border-top: var(--border) solid var(--g10);
    \\  font-size: var(--px-small);
    \\  line-height: var(--lh-small);
    \\  color: var(--mid);
    \\}
    \\footer a { color: inherit; text-decoration: underline; text-underline-offset: 2px; }
    \\
    \\/* The only links on this site that leave it. nokre navigates its own
    \\   screens and nothing else, so it has no element for one and no mark
    \\   for one either; a page that cites a source file has to say where
    \\   it is sending you. The glyph is Lucide's arrow-up-right out of the
    \\   same icon face, and it is decorative — the words are the link. */
    \\a.link[href^="https://"]::after {
    \\  content: "\e04d";
    \\  font-family: icons;
    \\  font-size: var(--px-small);
    \\  margin-inline-start: 2px;
    \\  vertical-align: -0.05em;
    \\}
    \\
    \\.skip {
    \\  position: absolute;
    \\  inset-inline-start: var(--page-pad);
    \\  top: calc(-1 * var(--touch) - 16px);
    \\  z-index: 5;
    \\  padding: var(--button-pad-v) var(--button-pad-h);
    \\  border-radius: var(--radius);
    \\  background: var(--ink);
    \\  color: var(--paper);
    \\  text-decoration: none;
    \\}
    \\.skip:focus { top: var(--page-pad); }
    \\
    \\@media print {
    \\  .nav, .skip { display: none; }
    \\  main.page { max-width: none; }
    \\  .nokre.has-chrome, footer { padding-bottom: var(--page-pad); }
    \\}
    \\
;

// ------------------------------------------------------------- extras

fn writeExtras(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, out_dir: []const u8) !void {
    var map: std.ArrayList(u8) = .empty;
    try map.appendSlice(gpa,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \\
    );
    for (pages.all, 0..) |p, i| {
        if (p.kind == .not_found) continue;
        const href = try links.pageHref(gpa, i, "");
        try map.print(gpa, "<url><loc>https://getnokre.github.io{s}</loc></url>\n", .{href});
    }
    try map.appendSlice(gpa, "</urlset>\n");
    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "sitemap.xml" }),
        .data = map.items,
    });

    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "robots.txt" }),
        .data = "User-agent: *\nAllow: /\nSitemap: https://getnokre.github.io/sitemap.xml\n",
    });

    // A mark made of what the library draws: a box, and lines of text
    // inside it. Both ramps, because a favicon follows the appearance
    // like everything else.
    const Gray = nok.Gray;
    const favicon = try std.fmt.allocPrint(gpa,
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
        \\<style>
        \\  .edge {{ fill: none; stroke: #{x:0>2}{x:0>2}{x:0>2}; stroke-width: 2 }}
        \\  .rule {{ stroke: #{x:0>2}{x:0>2}{x:0>2}; stroke-width: 2 }}
        \\  @media (prefers-color-scheme: dark) {{
        \\    .edge {{ stroke: #{x:0>2}{x:0>2}{x:0>2} }}
        \\    .rule {{ stroke: #{x:0>2}{x:0>2}{x:0>2} }}
        \\  }}
        \\</style>
        \\<rect class="edge" x="3" y="3" width="26" height="26" rx="8"/>
        \\<path class="rule" d="M9 12h14M9 17h14M9 22h8"/>
        \\</svg>
        \\
    , .{
        Gray.ink.byte(.light), Gray.ink.byte(.light), Gray.ink.byte(.light),
        Gray.mid.byte(.light), Gray.mid.byte(.light), Gray.mid.byte(.light),
        Gray.ink.byte(.dark),  Gray.ink.byte(.dark),  Gray.ink.byte(.dark),
        Gray.mid.byte(.dark),  Gray.mid.byte(.dark),  Gray.mid.byte(.dark),
    });
    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, "favicon.svg" }),
        .data = favicon,
    });

    // GitHub Pages would otherwise try to run the output through Jekyll.
    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, ".nojekyll" }),
        .data = "",
    });
}

test {
    _ = pages;
    _ = links;
    _ = icons;
    // Analysis is lazy and only the entry point references the write
    // path, so the test build would otherwise skip it. `main` itself
    // cannot be pulled in — App.Options drops the `services` default
    // under test on purpose — but the helpers past App.init can be.
    _ = &failOnStale;
    _ = &writeExtras;
}
