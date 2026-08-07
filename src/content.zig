//! Every screen this site has, as nokre trees.
//!
//! There is no template language here and no HTML. A page is a route
//! builder — the same signature an app's screens have — writing
//! elements through nokre's builder cursor (`app.root()`), and every
//! method is a `tree.append` checked by the same gates a real app's
//! appends go through: mandatory labels, contrast floors and ceilings,
//! structural rules. A page this file gets wrong does not render badly;
//! it fails to build. There is deliberately no helper layer between
//! these builders and the cursor — the framework's vocabulary is the
//! site's vocabulary.
//!
//! No builder here writes the page's top. The router draws it from
//! `RouteDef.title` before the builder runs, and level 1 is refused to
//! everything else (`error.HeadingAtTitleLevel`), so a screen's own
//! sections open at `h2`. Three answers to that, and each says which it
//! is: the pages whose title the nav's word already is say nothing, the
//! two whose reader-facing words differ restate with `app.setTitle`
//! (`home`, `index`), and the documentation pages stand the title down
//! altogether because their source opens with the heading it would
//! repeat (`document`).

const std = @import("std");
const nok = @import("nokre");
const opts = @import("site_options");
const links = @import("links.zig");
const pages = @import("pages.zig");

const L = @import("l10n.zig").L;
const App = nok.App;
const Cursor = nok.Cursor;
const Span = nok.Span;

/// What the builders read: the Markdown sources, loaded once, indexed
/// by page. Injected as the app's `ctx` — nokre never allocates
/// closures, so state arrives by pointer or not at all.
pub const Site = struct {
    gpa: std.mem.Allocator,
    /// One entry per `pages.all`, "" for a page that is not a document.
    sources: [][]const u8,
};

/// The route table, one entry per page. Names are validated once, in
/// `App.init`: a duplicate or a name outside the charset is an error
/// there and not a mystery at first navigation.
pub const routes = blk: {
    var defs: [pages.all.len]nok.RouteDef = undefined;
    for (pages.all, 0..) |p, i| {
        defs[i] = .{ .name = p.name, .title = .{ .of_locale = titleOf(i) }, .build = builderFor(i) };
    }
    const frozen = defs;
    break :blk frozen;
};

/// One route's title as a function of the app's locale — `Title`'s
/// other arm, and the reason the page table holds catalog keys.
///
/// `.fixed` was right while the site had one language and no axis; it
/// is wrong the moment there is a loop, because the nav roster, the
/// collapsed chip and the off-roster plate all read a title through
/// this and would keep answering in whatever language the literal was
/// written in. The tag arrives raw — `""` included, which `resolve`
/// reads as the template — so nothing here has to defend against a
/// locale nobody chose.
fn titleOf(comptime i: usize) *const fn ([]const u8) []const u8 {
    return struct {
        fn text(tag: []const u8) []const u8 {
            // `trAny` and not `tr`: the key is a value in a table, so a
            // comptime one would mean a switch with an arm per page,
            // written by hand. Same constant bytes either way.
            return L.trAny(L.resolve(tag), pages.all[i].title);
        }
    }.text;
}

fn builderFor(comptime i: usize) nok.RouteDef.Build {
    return nok.Routes(Site).builder(struct {
        fn build(site: *Site, app: *App) anyerror!void {
            return buildPage(site, app, i);
        }
    }.build);
}

fn buildPage(site: *Site, app: *App, i: usize) !void {
    try switch (pages.all[i].kind) {
        .home => home(app),
        .docs_index => index(app, .consumer),
        .internals_index => index(app, .contributor),
        .palette => palette(site, app),
        .gallery => gallery(app),
        .colophon => colophon(app),
        .not_found => notFound(app),
        .doc => document(app, i, site.sources[i]),
    };
    try footer(app);
}

/// What every page ends with: the licence, where the documents come
/// from, and the two links a reader who wants the repository or the
/// method is looking for.
///
/// **It is here rather than in the driver, and that is the change.** It
/// used to be markup the static driver spliced below the app and inside
/// the document — `Document.body_end` — and it was billed for that
/// three times over: it rendered in the browser's default serif because
/// bytes outside `.nokre` are styled by nobody, the fixed nav band
/// covered 73px of it on a phone because the clearance is padding
/// *inside* the screen, and nothing anywhere audited it or resolved its
/// one internal destination. A footer is a stack of links and a
/// sentence, which is content; the seam was the only way to opt out of
/// four things that were already true of everything in the tree
/// (`../nokre/docs/static-sites.md`, "A seam is for what does not
/// render"). Appended by the page builder, it opts back in, and nothing
/// in the library had to grant it.
///
/// One call site, at the end of `buildPage`, for the reason the header
/// has one: every page gets it, and a page that is owed it and does not
/// have it should not be possible to write. That includes the 404 body,
/// which is a screen like any other. The chooser stubs have no builder
/// and no footer — they are nokre's own document, three links and a
/// script, and a reader is on one for as long as it takes to redirect.
///
/// **The licence sentence keeps its inline link.** The prose is the
/// content: what "docs/" is is what the words around it say, and three
/// bare links in a column would be the same destinations with the
/// sentence deleted. So it is one `text` whose spans carry the link —
/// `Span.external`, because the documentation tree is on GitHub and a
/// span's other arm resolves against this app's route table. The split
/// at the link is nokre's own `Chrome.open_prefix` split, trailing
/// space and all: a runtime format string is a placeholder a translator
/// can drop or reorder, and joining costs the reordering a few
/// languages would want to buy words that cannot be wrong. The full
/// stop after the link is not in the catalog, beside the `" — nokre"` a
/// title takes — punctuation put around what the catalog said.
///
/// **No `lang` on anything here.** This site bundles one locale, so
/// every word in this stack is the document's own language, and
/// `lang=""` is not an omission in HTML — it is the claim "unknown".
/// The one place the criterion would bite is a language row naming each
/// locale in its own language, and this site does not publish one: what
/// stands at every unprefixed path is nokre's chooser, which writes its
/// own anchors and their own tags (`dom.localeStub`).
fn footer(app: *App) !void {
    const loc = L.of(app);
    const f = try app.root().stack(.{});
    // The rule the old footer drew with `border-top: var(--border) solid
    // var(--g10)` in the shell's own sheet, which is the same rule nokre
    // draws for a `divider` — so this is the site's one styling decision
    // here stated as the element that means it, rather than as CSS
    // reaching into a box the library owns.
    //
    // It is not decoration. A document page ends in a paragraph, and
    // the licence sentence is set in exactly the same face at exactly
    // the same size directly under it: without the rule a reader takes
    // "MIT licensed…" for the document's own last line, which is what
    // the small dimmed type behind a border used to prevent and what
    // moving into the tree gave up. The type is the library's to decide
    // and this is not asking for it back; the break is the site's.
    try f.divider();
    try f.spanned(&.{
        .{ .text = loc.tr(.footerLicense) },
        .{ .text = loc.tr(.footerDocsDir), .external = links.docs_dir_url },
        .{ .text = "." },
    });
    try f.link(.{ .label = loc.tr(.footerSource), .external = links.repo_url });
    // The one destination that stays on the site, so it is a route and
    // not a URL: `Refs` answers with this locale's copy of the page
    // (links.zig), the build fails if the name is not a page, and the
    // live driver resolves the same name the same way.
    try f.link(.{ .label = loc.tr(.footerColophon), .route = "colophon" });
}

/// The tile rows for a list of page names — the one loop several pages
/// share because the *data* is shared (the page table), not because the
/// syntax was heavy.
fn pageTiles(app: *App, b: Cursor, names: []const []const u8) !void {
    const loc = L.of(app);
    const group = try b.tileGroup(.{});
    for (names) |name| {
        const p = pages.find(name).?;
        try group.tile(.{
            .label = loc.trAny(p.title),
            .detail = loc.trAny(p.blurb),
            .route = p.name,
        });
    }
}

// --------------------------------------------------------------- home

fn home(app: *App) !void {
    const b = app.root();

    // The nav calls this screen "Home", which is what a roster of
    // destinations can call it and what the chip and the plate need.
    // The page is the library's own name, so it restates.
    try app.setTitle("nokre");
    try b.styled("A deliberately limited GUI library: text, lines, and boxes.", .{
        .scale = .h3,
        .ink = .mid,
    });
    try b.text("Zig and Skia, rasterized on the CPU. Grayscale only. Every element " ++
        "is semantic, so accessibility is derived from the tree you build " ++
        "rather than annotated onto it. Two devices on the same platform " ++
        "with the same logical screen size render byte-for-byte identical " ++
        "frames, run after run. Identity across platforms is not the goal: " ++
        "an app is a semantic tree, and how a device draws that tree is " ++
        "the device's business.");
    try b.styled("Think: apps for a grayscale Kindle — and, on the same tree, " ++
        "for a terminal, a watch face, a panel that refreshes one row at a time.", .{ .ink = .dark });

    try b.codeBlock(
        \\const nok = @import("nokre");
        \\
        \\fn buildHome(state: *Notes, app: *nok.App) !void {
        \\    const b = app.root();
        \\    try b.text("Everything here is accessible by construction.");
        \\    try b.button(.{
        \\        .label = "New note",
        \\        .on_press = .bind(Notes.newNote, state),
        \\    });
        \\}
    );
    try b.spanned(&.{
        .{ .text = "That is a complete, keyboard-navigable, screen-reader-complete screen. A button without a label would not have survived " },
        .{ .text = "append", .code = true },
        .{ .text = "." },
    });

    try b.divider();

    try b.heading(.h2, "The limitation is the product");
    try b.text("Every capability a UI toolkit offers is also a way to ship a broken " ++
        "app — inaccessible, inconsistent across machines, untestable without " ++
        "a screenshot farm. nokre keeps only what it can guarantee correct, " ++
        "and turns each removed capability into a promise that holds for " ++
        "every app built on it.");

    const promises = try b.stack(.{ .gap = 8 });
    try promise(promises, "Accessible by construction", "Every element is semantic — a heading is structure, a button is a " ++
        "button, a label is mandatory. The accessibility tree and the pixels " ++
        "are both projections of the same semantic tree, so accessibility " ++
        "cannot be added and cannot be omitted. What construction cannot " ++
        "verify, an automatic audit catches.");
    try promise(promises, "Deterministic to the pixel", "Same logical viewport, same bytes — across runs and machines, " ++
        "on the platform that drew them. Layout is integer math; rendering has no GPU, no " ++
        "hinting, no subpixel tricks. Screenshots are therefore tests: " ++
        "byte-exact, no tolerance, no perceptual diffing.");
    try promise(promises, "Testable end to end, headless", "nokre ships its own e2e framework, driving the real app through the " ++
        "real event pipeline — no browser driver, no window, no flakiness. " ++
        "Interactions go through the user's pipeline; assertions read the " ++
        "screen reader's snapshot.");

    try b.heading(.h2, "What nokre refuses to do");
    try b.text("Most of these are load-bearing for a promise above: remove one and " ++
        "it collapses. The rest take away a question the framework never " ++
        "needed answered.");
    const refusals = try b.list(.{});
    for ([_][]const Span{
        &.{
            .{ .text = "No hover states. ", .strong = true },
            .{ .text = "Interaction is press and release, key, focus, and one gesture. Nothing changes because a pointer floated over it: an affordance only pointer users can discover is information withheld from touch and keyboard users." },
        },
        &.{
            .{ .text = "No transitions or animation. ", .strong = true },
            .{ .text = "State changes are instant. Motion is a vestibular hazard, an untestable intermediate state, and a tax on determinism. A spinner is animation too — waiting is written in words." },
        },
        &.{
            .{ .text = "No color. ", .strong = true },
            .{ .text = "Thirteen fixed grays, five semantic aliases, two independent ramps. The whole palette is proven against WCAG contrast in unit tests — floor " },
            .{ .text = "and", .emphasis = true },
            .{ .text = " ceiling, because past a point more contrast stops buying legibility and starts costing comfort. One honest asterisk, framework-drawn: the Google sign-in button's multicolour G, a trademark whose owner refuses a gray variant. Nothing an app can reach paints in color." },
        },
        &.{
            .{ .text = "No system fonts. ", .strong = true },
            .{ .text = "Four bundled families, eleven real drawn faces, no synthesis. The moment the OS font stack participates, byte-identity across machines is gone." },
        },
        &.{
            .{ .text = "No GPU. ", .strong = true },
            .{ .text = "CPU rasterization only. No driver variance, no flicker, no capability matrix — the same bytes everywhere is only promisable when no driver is involved." },
        },
        &.{
            .{ .text = "No fractional scaling. ", .strong = true },
            .{ .text = "Layout is integer logical pixels; hidpi is an integer scale factor, so a 2× frame is exactly the 1× frame at double density." },
        },
        &.{
            .{ .text = "No custom widgets, no styling system. ", .strong = true },
            .{ .text = "The element set is closed. A styling hook is an accessibility loophole: contrast, target size and labeling can only be enforced on elements the framework owns." },
        },
        &.{
            .{ .text = "No paths. ", .strong = true },
            .{ .text = "A reference names a screen — " },
            .{ .text = "note~42", .code = true },
            .{ .text = " — and says nothing about where the screen sits, because screens do not sit anywhere." },
        },
    }) |item| {
        try (try refusals.listItem()).spanned(item);
    }
    try b.spanned(&.{
        .{ .text = "They are guarantees, not gaps: an app built on nokre " },
        .{ .text = "cannot", .emphasis = true },
        .{ .text = " have these problems, because the library cannot express them. The argument, in full, is the " },
        .{ .text = "introduction", .route = "introduction" },
        .{ .text = "." },
    });
    try b.styled("The refusals buy something quieter as well: a nokre app at rest " ++
        "costs zero CPU. No ticker, no vsync loop, no animation frames — a " ++
        "frame renders when state changes, and otherwise nothing runs.", .{ .ink = .mid });

    try b.heading(.h2, "Six platforms, full parity");
    try b.text("All five shells are working: window, input, IME, clipboard, and a " ++
        "screen reader on each. What differs at a glance is the text scaler " ++
        "and the accessibility backend.");
    const platforms = try b.table();
    for ([_][4][]const u8{
        .{ "Platform", "Shell", "Text", "Accessibility" },
        .{ "macOS", "AppKit", "CoreText", "VoiceOver via AccessKit" },
        .{ "iOS", "UIKit", "CoreText", "VoiceOver via UIAccessibility" },
        .{ "Windows", "Win32", "FreeType", "Narrator/NVDA/JAWS via AccessKit (UIA)" },
        .{ "Linux", "Wayland", "FreeType", "Orca/AT-SPI via AccessKit" },
        .{ "Android", "JNI + SurfaceView", "FreeType", "TalkBack via node provider" },
        .{ "Web", "wasm32, no shell", "the browser's", "the DOM itself — nothing to mirror" },
    }, 0..) |cells, r| {
        const row = try platforms.row(.{ .header = r == 0 });
        for (cells) |cell| try (try row.cell()).text(cell);
    }

    try b.heading(.h2, "This site is a nokre app");
    try b.spanned(&.{
        .{ .text = "Every page here — this one included — is a nokre element tree. " },
        .{ .text = "The generator builds each screen through " },
        .{ .text = "tree.append", .code = true },
        .{ .text = ", runs nokre's accessibility audit over it, and then writes the tree out as HTML instead of pixels. " },
        .{ .text = "The stylesheet's grays, type scale and metrics are read out of nokre's own source at build time. " },
        .{ .text = "What that means, and where the edition stops short, is the " },
        .{ .text = "colophon", .route = "colophon" },
        .{ .text = "." },
    });

    try b.heading(.h2, "Start here");
    try pageTiles(app, b, &.{ "introduction", "getting-started", "gallery", "palette", "docs" });
}

/// One promise card: the composition is the content of home's middle
/// section, not wrapper syntax.
fn promise(parent: Cursor, title: []const u8, body: []const u8) !void {
    const card = try parent.box(.{});
    try card.heading(.h3, title);
    try card.text(body);
}

// ------------------------------------------------------------ indexes

fn index(app: *App, track: @FieldType(pages.Page, "track")) !void {
    const b = app.root();
    // "Docs" and "Internals" are what the nav has room for; an index
    // page has room to say what its track is for, so both restate.
    if (track == .consumer) {
        try app.setTitle("Build an app");
        try b.text("Everything needed to build and ship one: the philosophy, the " ++
            "course, and one reference per surface. Each fact has exactly one " ++
            "home — these pages complement the internals track, they never " ++
            "duplicate it.");
    } else {
        try app.setTitle("Work on nokre");
        try b.text("How the promises are kept inside: the layer rules, the pixel " ++
            "contract, the five shells, and the per-service wiring. Start with " ++
            "the architecture, then the contributor checklists.");
    }

    const loc = L.of(app);
    const group = try b.tileGroup(.{});
    for (pages.all) |p| {
        if (p.track != track) continue;
        try group.tile(.{
            .label = loc.trAny(p.title),
            .detail = loc.trAny(p.blurb),
            .route = p.name,
        });
    }

    if (track == .consumer) {
        try b.heading(.h2, "Also here");
        try pageTiles(app, b, &.{ "gallery", "palette", "internals" });
    } else {
        try b.heading(.h2, "Also here");
        try pageTiles(app, b, &.{ "palette", "colophon", "docs" });
    }
}

// ---------------------------------------------------------- documents

/// One of nokre's own Markdown files, handed to the `document` element
/// exactly as an app would hand it a fetched terms-of-service: the
/// parser runs inside `append`, expands into ordinary elements, and
/// every append-time gate applies to it for free.
///
/// **These screens draw no title.** The router would draw the route's,
/// and nokre's Markdown files open with a `#` naming the file — so on
/// most of these pages the drawn heading and the source's first heading
/// are the same words, one line apart, and the copy this site could
/// remove is the drawn one. Standing it down loses no naming: the
/// localized title is still the `<title>`, still the nav's chip, still
/// the off-roster plate, and still this document's accessible name on
/// the line below. `setTitle("")` is the only way to say "none", and
/// saying it is what makes a page that opens at `h2` a stated shape
/// rather than a skipped level (nokre's routing.md, accessibility.md).
fn document(app: *App, i: usize, source: []const u8) !void {
    try app.setTitle("");
    try app.root().document(.{
        // The label is the site's and is localized; the source is
        // nokre's own Markdown and is not. That is the whole shape of a
        // documentation site on the day it grows a second language, and
        // it is stated rather than apologised for (l10n.zig).
        .label = L.of(app).trAny(pages.all[i].title),
        .source = source,
    });
}

// -------------------------------------------------------------- palette

fn palette(site: *Site, app: *App) !void {
    const gpa = site.gpa;
    const b = app.root();
    const Gray = nok.Gray;

    try b.text("Thirteen steps, two ramps, six type scales. A step is a semantic " ++
        "position rather than a byte: each appearance supplies its own ramp, " ++
        "and the dark one is deliberately not the light one reversed. " ++
        "Everything on this page is read out of nokre's source at build " ++
        "time, so it cannot drift from the library.");

    try b.heading(.h2, "The ramps");
    // Thirteen filled boxes in a row. A box is the only element that
    // paints a ground, so a swatch is a box — there is no swatch
    // element and there is not going to be one.
    const strip = try b.stack(.{ .axis = .horizontal, .gap = 4 });
    inline for (@typeInfo(Gray).@"enum".fields) |f| {
        const g: Gray = @enumFromInt(f.value);
        _ = try strip.box(.{ .fill = g, .border = false, .padding = 18 });
    }
    try b.styled("g0 on the left through g12 on the right, in whichever appearance you are reading this in. The dark ramp descends where the light one climbs — that descent is the inversion, which is why no draw site inverts anything. There is no theme switch here because there is none in nokre: both follow the system.", .{
        .scale = .small,
        .ink = .mid,
    });

    var rows: std.ArrayList([]const []const u8) = .empty;
    try rows.append(gpa, &.{ "Step", "Light", "Dark", "On paper (light)", "On paper (dark)" });
    inline for (@typeInfo(Gray).@"enum".fields) |f| {
        const g: Gray = @enumFromInt(f.value);
        // Duped: the literal's cells are runtime values, so the row
        // array itself is an iteration-scoped temporary — a pointer to
        // it would be dangling by the time the table reads it.
        try rows.append(gpa, try gpa.dupe([]const u8, &.{
            f.name,
            try std.fmt.allocPrint(gpa, "0x{X:0>2}", .{g.byte(.light)}),
            try std.fmt.allocPrint(gpa, "0x{X:0>2}", .{g.byte(.dark)}),
            try std.fmt.allocPrint(gpa, "{d:.1}:1", .{g.contrastWith(.paper, .light)}),
            try std.fmt.allocPrint(gpa, "{d:.1}:1", .{g.contrastWith(.paper, .dark)}),
        }));
    }
    const ramp_table = try b.table();
    for (rows.items, 0..) |cells, r| {
        const row = try ramp_table.row(.{ .header = r == 0 });
        for (cells) |cell| try (try row.cell()).text(cell);
    }

    try b.heading(.h2, "The five aliases");
    try b.text("You will mostly use these. They sit where WCAG compliance holds by " ++
        "construction, in both appearances.");
    const alias_table = try b.table();
    for ([_][3][]const u8{
        .{ "Alias", "Step", "Use" },
        .{ "ink", "g2", "Body text. 14.2:1 on paper in light, 10.6:1 in dark — not the 21:1 true black would give, because past a point contrast stops buying legibility and starts costing comfort." },
        .{ "dark", "g3", "Secondary text that still has to read as text (AAA)." },
        .{ "mid", "g5", "Dimmed text: labels, details, captions (AA body)." },
        .{ "light", "g9", "Boundaries and separators that carry no state." },
        .{ "paper", "g12", "The page." },
    }, 0..) |cells, r| {
        const row = try alias_table.row(.{ .header = r == 0 });
        for (cells) |cell| try (try row.cell()).text(cell);
    }

    try b.heading(.h2, "The type scale");
    try b.text("Fixed. Six sizes, and every heading level maps onto one of them.");
    inline for (@typeInfo(nok.text.Scale).@"enum".fields) |f| {
        const s: nok.text.Scale = @enumFromInt(f.value);
        const label = try std.fmt.allocPrint(gpa, "{s} — {d}px on {d}px", .{ f.name, s.px(), s.lineHeight() });
        try b.styled(label, .{ .scale = s });
    }

    try b.heading(.h2, "Both families");
    try b.styled("prose — IBM Plex Sans, four faces. Body copy, labels, headings.", .{});
    try b.styled("mono — JetBrains Mono, four faces. Code, verbatim values, anything whose columns mean something.", .{ .family = .mono });
    try b.styled("A fifth face carries the Arabic script — سلام دنیا — so Persian and Arabic render in one voice whatever family was asked for.", .{});

    try b.heading(.h2, "Where this comes from");
    try b.spanned(&.{
        .{ .text = "The bytes, the ratios and the reasoning are " },
        .{ .text = "the pixel model", .route = "internals.pixel-model" },
        .{ .text = ". The palette itself is " },
        .{ .text = "src/core/color.zig", .route = "../src/core/color.zig" },
        .{ .text = ", where a ramp byte that breaks compliance — in either direction, in either appearance — fails the build." },
    });
}

// -------------------------------------------------------------- gallery

fn gallery(app: *App) !void {
    const b = app.root();

    try b.text("The complete, closed set. Every element carries its semantics with " ++
        "it — role, label and state are intrinsic, which is why " ++
        "accessibility can be derived rather than annotated. There is no " ++
        "styling API: if an element does not do what you want, the answer is " ++
        "a different composition of these, not a customization hook.");
    const note = try b.box(.{});
    try note.styled("The controls below are specimens. They are drawn the way nokre " ++
        "draws them and they take focus the way nokre does; the ones with " ++
        "state — checkbox, toggle, radio, select, fields — really do change " ++
        "it, because a browser gives that for free. The buttons call " ++
        "nothing: on this edition there is no app behind them.", .{ .ink = .mid, .scale = .small });

    // ---- static ----
    try b.heading(.h2, "Static");

    try b.heading(.h3, "text");
    try b.text("Body copy. Wraps greedily at word boundaries within the parent width.");
    try b.spanned(&.{
        .{ .text = "Inline structure comes from spans — Markdown's inline vocabulary: " },
        .{ .text = "strong", .strong = true },
        .{ .text = ", " },
        .{ .text = "emphasis", .emphasis = true },
        .{ .text = ", " },
        .{ .text = "code", .code = true },
        .{ .text = ", " },
        .{ .text = "strike", .strike = true },
        .{ .text = ", and " },
        .{ .text = "an inline link", .route = "elements" },
        .{ .text = ", which is a control and therefore its own tab stop." },
    });

    try b.heading(.h3, "heading");
    try b.text("h2 through h6, mapped to fixed sizes. Level 1 is the page's title — stated at the route table and drawn by the library, which is the heading at the top of this page — so a builder cannot write one. Headings are structure, not styling — the audit fails a skipped level. Every level draws bold, which is what keeps h5 and h6 reading as headings beside the prose they share a size with.");

    try b.heading(.h3, "icon");
    const icons = try b.stack(.{ .axis = .horizontal, .gap = 8 });
    try icons.icon(.{ .name = .shapes, .label = "Shapes" });
    try icons.icon(.{ .name = .ruler, .label = "Ruler" });
    try icons.icon(.{ .name = .accessibility, .label = "Accessibility" });
    try icons.icon(.{ .name = .flask_conical, .label = "Flask" });
    try icons.icon(.{ .name = .globe, .ink = .mid });
    try b.styled("One named Lucide glyph, laid out as a square line-height box. An empty label means decorative, and decorative means hidden from assistive tech; a named one is announced and must clear the same contrast gate as text.", .{ .ink = .mid, .scale = .small });

    try b.heading(.h3, "divider");
    try b.divider();

    try b.heading(.h3, "badge");
    const badges = try b.stack(.{ .axis = .horizontal, .gap = 8 });
    try badges.badge(.{ .label = "Active" });
    try badges.badge(.{ .label = "Owner" });
    try badges.badge(.{ .label = "3 pending" });
    try b.styled("Where color-coded chips carry state by hue elsewhere, here the words carry it.", .{ .ink = .mid, .scale = .small });

    try b.heading(.h3, "meter");
    try b.meter(.{ .label = "12 of 30 days", .value = 12, .max = 30 });
    try b.styled("The label is mandatory and is what assistive tech hears; the fill only restates it. Never animated — for indeterminate waiting, write \"Loading…\" as text.", .{ .ink = .mid, .scale = .small });

    try b.heading(.h3, "qr");
    try b.qr(.{
        .label = "This site",
        .value = "https://getnokre.github.io",
    });

    // ---- containers ----
    try b.heading(.h2, "Containers");

    try b.heading(.h3, "stack");
    try b.text("Vertical or horizontal flow, with a gap and a padding. The tree root is a vertical stack.");

    try b.heading(.h3, "box");
    const outer = try b.box(.{});
    try outer.text("Grouping container: an optional 1px border, a padding, an optional fill. Boxes group; they do not decorate.");
    const inner = try outer.box(.{ .fill = .g11 });
    try inner.text("A box's edge is a wall: the margin advice stops at it, so nothing ever bleeds across a border.");

    try b.heading(.h3, "scroll_region");
    const region = try b.scrollRegion(.{ .height = 120 });
    try region.text("A viewport over vertically flowing children, clipped, with a 2px indicator reflecting the offset.");
    try region.text("The bar has two tones, switched by state and never by time: emphasized while its surface is engaged, quiet at rest.");
    try region.text("At rest the primary \"more is there\" affordance is the content itself, cut mid-element at the viewport edge — which is why the audit fails a fixed-height region whose top edge cuts nothing visible.");

    // ---- interactive ----
    try b.heading(.h2, "Interactive");
    try b.spanned(&.{
        .{ .text = "Every interactive element requires a label. ", .strong = true },
        .{ .text = "That is not a convention and not a lint: " },
        .{ .text = "tree.append", .code = true },
        .{ .text = " refuses to construct an interactive element with an empty one. An inaccessible control cannot exist." },
    });

    try b.heading(.h3, "button");
    const buttons = try b.stack(.{ .axis = .horizontal, .gap = 8 });
    try buttons.button(.{ .label = "New note" });
    try buttons.button(.{ .label = "Cancel", .form = .{ .secondary = null } });
    try buttons.button(.{ .label = "Delete", .disabled = true });

    try b.heading(.h3, "link");
    try b.link(.{ .label = "The routing contract", .route = "routing" });

    try b.heading(.h3, "toggle");
    try b.toggle(.{ .label = "Sync over cellular", .on = true });

    try b.heading(.h3, "checkbox");
    try b.checkbox(.{ .label = "Remember this device", .checked = true });
    try b.checkbox(.{ .label = "Send crash reports" });

    try b.heading(.h3, "radio_group");
    try b.radioGroup(.{
        .label = "Export format",
        .options = &.{ "Markdown", "Plain text", "HTML" },
        .selected = 0,
    });

    try b.heading(.h3, "segmented");
    try b.segmented(.{
        .label = "View",
        .options = &.{ "All", "Starred", "Archived" },
        .selected = 1,
    });
    try b.styled("An exclusive choice among 2+ fixed options — radiogroup semantics, not tabs. There is deliberately no tablist element: nokre rebuilds subtrees instantly, so co-existing tab panels never exist and tablist semantics would be a lie.", .{ .ink = .mid, .scale = .small });

    try b.heading(.h3, "select");
    try b.select(.{
        .label = "Sort by",
        .options = &.{ "Recently edited", "Recently created", "Title" },
        .selected = 0,
    });

    try b.heading(.h3, "text_input");
    try b.textInput(.{ .label = "Title", .value = "Grocery list" });

    try b.heading(.h3, "text_area");
    try b.textArea(.{
        .label = "Note",
        .placeholder = "Whitespace is preserved; the field grows to three lines and then scrolls.",
    });

    try b.heading(.h3, "copyable");
    try b.copyable(.{
        .label = "Recovery code",
        .value = "K7QM-2XPD-9ATV-6BLR",
    });
    try b.styled("Activation is intrinsic — it writes the value to the platform clipboard. There is no action to wire, so it cannot be miswired.", .{ .ink = .mid, .scale = .small });

    try b.heading(.h3, "tile_group and tile");
    const group = try b.tileGroup(.{
        .description = "Reach for tiles where a screen is a list of destinations or row-shaped actions.",
    });
    try group.tile(.{
        .label = "Accessibility",
        .detail = "Derivation, enforcement, the audit",
        .route = "accessibility",
    });
    try group.tile(.{
        .label = "Testing",
        .detail = "Harness, queries, golden screenshots",
        .route = "testing",
    });

    try b.heading(.h3, "list and list_item");
    const facts = try b.list(.{});
    for ([_][]const u8{
        "Markers are derived, never authored — so a list can never number itself wrongly.",
        "A list_item holds document blocks: text and nested lists, not arbitrary content.",
        "Nesting is capped at three levels, at append. Past that the indent has eaten the line without saying anything the words do not.",
    }) |line| {
        try (try facts.listItem()).text(line);
    }

    try b.heading(.h3, "blockquote");
    const quote = try b.blockquote();
    try quote.text("The attribution is words inside the quote, not a field on it: a quote whose source only a border implies is a quote whose source nobody hears.");
    try quote.styled("— docs/elements.md", .{ .ink = .mid, .scale = .small });

    try b.heading(.h3, "code_block");
    try b.codeBlock(
        \\// Whitespace preserved, never reflowed: a wrapped code line
        \\// lies about where the code breaks.
        \\const focus = metrics.focus_stroke; // 2
    );

    try b.heading(.h3, "table, row and cell");
    const rules = try b.table();
    for ([_][2][]const u8{
        .{ "Element", "Children must be" },
        .{ "table", "row" },
        .{ "row", "cell" },
        .{ "cell", "anything" },
    }, 0..) |cells, r| {
        const row = try rules.row(.{ .header = r == 0 });
        for (cells) |cell| try (try row.cell()).text(cell);
    }

    // ---- chrome ----
    try b.heading(.h2, "Navigation chrome");
    try b.spanned(&.{
        .{ .text = "The bar at the bottom of this page is a " },
        .{ .text = "nav", .code = true },
        .{ .text = ": a closed roster of destinations, installed once and preserved across every router rebuild. It carries no labels of its own — what a screen is called is its route's title, declared once at the route table, so the nav and the screen cannot disagree. This screen is none of the destinations, so it names itself with the trailing " },
        .{ .text = "nav_here", .code = true },
        .{ .text = " plate, which is a label and not a link." },
    });

    try b.heading(.h2, "Layers");
    try b.spanned(&.{
        .{ .text = "A " },
        .{ .text = "sheet", .code = true },
        .{ .text = ", a " },
        .{ .text = "notice", .code = true },
        .{ .text = " and the select picker are opened by an event — a press, an arrival, a change. This edition has no events, so they cannot appear here. They are specified in " },
        .{ .text = "elements.md", .route = "elements" },
        .{ .text = "." },
    });
}

// ------------------------------------------------------------- colophon

fn colophon(app: *App) !void {
    const b = app.root();

    try b.text("This site is a nokre app that renders to HTML. Not a site about " ++
        "nokre with a nokre-ish stylesheet: every page is a real element " ++
        "tree, built by a route builder with the same signature an app's " ++
        "screens have, checked by the same gates, and audited by the same " ++
        "audit before a byte of markup is written.");

    try b.heading(.h2, "How a page is made");
    const steps = try b.list(.{ .ordered = true });
    for ([_][]const u8{
        "One App is constructed with a route table of every page on this site. Duplicate or malformed route names fail there, in App.init, rather than at first navigation.",
        "The generator switches to each route in turn — switchTo, the motion the web shell uses for an inbound link, which is exactly what a visitor arriving at a static page has.",
        "The route's builder appends elements. Documentation pages append one document element holding nokre's own Markdown, which the parser expands into ordinary elements inside append.",
        "nokre's accessibility audit runs over the finished screen. A skipped heading level, an unlabeled control, two controls sharing a label, a contrast pair outside the floor or the ceiling — any of them fails the build.",
        "The tree is walked once more and written out as HTML: the same walk render/renderer.zig makes, with markup where it has draw calls.",
    }) |body| {
        try (try steps.listItem()).text(body);
    }

    try b.text("There is no build server. The generator runs on a laptop and its " ++
        "output is committed, so the bytes a reader is served are the bytes " ++
        "somebody reviewed in a diff — which is the same argument nokre " ++
        "makes for golden screenshots, one layer out. Two runs over " ++
        "unchanged sources produce identical files, so a diff that is empty " ++
        "means nothing changed rather than nothing was checked.");

    // The stamp below is what lets that argument be checked rather than
    // taken on faith: build.zig asks each checkout for `rev-parse
    // --short HEAD` and `status --porcelain` at generation time, and
    // the answers are compiled into this sentence. It makes the output
    // depend on checkout *state*, which is the point — provenance — and
    // costs the paragraph above nothing: a rebuild on the same two
    // clean commits is still byte-identical, so the empty-diff property
    // survives the stamp. The two clauses wear different words because
    // they know different things. The nokre clause can name the exact
    // sources — that checkout is only read — so a dirty tree there is a
    // real finding and gets the admission. The site's own clause can
    // never name the commit it lands in: the hash is HEAD as of the
    // build, the publishing commit does not exist yet, and the tree is
    // dirty at rebuild time by construction (the rebuild is what
    // dirties it). An admission that is always true says nothing, so
    // this clause says the honest smaller thing — the output was built
    // atop that commit — and no more.
    const provenance = comptime prov: {
        const lead: []const Span =
            &.{.{ .text = "And which sources those were is stamped rather than assumed: " ++
            "this page was generated from nokre at " }};
        const mid: []const Span = &.{.{ .text = " and built atop " }};
        const site_clause: []const Span = &.{.{ .text = opts.site_rev, .code = true }};
        const tail: []const Span = &.{.{ .text = " of this repository." }};
        break :prov lead ++ stamp(opts.nokre_rev, opts.nokre_dirty) ++
            mid ++ site_clause ++ tail;
    };
    try b.spanned(provenance);

    try b.heading(.h2, "The door was left open on purpose");
    const quote = try b.blockquote();
    try quote.text("A renderer is an interpretation of the semantic tree, the way a " ++
        "browser interprets HTML. It may draw each element however it likes, " ++
        "with capabilities the Skia edition refuses, so long as the semantics " ++
        "— element set, behavior, focus model, a11y tree — are conveyed " ++
        "faithfully.");
    try quote.spanned(&.{ .{ .text = "— " }, .{ .text = "internals/renderer-editions.md", .route = "internals.renderer-editions" } });
    try b.text("That document splits the guarantees in two. Grayscale, CPU raster, " ++
        "pixel determinism and byte-exact goldens belong to the Skia edition. " ++
        "The semantic tree, event behavior, focus traversal, the accessibility " ++
        "snapshot and the validate/audit rules live on the tree, so they hold " ++
        "whatever renders it. This edition keeps the second list whole.");

    try b.heading(.h2, "What this edition keeps");
    const kept = try b.list(.{});
    for ([_][]const Span{
        &.{
            .{ .text = "The closed set. ", .strong = true },
            .{ .text = "Every element has exactly one case in the writer. An element with no case is a compile error, not a div — which is the same discipline that makes the set closed in the first place." },
        },
        &.{
            .{ .text = "The semantics. ", .strong = true },
            .{ .text = "Roles, labels, states and focus order come from the tree, not from markup written by hand. A tile with a route is a link; a tile with an action is a button; the nav's own current entry is a label and not a destination, because it goes where you already are." },
        },
        &.{
            .{ .text = "The design system, to the byte. ", .strong = true },
            .{ .text = "The stylesheet is generated: thirteen grays in two ramps out of core/color.zig, six type scales out of core/text.zig, and every padding, radius, target and stroke out of core/layout.zig. Nothing is transcribed, so nothing can drift." },
        },
        &.{
            .{ .text = "The faces. ", .strong = true },
            .{ .text = "The same IBM Plex Sans, JetBrains Mono, Lucide and Vazirmatn binaries nokre bundles, subset to what this site draws. There is no font stack in the stylesheet, because nokre has no font stack." },
        },
        &.{
            .{ .text = "The refusals. ", .strong = true },
            .{ .text = "No animation, no transition, no hover rule anywhere in the stylesheet, no color, and no theme switch — the appearance follows the system, which is the whole of nokre's appearance API." },
        },
    }) |item| {
        try (try kept.listItem()).spanned(item);
    }

    try b.heading(.h2, "The file is the first frame");
    try b.text("A generated page is a screen measured with a ruler that is not " ++
        "yours. A build has no font metrics and no window, so the stand-in " ++
        "measurer answers every measured question against 1280 pixels: " ++
        "where prose wraps, whether a row of actions has to give up its " ++
        "tail, whether the nav roster fits on one line. On a phone each of " ++
        "those answers is about a screen nobody is looking at.");
    try b.text("So the page ships with the app that made it. The same wasm module " ++
        "on every screen, the same route table, the same builders — it " ++
        "boots, measures the column you actually have, and retakes those " ++
        "decisions. The roster that could not fit collapses into a section " ++
        "chip, which is what nokre does on every other platform and what " ++
        "the file alone could never do.");
    try b.text("It is an upgrade and not a requirement, which is the whole reason " ++
        "the pair exists. Nothing on this site waits for it: the markup is " ++
        "complete before a byte of script arrives, the links are real " ++
        "links, and a reader with JavaScript off gets the 1280-pixel " ++
        "reading of the page rather than an empty one. Navigation stays " ++
        "the browser's for the same reason — every screen here is a file " ++
        "with a URL of its own, so a link is something to follow rather " ++
        "than something to intercept.");

    try b.heading(.h2, "Where it stops short, exactly");
    try b.text("Two places. Each is the web being the web, and each is a decision " ++
        "rather than an oversight.");
    const stops = try b.list(.{});
    for ([_][]const Span{
        &.{
            .{ .text = "Lines wrap where the browser wraps them. ", .strong = true },
            .{ .text = "Layout is computed and then ignored. Pixel determinism is the Skia edition's promise, not this one's, and a page that fixed its line breaks would break the first reader who changed their text size." },
        },
        &.{
            .{ .text = "There are external links. ", .strong = true },
            .{ .text = "nokre navigates its own screens and nothing else. A page that cites a source file has to leave the app, so those links carry an arrow and say so. They are the only ones on the site that do." },
        },
    }) |item| {
        try (try stops.listItem()).spanned(item);
    }

    try b.heading(.h2, "What it costs the reader");
    // No header row: nokre's row is only a header when marked, and
    // empty header strings would emit empty `<th>`s a screen reader
    // associates every cell with.
    const costs = try b.table();
    for ([_][2][]const u8{
        .{ "JavaScript", "nokre's own live driver and nothing else. No framework, no dependency, no analytics, no cookies." },
        .{ "Before it runs", "The whole page. Content, links, chrome — the script changes what is measured, not what is there." },
        .{ "With it off", "The same page, wrapped for a 1280-pixel window." },
        .{ "Requests", "One document, one stylesheet, one favicon, the faces the page uses, the live driver, the services module it imports, the service worker it registers, one wasm module, and — on a documentation page — its Markdown." },
        .{ "Trackers, cookies, consent", "None, so no banner asking about any." },
        .{ "Appearance", "Follows the system, both ramps generated." },
        .{ "Print", "Chrome drops out; the content is the page." },
    }) |cells| {
        const row = try costs.row(.{});
        for (cells) |cell| try (try row.cell()).text(cell);
    }

    try b.heading(.h2, "Sources");
    try b.text("Documentation pages are nokre's own Markdown, rendered by nokre's " ++
        "own parser — not a copy, and not a second parser. Every internal " ++
        "link in them is a route reference, resolved at build time against " ++
        "the route table; one that names a page this site does not publish " ++
        "fails the build the way error.UnknownRoute fails an app.");
    try b.text("Which also means the subset is the subset. Where a document reaches " ++
        "for something the parser does not cover, it comes through as its " ++
        "own source text, markers and all — that is the rule that makes " ++
        "parsing bytes nobody reviewed safe, and it is exactly what a nokre " ++
        "app would put on screen. Nothing here quietly cleans it up first.");
    try pageTiles(app, b, &.{ "internals.renderer-editions", "internals.pixel-model", "markdown" });
}

// ------------------------------------------------------------ not found

/// The one screen this file builds by hand whose words are in the
/// catalog. Every other hand-built screen here is prose — an argument,
/// a gallery, a colophon — and prose is content, which this site keeps
/// where the Markdown beside it is kept: in one language. A 404 body is
/// not prose. It is the sentence a reader gets when they have arrived
/// from anywhere at all, which is the one place a language they cannot
/// read is a dead end rather than a page they can skip.
fn notFound(app: *App) !void {
    const b = app.root();
    const loc = L.of(app);
    try b.spanned(&.{
        .{ .text = loc.tr(.notFoundLead) },
        // Not a message: `error.UnknownRoute` is an identifier out of
        // nokre's own source, which is the same in every language and
        // is drawn as code for exactly that reason.
        .{ .text = "error.UnknownRoute", .code = true },
        .{ .text = loc.tr(.notFoundTail) },
    });
    try pageTiles(app, b, &.{ "home", "docs", "internals" });
}

/// One checkout's clause in the provenance sentence: the short hash,
/// and — when the build read a working tree holding more than the
/// commit — the admission, in words. Words rather than a `-dirty`
/// suffix, because the sentence is prose and its reader need not be a
/// git user to be owed the fact.
fn stamp(comptime rev: []const u8, comptime dirty: bool) []const Span {
    return if (dirty)
        &.{ .{ .text = rev, .code = true }, .{ .text = " (with uncommitted changes)" } }
    else
        &.{.{ .text = rev, .code = true }};
}

// ------------------------------------------------------------- tests

const dom = nok.render.dom;
const testing = std.testing;

/// One built screen as markup, resolved the way the generator resolves
/// it. The site's `Refs` and not the edition's default, because half of
/// what these tests are about is that the footer's internal destination
/// goes through the route table at build time — the default would
/// answer `#colophon` and pass an assertion about a link to nowhere.
///
/// Everything is on one arena and nothing is freed: `Resolver` hands
/// back slices of intermediate joins, which is the shape the generator
/// itself runs in (links.zig's own tests say it the same way).
fn renderPage(arena: std.mem.Allocator, name: []const u8) ![]const u8 {
    var sources: [pages.all.len][]const u8 = @splat("");
    var site: Site = .{ .gpa = arena, .sources = &sources };
    var app = try nok.App.init(testing.allocator, .{
        .viewport = .{ .w = 900, .h = 600 },
        .routes = &routes,
        .ctx = &site,
        .services = .mocks(),
    });
    defer app.deinit();
    try app.switchTo(name);

    var seen: std.ArrayList(links.Seen) = .empty;
    var resolver: links.Resolver = .{ .gpa = arena, .seen = &seen };
    var out: std.ArrayList(u8) = .empty;
    var em: dom.Emitter = .{
        .gpa = arena,
        .app = &app,
        .out = &out,
        .options = .{ .refs = resolver.refs() },
    };
    defer em.deinit();
    try dom.content(&em);
    return out.items;
}

test "the licence sentence keeps its link inside the prose" {
    // The one thing about this footer that a stack of links cannot say.
    // What `docs/` *is* is what the words on either side of it say, so
    // the sentence is one text whose spans carry the destination — and
    // flattening it into a fourth bare link, which is the shape the
    // library's own description of a footer suggests, would publish the
    // three destinations with the sentence deleted.
    //
    // The full stop is outside the anchor and the space before it is
    // inside the catalog's own message (`footerLicense`, trailing space,
    // nokre's `Chrome.open_prefix` split). Both are spellings a joiner
    // gets wrong silently, and both read as a typo rather than a bug.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderPage(arena.allocator(), "colophon");
    try testing.expect(std.mem.indexOf(u8, html, "<p>MIT licensed. Documentation rendered from the repository at " ++
        "<a class=\"link\" href=\"https://github.com/getnokre/nokre/tree/main/docs\"" ++
        " target=\"_blank\" rel=\"noopener noreferrer\"") != null);
    try testing.expect(std.mem.indexOf(u8, html, ">docs/</a>.</p>") != null);
}

test "the footer's outbound links are external and its own page is a route" {
    // The three destinations, each said the way its kind is said. The
    // two that leave carry the pair nokre writes for `.external` — this
    // site used to write those bytes itself, and the footer was the last
    // place it did (links.zig) — and the one that does not leave is a
    // route name, resolved against the table by `Refs` into this
    // locale's copy of the page. A literal `/colophon/` would have been
    // the pre-axis address, which is a chooser now and not the page.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderPage(arena.allocator(), "gallery");
    try testing.expect(std.mem.indexOf(u8, html, "<a class=\"link block\" href=\"https://github.com/getnokre/nokre\"" ++
        " target=\"_blank\" rel=\"noopener noreferrer\"") != null);
    try testing.expect(std.mem.indexOf(u8, html, "Source on GitHub</a>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "href=\"/en/colophon/\"") != null);
    // One locale, so nothing here is in another language and nothing
    // says it is: `lang=""` is the claim "unknown", not silence.
    try testing.expect(std.mem.indexOf(u8, html, "lang=") == null);
}

test "every screen ends with the footer, the 404 body included" {
    // One call site at the end of `buildPage` is what makes this true of
    // a page nobody remembered — which is the half the seam could not
    // do, since a driver that forgot a page simply wrote it without one.
    // The 404 body is the page that proves it: it is a screen like any
    // other and is reached from anywhere at all.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for (pages.all) |p| {
        const html = try renderPage(arena.allocator(), p.name);
        const mark = std.mem.indexOf(u8, html, "How this site is built") orelse {
            std.debug.print("no footer on page \"{s}\"\n", .{p.name});
            return error.TestUnexpectedResult;
        };
        // Last, and nothing after it but the closing tags the emitter
        // owes: a footer appended before the screen's own content would
        // still be *present* and would still be wrong.
        try testing.expect(std.mem.indexOf(u8, html[mark..], "<hr>") == null);
        try testing.expectEqualStrings("</a></div>", html[html.len - "</a></div>".len ..]);
    }
}

test "the footer is a stack, not a landmark this edition has no element for" {
    // nokre serializes a `stack` as a `div` and has no `<footer>` — that
    // call is measured in `../nokre/docs/static-sites.md` ("The
    // `contentinfo` landmark is the loss, and it is a small one"), and
    // this site satisfies 2.4.1 twice over without it: the skip link
    // `dom.document` writes, and the roster as a `nav` landmark ahead of
    // the content. What this pins is that nothing here reintroduces the
    // tag by hand, which is what the seam made possible.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const html = try renderPage(arena.allocator(), "home");
    try testing.expect(std.mem.indexOf(u8, html, "<footer") == null);
    try testing.expect(std.mem.indexOf(u8, html, "contentinfo") == null);
}
