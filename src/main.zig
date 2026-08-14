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
    // This generator is a platform shell; it owes the hooks a shell
    // owes. See shell.zig.
    _ = @import("shell.zig");
}

// The nokre this generator is written against: the sibling checkout is the
// whole dependency, so nokre's hand-bumped `revision` is the only pin a build
// can check. The colophon's git stamp is provenance — which commit was read —
// not a pin; this is the pin. A moved checkout fails here naming both numbers.
const nokre_revision = 82;
comptime {
    if (nok.revision != nokre_revision) @compileError(std.fmt.comptimePrint(
        "written against nokre revision {d}, the checkout is at {d} — survey the generator before bumping",
        .{ nokre_revision, nok.revision },
    ));
}

/// Where this site is published: scheme and host, no trailing slash.
///
/// One constant because it had been four copies — the canonical, the
/// `og:url`, the sitemap's `<loc>` and robots.txt's `Sitemap:` — and a
/// site that moved host would have had to find all four, with nothing
/// anywhere to say it had missed one. It is *config*, which is why it
/// lives here and not in nokre: the library joins it to a path and
/// checks the join, and has no way to know or guess the value
/// (`dom.Meta.origin`).
///
/// The locale axis added a fifth spender rather than a fifth copy —
/// every chooser stub says where it stands (`writeStub`'s `published`),
/// which is what puts a real `hreflang` block on it — and it reads this
/// constant like the other four.
///
/// The one occurrence of this string in the tree that is *not* a copy
/// of this and must not become one: content.zig's `qr` example draws a
/// QR code *of* this site on the elements page. That is content — a
/// thing a reader points a camera at — not a destination the document
/// claims.
const origin = "https://getnokre.github.io";

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
/// measured for a window it does not have. What that costs is a band
/// the reader drags sideways to reach the far end of, rather than a row
/// with its ends hanging past both screen edges — the sheet answers a
/// row that will not fit by scrolling it, and that answer needs nothing
/// running (`../nokre/docs/static-sites.md`). A narrow number would
/// trade the whole thing for a collapsed nav on every desktop first
/// paint, which is the same lie pointing the other way.
const viewport: nok.Size = .{ .w = 1280, .h = 1024 };

/// The live driver's browser half, published beside the pages
/// (`docs/internals/dom-edition.md`). The set *and its bytes* are
/// nokre's own statement of it, not a re-typed list and not a path into
/// a checkout: this site once re-typed two of the four it then had and
/// shipped a service-worker registration that 404ed on every page load
/// — the set is the library's contract, so it comes from the library,
/// and so do the files. "It then had" is the point. The set has grown
/// since, and this loop published the new members without a line
/// changing here: what a page and a stub now load instead of carrying
/// inline are two more files in it (`../nokre/docs/static-sites.md`).
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

    // ---- the alternate sets ------------------------------------------
    //
    // Before any page is written, because two writers spend each one and
    // the whole point of the type is that they spend the *same* value.
    // A route's set is a property of the route and not of the copy — the
    // English page and the Persian page of one route carry byte-identical
    // blocks — which is why this is indexed by page and not by page and
    // locale, and why reciprocity is not something anything here checks.
    var alternates = try gpa.alloc([]const dom.Alternate, pages.all.len);
    for (pages.all, 0..) |p, i| {
        // The 404 body is served at whatever URL missed and has no
        // address of its own, so it has no set of addresses either.
        // Empty rather than absent, so no reader of this array has to
        // remember the exception — and it is what the library requires
        // anyway: `alternates.check` refuses a non-empty set on a page
        // whose `Meta.path` is null, because a page nobody is meant to
        // arrive at cannot be a member of a set.
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

    // ---- every screen, once per locale -------------------------------
    var seen: std.ArrayList(links.Seen) = .empty;
    var resolver: links.Resolver = .{ .gpa = gpa, .seen = &seen };

    var documents: [l10n.locales.len][][]const u8 = undefined;
    var anchors: [l10n.locales.len][][]const []const u8 = undefined;
    for (&documents) |*d| d.* = try gpa.alloc([]const u8, pages.all.len);
    for (&anchors) |*a| a.* = try gpa.alloc([]const []const u8, pages.all.len);

    for (l10n.locales, 0..) |loc, li| {
        // The three lines docs/localization.md documents, in the order
        // it documents them. `setChrome` is what puts nokre's own words
        // — the Back control, the section chip, the notices pane — in
        // this catalog rather than on the library's English defaults,
        // and `L.chrome` derives one reserved key per `Chrome` field at
        // comptime, so a word the library grows is a build error here
        // and never a shipped English string on a Persian page.
        // `setDirection` is the one of the three that is silent when
        // forgotten, which is why it is written even where every
        // bundled locale is left-to-right.
        try app.setLocale(L.tag(loc));
        app.setChrome(L.chrome(loc));
        app.setDirection(L.dir(loc));

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
                    std.debug.print("accessibility audit failed on \"{s}\" in {s}\n", .{ p.name, L.tag(loc) });
                    return error.A11yAuditFailed;
                }
            }

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
            try writeDocument(&em, loc, i, alternates[i]);
            documents[li][i] = out.items;
            // The anchors this page exports — what another page's `#frag`
            // has to name. The edition hands them over whole
            // (internals/dom-edition.md, "A heading is an address"); reading
            // the emitter's own dedup bookkeeping and deep-copying it before
            // `deinit` was this site holding bookkeeping and calling it an
            // answer.
            anchors[li][i] = try em.takeAnchors(gpa);
            em.deinit();
        }
    }

    // ---- the chooser stubs -------------------------------------------
    //
    // One page at every unprefixed path, which is where every link
    // written before this site had a locale axis still points. nokre
    // writes them: the resolution is the bundle's own, transcribed once
    // in the library and held to `L.resolve`'s answers by a gate there,
    // and a driver that rolled its own would be a second policy
    // (`dom.localeStub`). What this file supplies is the two things the
    // library cannot know — where each locale's copy is published, and
    // what each language is called in itself.
    var stubs = try gpa.alloc([]const u8, pages.all.len);
    for (pages.all, 0..) |p, i| {
        // The 404 has no unprefixed address to stand at: the host
        // serves its body at whatever URL missed, so there is no link
        // anywhere to preserve and nothing for a chooser to choose
        // between.
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

    // ---- the link check ----------------------------------------------
    var broken: usize = 0;
    for (seen.items) |ref| {
        // A reference is checked against the anchors of the copy it was
        // written on: a heading id is derived from the words of the
        // heading, so it is a per-locale fact and a set shared across
        // locales would pass a Persian `#frag` against English ids.
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
    const css = try stylesheet(gpa);

    // ---- the stylesheet check ------------------------------------
    //
    // Custom properties inherit, so a `var(--x)` the shell's rules spend
    // outside `.nokre` resolves to nothing unless something declares it
    // at `:root` — and a declaration that resolves to nothing is dropped
    // whole, silently. This site shipped its footer unpadded across the
    // window that way once (css.zig). Here as well as in the unit test
    // below, because the two ask about different things: the test asks
    // whether the sheet *this site is written against* is sound, and
    // this asks it of the bytes about to be written, which is where a
    // nokre that moved a property deeper would show up.
    try checkStylesheet(gpa, css);

    // Every byte of markup this run publishes, in one list: each
    // locale's copy of each page, and the stubs. The stubs are in it
    // because they are pages a reader can land on — an icon escape that
    // only ever appeared on one would be tofu nothing else here looks
    // at.
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

    // ---- write -------------------------------------------------------
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

    // The driver, out of the library itself — its bytes, not a path
    // into a checkout. Copied rather than vendored for the reason the
    // fonts are (a second copy of a library file in this repository is
    // a copy that can be older than the library), and now not located
    // either: `dom.driver_sources` carries name and bytes together, so
    // this site no longer knows or cares which directory of nokre they
    // live in.
    var script_bytes: usize = 0;
    for (driver_sources) |src| {
        script_bytes += src.bytes.len;
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, src.name }),
            .data = src.bytes,
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

/// After the write, nothing in the output tree may keep the shape of a
/// generated page this run did not generate. The generator only creates
/// and overwrites, so a renamed or removed route would leave its old
/// `<name>/index.html` and `md/<name>.md` published forever — served,
/// indexed, and invisible to every check that walks the route table,
/// because the route table is exactly what no longer names them. Found
/// ones fail the build rather than being deleted: what a page on its
/// way out becomes — a redirect, a removal commit somebody reviews — is
/// the operator's decision, same fail-forward posture as every other
/// check here.
///
/// The walk is scoped to the shapes this run writes, and the locale
/// axis added one level to two of them: `<locale>/index.html` and
/// `<locale>/<route>/index.html` are the pages, `<route>/index.html` is
/// that route's chooser stub, and `md/<route>.md` is its source.
/// Everything else in the tree (assets/, the driver files, app.wasm,
/// the extras, 404.html and the root index.html) has a fixed name and a
/// writer of its own.
///
/// A locale that leaves the catalog is caught by the same walk without
/// a rule of its own: `docs/de/` stops being a locale directory the
/// moment `site_de.arb` is removed, so it falls to the stub test, and
/// `de` is not a route.
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

/// One locale directory's own sweep. Its `index.html` is that locale's
/// home page and needs no test; every directory inside it must be a
/// route publishing in the directory shape, which is the same predicate
/// the stubs answer to — home lands at the locale root and the 404 page
/// is not per-locale at all.
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

/// Whether `<name>` is a directory this site publishes a locale under —
/// asked of the catalog and of nothing else, so the answer cannot
/// disagree with the set the pages were generated for.
fn isPublishedLocale(name: []const u8) bool {
    for (l10n.locales) |loc| {
        if (std.mem.eql(u8, L.tag(loc), name)) return true;
    }
    return false;
}

/// Whether this run wrote `<name>/index.html` under a locale, and a
/// chooser stub at `<name>/index.html` beside them: the name must be a
/// route, and one publishing in the directory shape — home lands at the
/// locale's root (and its stub at the site's) and the 404 page at
/// `404.html`, so directories by those names would be stale like any
/// other.
fn writesPageDir(name: []const u8) bool {
    const p = pages.find(name) orelse return false;
    return !std.mem.eql(u8, p.name, "home") and p.kind != .not_found;
}

/// Where one locale's copy of a page lands. Every page is prefixed, the
/// default locale included: there is no bare-default copy anywhere, and
/// the unprefixed path belongs to the chooser (`stubPath`).
///
/// **`null` is the 404 body on every locale but the template's**, and
/// it is the one place the axis does not multiply a file. A static host
/// serves one document for a URL that missed — GitHub Pages looks for
/// `404.html` at the site root and nowhere else — so a per-locale copy
/// would be a file nothing can ever request. It is written in the
/// template's language for the same reason the chooser is: nothing
/// about a URL that missed says what its reader reads.
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

/// Where a page's chooser stub lands: the path the page itself used to
/// be published at, exactly. That is what makes the move free — every
/// inbound link and every cross-doc fragment written against the old
/// scheme still resolves, and lands on the copy in the reader's own
/// language instead of a 404.
fn stubPath(gpa: std.mem.Allocator, out_dir: []const u8, p: pages.Page) ![]const u8 {
    if (std.mem.eql(u8, p.name, "home")) {
        return std.fs.path.join(gpa, &.{ out_dir, "index.html" });
    }
    return std.fmt.allocPrint(gpa, "{s}/{s}/index.html", .{ out_dir, p.name });
}

// ------------------------------------------------------------ the shell

/// Everything outside the screen is the driver's, not the tree's — and
/// "outside the screen" is now a much smaller place than it was.
/// `dom.document` writes the file: the doctype, the root element's
/// language and direction, the head's fixed half, the two mount points,
/// the skip link, and the boot script that turns the file into the
/// app's first frame. What is left here is what this site invented —
/// the ids it mounts into, the URLs it publishes things at, the words on
/// its skip link, and the one seam's worth of markup nokre has no
/// element and no opinion for.
///
/// One seam, and it was two. The other took the footer, and a footer is
/// content: a stack of links and a sentence, which the library can style,
/// clear, audit and resolve routes for the moment it is in the tree
/// instead of beside it. It is `content.footer` now, appended by the
/// page builder like everything else on the page, and nothing here
/// stands below the screen (`../nokre/docs/static-sites.md`, "A seam is
/// for what does not render").
///
/// The upgrade the boot script carries is the whole reason the pair
/// exists: everything above it is a complete page — it reads, it
/// navigates, it prints — and what follows makes it *true*, because a
/// generated page is a screen measured at a width the reader may not
/// have. A doc page hands its Markdown over the same way (`seed`): the
/// live driver rebuilds the tree from the route's own builder, that
/// builder expands the source, and a build cannot wait for a fetch.
fn writeDocument(em: *dom.Emitter, loc: L.Locale, i: usize, alts: []const dom.Alternate) !void {
    const p = pages.all[i];
    const home = std.mem.eql(u8, p.name, "home");
    // This page's path, from this site's own resolver — the same
    // function every in-page link goes through, so a page's canonical
    // and the links pointing at it cannot name different addresses.
    const canonical = try links.pageHref(em.gpa, loc, i, "");

    var head: std.ArrayList(u8) = .empty;
    defer head.deinit(em.gpa);
    try writeHead(em, &head);

    try dom.document(em, .{
        .title = try documentTitle(em.gpa, loc, i),
        .description = L.trAny(loc, p.blurb),
        .stylesheet = "/style.css",
        // What this page tells a crawler and a link preview. The two
        // destinations are this site's — where it is published, and
        // what this page's path is — and nokre's half is that they
        // cannot come apart: `og:url` is the canonical because there is
        // one `path` behind both, and the 404 page says `null` rather
        // than carrying a URL with a flag beside it.
        .meta = .{
            .origin = origin,
            // The 404 body is served at whatever URL missed, never at
            // its own address. Same posture as the sitemap in
            // writeExtras, which skips this page too.
            .path = if (p.kind == .not_found) null else canonical,
            // Every address this page also lives at: its own copy per
            // locale, and the `x-default` naming the chooser. It used
            // to be `&.{}` and the ground for that has since become
            // false — a page with one language still had one URL then,
            // and the prefix-plus-stub scheme gives every page two that
            // are different *in kind*. A crawler told nothing about the
            // pair guesses at the relationship and may index the
            // chooser as a duplicate of the page it points at.
            .alternates = alts,
            .site_name = "nokre",
            // The card shows the site's name beside the headline, so
            // the `<title>`'s " — nokre" suffix there would be the site
            // named twice.
            .title = if (home) "nokre" else L.trAny(loc, p.title),
            // The card a link preview fetches: nokre's own derivation
            // from the declared mark and the app's name, not artwork
            // authored here. Path and frame are the module's constants,
            // so the tag and the file cannot come apart. Empty alt on
            // purpose — the picture is the mark and the name, nothing a
            // reader is not already told.
            .image = .{
                .path = web_assets.share_card_path,
                .shape = .banner,
                .size = .{ .w = web_assets.share_card_width, .h = web_assets.share_card_height },
            },
        },
        .head = head.items,
        // The mount points are this site's own names, which is why they
        // are parameters and not something the library picked. They are
        // also two rather than one: the live driver patches the
        // framework's layers as one region and the screen as another,
        // and a region is an element.
        .chrome_id = "chrome",
        .content_id = "content",
        // Beside nokre's own class list, which `dom.document` writes
        // from `rootClass` — this half is the reading column, and it is
        // the site's.
        .content_class = "page",
        .skip = L.tr(loc, .skipToContent),
        // Every page, and that is a decision and not the default.
        //
        // nokre reads off the tree whether a page *needs* a runtime and
        // refuses one that needs one and has no boot (`dom.needsRuntime`,
        // `error.PageNeedsBoot`). It is a floor, though, not a ceiling: a
        // page may carry a boot for a need no tree can show. Nearly every
        // page here is below that floor — prose and links publish whole,
        // and a tile is a link wherever it carries a route rather than a
        // press (`Element.needsRuntime`), which is what every tile on
        // this site carries — and they carry a boot anyway, for two needs
        // the tree cannot state.
        //
        // The nav's shape is the first. The file was measured against
        // 1280 pixels and the reader's window is whatever it is; above
        // the cap the header wraps and nothing is owed, but below it the
        // band's own answer to a row that will not fit is to scroll, and
        // the chip is what a driver *upgrades* that to. A prose page is
        // read on a phone as often as the gallery is, so it is owed the
        // upgrade as much — which is the colophon's "an upgrade and not
        // a requirement", said about the whole site and not about six
        // pages of it.
        //
        // A document page's Markdown is the second, and it is the
        // concrete one. `seed` is fetched by that page's own boot and by
        // nothing else — addressing is `.documents`, so no screen here
        // ever builds another screen — so a doc page that did not boot
        // would leave the source it was generated from published at an
        // address nothing requests.
        .boot = .{
            .wasm = "/app.wasm",
            .addressing = .documents,
            .seed = if (p.md.len != 0) try sourceUrl(em.gpa, p) else "",
        },
        // The policy this page carries about itself, and a `<meta>` is
        // the only vehicle this repository has for one: Pages serves
        // the committed tree as it stands and takes no header
        // configuration from here (README, "Publishing"). So the three
        // directives a `<meta>` cannot carry are simply unstated —
        // there is no edge of this site's to state them at
        // (`../nokre/docs/static-sites.md`).
        //
        // Every directive in it is nokre's, derived from the rest of
        // this value; what a driver supplies is the hosts its app
        // fetches beyond its own origin, and this site has none.
        // Everything a page here asks for is a file this site
        // publishes — the module, the driver's own files, and a doc
        // page's `seed` above — and the wasm half links no service that
        // talks to anything (web.zig). A host named here would be a
        // power granted to nobody.
        .csp = .{},
    });
}

/// The head seam: what is left of this site's own head once nokre
/// writes the parts that have invariants — the icon block, received
/// whole from the library (conditionality and the `.ico` sizes
/// attribute already resolved), and where this site published its
/// faces. Placement stays this seam's; the bytes stopped being its to
/// compose (`../nokre/docs/static-sites.md`).
///
/// It used to carry the canonical and the Open Graph block too. Those
/// moved to `dom.Meta` (`writeDocument` above), which is not this site
/// losing a destination: it still states its own origin and its own
/// path. What it stopped stating is the *relationship* between them —
/// that `og:url` is the canonical, that both are absolute, and that a
/// page with no URL of its own has neither — which is what a second
/// static consumer would otherwise have re-derived from scratch.
///
/// Built into a buffer of the driver's own and handed over as bytes.
/// The emitter is a second one over that buffer (`Emitter.fragment`),
/// so the escape is the same one the rest of the document gets; the
/// seam is bytes rather than a callback because a hook holding `em.out`
/// could write anywhere, and "into the head" is the one thing it would
/// then be unable to say.
fn writeHead(em: *dom.Emitter, out: *std.ArrayList(u8)) !void {
    var h = em.fragment(out);
    defer h.deinit();

    try h.raw(web_assets.head_icon_links);
    try h.raw(
        \\<link rel="preload" href="/assets/fonts/prose.woff2" as="font" type="font/woff2" crossorigin>
        \\
    );
}

/// Where a page's Markdown is published, for its own boot to fetch.
/// Flat and route-named, like the pages: the route is the key its
/// source is looked up under at build time (pages.zig), and this is the
/// same key with a directory in front of it.
fn sourceUrl(gpa: std.mem.Allocator, p: pages.Page) ![]const u8 {
    return std.fmt.allocPrint(gpa, "/md/{s}.md", .{p.name});
}

/// The page at every unprefixed path: the chooser this site's readers
/// and its old inbound links land on.
///
/// nokre writes the document, the script and the no-JS links; what this
/// supplies is the pair the library cannot derive — where each locale's
/// copy of *this* page is published, and what each language is called
/// in its own language. Neither is a list of tags: `choices` has one
/// field per bundled locale, generated from the catalog, so a locale
/// this site publishes and forgets here is a compile error.
///
/// **The identity case needs no branch.** With one locale the stub's
/// only choice is the page it stands beside, and a reader is sent
/// there; a stub that ever stood at one of its own choices would be
/// told so by the library's own guard, which compares against the
/// resolved URL and navigates nowhere rather than spinning.
///
/// It is in no locale — that is what it is for — so every word on it
/// comes from `L.default_locale`, which is also the language the script
/// falls back to and the one nokre stamps on its root element.
fn writeStub(em: *dom.Emitter, i: usize) !void {
    const gpa = em.gpa;
    const def = L.default_locale;

    var choices: @FieldType(dom.LocaleStub(L), "choices") = undefined;
    inline for (l10n.locales) |loc| {
        @field(choices, @tagName(loc)) = .{
            .href = try links.pageHref(gpa, loc, i, ""),
            // The language's name in that language, out of that
            // language's own catalog — the one form a reader who cannot
            // read this page can act on, and not a table of language
            // names this site would otherwise have had to keep.
            .label = comptime L.tr(loc, .language),
        };
    }

    var head: std.ArrayList(u8) = .empty;
    defer head.deinit(gpa);
    try writeHead(em, &head);

    try dom.localeStub(em, L, .{
        // The same `<title>` its own page carries, in the template's
        // language: this is that page at its language-neutral address,
        // and what tells a crawler the two are variants rather than
        // duplicates is the alternate set below, not a different
        // sentence in the tab.
        .title = try documentTitle(gpa, def, i),
        .stylesheet = "/style.css",
        .heading = L.tr(def, .chooseLanguage),
        .head = head.items,
        // The same request the pages make, over a much shorter page,
        // and it comes out a narrower policy without this driver saying
        // so: a chooser loads one script of the library's over a list
        // of links, compiles nothing and boots nothing, so it is handed
        // none of the powers a page that runs the app is. Nothing on it
        // fetches, which is also why it may not name a host and does
        // not (`dom.CspError.ConnectSrcWithoutBoot`).
        .csp = .{},
        // Where this page is, which is the whole of what it takes to
        // put the alternate set on it: `choices` is already one path
        // per locale, and `x-default` is this address because a chooser
        // is what `x-default` means. Nothing is restated.
        .published = .{ .origin = origin, .path = try links.stubHref(gpa, i) },
        .choices = choices,
    });
}

/// A page's `<title>`, in one locale. One writer, because the copy and
/// its chooser must not disagree about what the page is called.
///
/// Not `app.title()`, though nokre grew that accessor for a static
/// driver to spend here. Two reasons, and the second is the one that
/// decides it. The chooser has no built screen to read a title off —
/// `writeStub` runs after the per-locale loop, over an app standing on
/// whatever page it finished on — so reading the tree would split the
/// one writer this function exists to be. And a `<title>` here is not
/// the screen's title: it is that plus the site's name, and home's is a
/// sentence of its own. The suffix is the driver's, which is nokre's own
/// reason for not defaulting `Document.title` to the screen's.
///
/// Nothing is restated either way: `p.title` is the same declaration the
/// router now draws the page's `h1` from, so there is no second copy of
/// the words to go stale.
fn documentTitle(gpa: std.mem.Allocator, loc: L.Locale, i: usize) ![]const u8 {
    const p = pages.all[i];
    if (std.mem.eql(u8, p.name, "home")) return L.tr(loc, .documentTitleHome);
    return std.fmt.allocPrint(gpa, "{s} — nokre", .{L.trAny(loc, p.title)});
}

/// The external-link mark's rule, split out of `shell_css` for exactly
/// one reason — the sheet's own comment above it already says what the
/// mark is for. The codepoint is nokre's, spelled as a CSS escape by
/// derivation rather than typed:
/// `IconName`'s enum value *is* the font codepoint (nokre's
/// icon_names.zig), so this cannot name a glyph the face does not draw,
/// and the generation-time icon check that reads CSS escapes is proving
/// this against the served subset rather than against a literal that
/// agreed with itself.
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

/// The one sheet this site serves: the edition's, then the shell's own
/// document rules. One home, because the check below and the generator
/// must be asking about the same bytes.
fn stylesheet(gpa: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try dom.stylesheet.write(gpa, &out, .{});
    try out.appendSlice(gpa, shell_css);
    return out.toOwnedSlice(gpa);
}

/// Every custom property the shell's rules spend must be declared at
/// `:root`, because those rules apply to the document and a property
/// published deeper — nokre puts `--pad` and `--gap` on `.nokre` — does
/// not inherit upward. See css.zig for the footer this caught.
fn checkStylesheet(gpa: std.mem.Allocator, css: []const u8) !void {
    const unresolvable = try css_check.unresolvable(gpa, css, shell_css);
    if (unresolvable.len == 0) return;
    for (unresolvable) |name| {
        std.debug.print("shell CSS spends {s}, which nothing declares at :root\n", .{name});
    }
    std.debug.print("{d} custom propert(ies) resolve to nothing outside .nokre — their whole declarations are dropped\n", .{unresolvable.len});
    return error.UnresolvableCssVar;
}

/// The driver's own rules, appended after the edition's stylesheet.
/// Everything here is about the *document* — its reading column, its
/// paper, the print sheet and the mark on an outbound link — and none of
/// it restyles an element: there is no styling API to reach for, on this
/// edition either. It is shorter by the footer's rules, which is what
/// moving the footer into the tree bought: the block that centred it,
/// bordered it, sized it and re-inked it was a driver styling its own
/// content because the seam had put that content outside everything
/// that would otherwise have done it.
/// What is left of a document rule that was never the library's. The
/// reading column used to live here, capped by hand on the two boxes
/// this site mounts into — the only place for it while core had no page
/// column. Core has one now and the DOM sheet states it on the root and
/// on the header's row, so both mounts take it without being told, and
/// this file stops being one of the three copies that had drifted apart.
const shell_css =
    \\
    \\/* The driver's own guard: the edition clips its screen, and this
    \\   keeps the document around it from growing either — a page that
    \\   scrolls sideways leaves every fixed layer covering the wrong
    \\   part of it. */
    \\html { background: var(--paper); overflow-x: clip; }
++ external_mark_css;

// ------------------------------------------------------------- extras

fn writeExtras(
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    out_dir: []const u8,
    alternates: []const []const dom.Alternate,
) !void {
    // The `<urlset>` is nokre's to write and this site's to publish:
    // the XML escape, the `xhtml` namespace, the spec's two limits and
    // the check that every alternate a page names was actually
    // published are all things one file can see and no page can
    // (`dom.Sitemap`). What stays here is where the bytes go, which is
    // the same line the document writer draws.
    //
    // The set each entry carries is the *same array* the page's own
    // head was written from, not a second derivation over the same
    // rule. Taking it as an argument is what let the locale axis land
    // without touching this call: what changed is that `&.{}` became a
    // real set.
    //
    // The chooser stubs are not entries. The closure rule exempts
    // `x-default` for exactly this reason — whether a chooser is itself
    // indexed is publishing policy — and this site's answer is that a
    // sitemap lists content, of which there is one URL per page per
    // language. The stubs are still reachable, still annotated, and
    // still the `x-default` every entry names.
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

    // The derived identity set — favicon.ico, the adaptive favicon.svg,
    // the touch icons, share-card.png — nokre's bytes, every one
    // derived from assets/icon-silhouette.svg and the declaration. The
    // mark used to be drawn right here from `nok.Gray`; it is declared
    // identity now, same geometry flattened to one shade, because the
    // silhouette decoder takes fills in a single tone and nothing else.
    for (web_assets.all) |a| {
        try cwd.writeFile(io, .{
            .sub_path = try std.fs.path.join(gpa, &.{ out_dir, a.name }),
            .data = a.bytes,
        });
    }

    // GitHub Pages would otherwise try to run the output through Jekyll.
    try cwd.writeFile(io, .{
        .sub_path = try std.fs.path.join(gpa, &.{ out_dir, ".nojekyll" }),
        .data = "",
    });
}

test "the external-link mark is nokre's codepoint, spelled as the sheet spells it" {
    // The escape used to be typed. It is derived now, so this pins the
    // *spelling* — lowercase hex, no trailing space — which is what the
    // generation-time icon scan reads to prove the glyph is in the
    // served subset (icons.zig). A `{x}` that formatted differently
    // would leave that scan quietly covering nothing.
    try std.testing.expect(std.mem.indexOf(u8, external_mark_css, "content: \"\\e04d\";") != null);
    try std.testing.expectEqual(@as(u21, 0xe04d), @intFromEnum(nok.element.IconName.arrow_up_right));
}

test "every custom property the shell spends is one the document root carries" {
    // The regression this exists for is invisible: `var(--pad)` in the
    // footer was valid CSS that resolved to nothing, which drops the
    // whole declaration — so the footer ran unpadded and uncapped
    // across the window and every page still passed every check. The
    // sheet is deterministic and needs no filesystem, so the guard is a
    // unit test as well as a generation-time one.
    const gpa = std.testing.allocator;
    const css = try stylesheet(gpa);
    defer gpa.free(css);
    const unresolvable = try css_check.unresolvable(gpa, css, shell_css);
    defer gpa.free(unresolvable);
    for (unresolvable) |name| {
        std.debug.print("shell CSS spends {s}, which nothing declares at :root\n", .{name});
    }
    try std.testing.expectEqual(@as(usize, 0), unresolvable.len);
    // …and the scan found something to check, so a rename in nokre that
    // emptied the sheet could not pass this by saying nothing. Not a
    // count and not a floor either any more. It was `> 5`; it was
    // retuned once when the footer stopped reserving its own space out
    // of the band's metrics, and it would have had to be retuned again
    // when the footer's own rules left with the seam. A bound that moves
    // every time a rule moves is a bound nobody trusts, and all this
    // assertion was ever asking is whether the scan found anything.
    const used = try css_check.varsUsed(gpa, shell_css);
    defer gpa.free(used);
    try std.testing.expect(used.len != 0);
}

test {
    _ = pages;
    _ = links;
    _ = icons;
    _ = css_check;
    // Every screen, and the footer under all of them. It was not on
    // this list while the footer was markup here and the builders had
    // nothing to assert about: a file whose tests nothing references is
    // a file whose tests do not run, and the suite says so by passing.
    _ = content;
    // Analysis is lazy and only the entry point references the write
    // path, so the test build would otherwise skip it. `main` itself
    // cannot be pulled in — App.Options drops the `services` default
    // under test on purpose — but the helpers past App.init can be.
    _ = &failOnStale;
    _ = &writeExtras;
    // The page shell itself, which was not on this list and should have
    // been: analysis is lazy, `writeDocument` is reached only from
    // `main`, and so the whole of what this driver hands `dom.document`
    // was invisible to `zig build test`. The revision that deleted the
    // body seam is what showed it — the pin bumped, every test passed,
    // and `zig build site` then failed on a field that no longer exists.
    _ = &writeDocument;
    // The locale axis's own half of that write path: where a copy lands,
    // where its chooser lands, and what writes the chooser.
    _ = &outPath;
    _ = &stubPath;
    _ = &writeStub;
    _ = &documentTitle;
}
