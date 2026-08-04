//! Every screen this site has, as nokre trees.
//!
//! There is no template language here and no HTML. A page is a route
//! builder — the same signature an app's screens have — appending
//! elements to `app.tree`, and every append is checked by the same
//! gates a real app's appends go through: mandatory labels, contrast
//! floors and ceilings, structural rules. A page this file gets wrong
//! does not render badly; it fails to build.

const std = @import("std");
const nok = @import("nokre");
const opts = @import("site_options");
const pages = @import("pages.zig");

const App = nok.App;
const NodeId = nok.NodeId;

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
        defs[i] = .{ .name = p.name, .title = p.title, .build = builderFor(i) };
    }
    const frozen = defs;
    break :blk frozen;
};

fn builderFor(comptime i: usize) *const fn (?*anyopaque, *App) anyerror!void {
    return struct {
        fn build(ctx: ?*anyopaque, app: *App) anyerror!void {
            const site: *Site = @ptrCast(@alignCast(ctx.?));
            return buildPage(site, app, i);
        }
    }.build;
}

fn buildPage(site: *Site, app: *App, i: usize) !void {
    return switch (pages.all[i].kind) {
        .home => home(app),
        .docs_index => index(app, .consumer),
        .internals_index => index(app, .contributor),
        .palette => palette(site, app),
        .gallery => gallery(app),
        .colophon => colophon(app),
        .not_found => notFound(app),
        .doc => document(app, i, site.sources[i]),
    };
}

// ------------------------------------------------------------ helpers

fn text(app: *App, parent: NodeId, content: []const u8) !void {
    try app.tree.append(parent, .{ .text = .{ .content = content } });
}

fn styled(app: *App, parent: NodeId, content: []const u8, style: nok.text.Style) !void {
    try app.tree.append(parent, .{ .text = .{ .content = content, .style = style } });
}

fn spanned(app: *App, parent: NodeId, spans: []const nok.element.Span) !void {
    try app.tree.append(parent, .{ .text = .{ .spans = spans } });
}

fn heading(app: *App, parent: NodeId, level: nok.element.HeadingLevel, content: []const u8) !void {
    try app.tree.append(parent, .{ .heading = .{ .content = content, .level = level } });
}

fn code(app: *App, parent: NodeId, content: []const u8) !void {
    try app.tree.append(parent, .{ .code_block = .{ .content = content } });
}

fn divider(app: *App, parent: NodeId) !void {
    try app.tree.append(parent, .{ .divider = .{} });
}

fn bullets(app: *App, parent: NodeId, items: []const []const nok.element.Span) !void {
    const list = try app.tree.appendId(parent, .{ .list = .{} });
    for (items) |item| {
        const li = try app.tree.appendId(list, .{ .list_item = .{} });
        try app.tree.append(li, .{ .text = .{ .spans = item } });
    }
}

/// Markdown's inline vocabulary, spelled out. `spans` is not a styling
/// hook — a span may restate emphasis the words already carry, never be
/// information's only carrier — so these are deliberately thin.
fn plain(s: []const u8) nok.element.Span {
    return .{ .text = s };
}
fn strong(s: []const u8) nok.element.Span {
    return .{ .text = s, .strong = true };
}
fn mono(s: []const u8) nok.element.Span {
    return .{ .text = s, .code = true };
}
fn linkTo(s: []const u8, route: []const u8) nok.element.Span {
    return .{ .text = s, .route = route };
}

fn tiles(app: *App, parent: NodeId, names: []const []const u8) !void {
    const group = try app.tree.appendId(parent, .{ .tile_group = .{} });
    for (names) |name| {
        const p = pages.find(name).?;
        try app.tree.append(group, .{ .tile = .{
            .label = p.title,
            .detail = p.blurb,
            .route = p.name,
        } });
    }
}

fn tableOf(app: *App, parent: NodeId, rows: []const []const []const u8) !void {
    const table = try app.tree.appendId(parent, .{ .table = .{} });
    for (rows, 0..) |cells, r| {
        try tableRow(app, table, cells, r == 0);
    }
}

/// A table whose columns need no names. nokre's row is only a header
/// when marked (`.header = true`), so the case is expressed by never
/// marking one — passing empty header strings instead would emit empty
/// `<th>`s, and a screen reader associates every cell with a header
/// that says nothing.
fn headerlessTableOf(app: *App, parent: NodeId, rows: []const []const []const u8) !void {
    const table = try app.tree.appendId(parent, .{ .table = .{} });
    for (rows) |cells| {
        try tableRow(app, table, cells, false);
    }
}

fn tableRow(app: *App, table: NodeId, cells: []const []const u8, header: bool) !void {
    const row = try app.tree.appendId(table, .{ .row = .{ .header = header } });
    for (cells) |c| {
        const cell = try app.tree.appendId(row, .{ .cell = .{} });
        try app.tree.append(cell, .{ .text = .{ .content = c } });
    }
}

// --------------------------------------------------------------- home

fn home(app: *App) !void {
    const root = app.tree.rootId();

    try heading(app, root, .h1, "nokre");
    try styled(app, root, "A deliberately limited GUI library: text, lines, and boxes.", .{
        .scale = .h3,
        .ink = .mid,
    });
    try text(app, root, "Zig and Skia, rasterized on the CPU. Grayscale only. Every element " ++
        "is semantic, so accessibility is derived from the tree you build " ++
        "rather than annotated onto it. Two devices on the same platform " ++
        "with the same logical screen size render byte-for-byte identical " ++
        "frames, run after run. Identity across platforms is not the goal: " ++
        "an app is a semantic tree, and how a device draws that tree is " ++
        "the device's business.");
    try styled(app, root, "Think: apps for a grayscale Kindle — and, on the same tree, " ++
        "for a terminal, a watch face, a panel that refreshes one row at a time.", .{ .ink = .dark });

    try code(app, root,
        \\const nok = @import("nokre");
        \\
        \\fn buildHome(_: ?*anyopaque, app: *nok.App) !void {
        \\    const root = app.tree.rootId();
        \\    try app.tree.append(root, .{ .heading = .{
        \\        .content = "Notes",
        \\        .level = .h1,
        \\    } });
        \\    try app.tree.append(root, .{ .text = .{
        \\        .content = "Everything here is accessible by construction.",
        \\    } });
        \\    try app.tree.append(root, .{ .button = .{
        \\        .label = "New note",
        \\        .on_press = .{ .call = onNewNote },
        \\    } });
        \\}
    );
    try spanned(app, root, &.{
        plain("That is a complete, keyboard-navigable, screen-reader-complete screen. A button without a label would not have survived "),
        mono("append"),
        plain("."),
    });

    try divider(app, root);

    try heading(app, root, .h2, "The limitation is the product");
    try text(app, root, "Every capability a UI toolkit offers is also a way to ship a broken " ++
        "app — inaccessible, inconsistent across machines, untestable without " ++
        "a screenshot farm. nokre keeps only what it can guarantee correct, " ++
        "and turns each removed capability into a promise that holds for " ++
        "every app built on it.");

    const promises = try app.tree.appendId(root, .{ .stack = .{ .gap = 8 } });
    try promise(app, promises, "Accessible by construction", "Every element is semantic — a heading is structure, a button is a " ++
        "button, a label is mandatory. The accessibility tree and the pixels " ++
        "are both projections of the same semantic tree, so accessibility " ++
        "cannot be added and cannot be omitted. What construction cannot " ++
        "verify, an automatic audit catches.");
    try promise(app, promises, "Deterministic to the pixel", "Same logical viewport, same bytes — across runs, machines and " ++
        "platforms. Layout is integer math; rendering has no GPU, no " ++
        "hinting, no subpixel tricks. Screenshots are therefore tests: " ++
        "byte-exact, no tolerance, no perceptual diffing.");
    try promise(app, promises, "Testable end to end, headless", "nokre ships its own e2e framework, driving the real app through the " ++
        "real event pipeline — no browser driver, no window, no flakiness. " ++
        "Interactions go through the user's pipeline; assertions read the " ++
        "screen reader's snapshot.");

    try heading(app, root, .h2, "What nokre refuses to do");
    try text(app, root, "Most of these are load-bearing for a promise above: remove one and " ++
        "it collapses. The rest take away a question the framework never " ++
        "needed answered.");
    try bullets(app, root, &.{
        &.{
            strong("No hover states. "),
            plain("Interaction is press and release, key, focus, and one gesture. Nothing changes because a pointer floated over it: an affordance only pointer users can discover is information withheld from touch and keyboard users."),
        },
        &.{
            strong("No transitions or animation. "),
            plain("State changes are instant. Motion is a vestibular hazard, an untestable intermediate state, and a tax on determinism. A spinner is animation too — waiting is written in words."),
        },
        &.{
            strong("No color. "),
            plain("Thirteen fixed grays, five semantic aliases, two independent ramps. The whole palette is proven against WCAG contrast in unit tests — floor "),
            .{ .text = "and", .emphasis = true },
            plain(" ceiling, because past a point more contrast stops buying legibility and starts costing comfort."),
        },
        &.{
            strong("No system fonts. "),
            plain("Four bundled families, eleven real drawn faces, no synthesis. The moment the OS font stack participates, byte-identity across machines is gone."),
        },
        &.{
            strong("No GPU. "),
            plain("CPU rasterization only. No driver variance, no flicker, no capability matrix — the same bytes everywhere is only promisable when no driver is involved."),
        },
        &.{
            strong("No fractional scaling. "),
            plain("Layout is integer logical pixels; hidpi is an integer scale factor, so a 2× frame is exactly the 1× frame at double density."),
        },
        &.{
            strong("No custom widgets, no styling system. "),
            plain("The element set is closed. A styling hook is an accessibility loophole: contrast, target size and labeling can only be enforced on elements the framework owns."),
        },
        &.{
            strong("No paths. "),
            plain("A reference names a screen — "),
            mono("note~42"),
            plain(" — and says nothing about where the screen sits, because screens do not sit anywhere."),
        },
    });
    try spanned(app, root, &.{
        plain("They are guarantees, not gaps: an app built on nokre "),
        .{ .text = "cannot", .emphasis = true },
        plain(" have these problems, because the library cannot express them. The argument, in full, is the "),
        linkTo("introduction", "introduction"),
        plain("."),
    });
    try styled(app, root, "The refusals buy something quieter as well: a nokre app at rest " ++
        "costs zero CPU. No ticker, no vsync loop, no animation frames — a " ++
        "frame renders when state changes, and otherwise nothing runs.", .{ .ink = .mid });

    try heading(app, root, .h2, "Six platforms, full parity");
    try text(app, root, "All six shells are working: window, input, IME, clipboard, and a " ++
        "screen reader on each. What differs at a glance is the text scaler " ++
        "and the accessibility backend.");
    try tableOf(app, root, &.{
        &.{ "Platform", "Shell", "Text", "Accessibility" },
        &.{ "macOS", "AppKit", "CoreText", "VoiceOver via AccessKit" },
        &.{ "iOS", "UIKit", "CoreText", "VoiceOver via UIAccessibility" },
        &.{ "Windows", "Win32", "FreeType", "Narrator/NVDA/JAWS via AccessKit (UIA)" },
        &.{ "Linux", "Wayland", "FreeType", "Orca/AT-SPI via AccessKit" },
        &.{ "Android", "JNI + SurfaceView", "FreeType", "TalkBack via node provider" },
        &.{ "Web", "wasm32, no shell", "the browser's", "the DOM itself — nothing to mirror" },
    });

    try heading(app, root, .h2, "This site is a nokre app");
    try spanned(app, root, &.{
        plain("Every page here — this one included — is a nokre element tree. "),
        plain("The generator builds each screen through "),
        mono("tree.append"),
        plain(", runs nokre's accessibility audit over it, and then writes the tree out as HTML instead of pixels. "),
        plain("The stylesheet's grays, type scale and metrics are read out of nokre's own source at build time. "),
        plain("What that means, and where the edition stops short, is the "),
        linkTo("colophon", "colophon"),
        plain("."),
    });

    try heading(app, root, .h2, "Start here");
    try tiles(app, root, &.{ "introduction", "getting-started", "gallery", "palette", "docs" });
}

fn promise(app: *App, parent: NodeId, title: []const u8, body: []const u8) !void {
    const box = try app.tree.appendId(parent, .{ .box = .{} });
    try heading(app, box, .h3, title);
    try text(app, box, body);
}

// ------------------------------------------------------------ indexes

fn index(app: *App, track: @FieldType(pages.Page, "track")) !void {
    const root = app.tree.rootId();
    if (track == .consumer) {
        try heading(app, root, .h1, "Build an app");
        try text(app, root, "Everything needed to build and ship one: the philosophy, the " ++
            "course, and one reference per surface. Each fact has exactly one " ++
            "home — these pages complement the internals track, they never " ++
            "duplicate it.");
    } else {
        try heading(app, root, .h1, "Work on nokre");
        try text(app, root, "How the promises are kept inside: the layer rules, the pixel " ++
            "contract, the six shells, and the per-service wiring. Start with " ++
            "the architecture, then the contributor checklists.");
    }

    const group = try app.tree.appendId(root, .{ .tile_group = .{} });
    for (pages.all) |p| {
        if (p.track != track) continue;
        try app.tree.append(group, .{ .tile = .{
            .label = p.title,
            .detail = p.blurb,
            .route = p.name,
        } });
    }

    if (track == .consumer) {
        try heading(app, root, .h2, "Also here");
        try tiles(app, root, &.{ "gallery", "palette", "internals" });
    } else {
        try heading(app, root, .h2, "Also here");
        try tiles(app, root, &.{ "palette", "colophon", "docs" });
    }
}

// ---------------------------------------------------------- documents

/// One of nokre's own Markdown files, handed to the `document` element
/// exactly as an app would hand it a fetched terms-of-service: the
/// parser runs inside `append`, expands into ordinary elements, and
/// every append-time gate applies to it for free.
fn document(app: *App, i: usize, source: []const u8) !void {
    const root = app.tree.rootId();
    try app.tree.append(root, .{ .document = .{
        .label = pages.all[i].title,
        .source = source,
    } });
}

// -------------------------------------------------------------- palette

fn palette(site: *Site, app: *App) !void {
    const gpa = site.gpa;
    const root = app.tree.rootId();
    const Gray = nok.Gray;

    try heading(app, root, .h1, "Palette and scale");
    try text(app, root, "Thirteen steps, two ramps, six type scales. A step is a semantic " ++
        "position rather than a byte: each appearance supplies its own ramp, " ++
        "and the dark one is deliberately not the light one reversed. " ++
        "Everything on this page is read out of nokre's source at build " ++
        "time, so it cannot drift from the library.");

    try heading(app, root, .h2, "The ramps");
    // Thirteen filled boxes in a row. A box is the only element that
    // paints a ground, so a swatch is a box — there is no swatch
    // element and there is not going to be one.
    const strip = try app.tree.appendId(root, .{ .stack = .{ .axis = .horizontal, .gap = 4 } });
    inline for (@typeInfo(Gray).@"enum".fields) |f| {
        const g: Gray = @enumFromInt(f.value);
        try app.tree.append(strip, .{ .box = .{ .fill = g, .border = false, .padding = 18 } });
    }
    try styled(app, root, "g0 on the left through g12 on the right, in whichever appearance you are reading this in. The dark ramp descends where the light one climbs — that descent is the inversion, which is why no draw site inverts anything. There is no theme switch here because there is none in nokre: both follow the system.", .{
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
    try tableOf(app, root, rows.items);

    try heading(app, root, .h2, "The five aliases");
    try text(app, root, "You will mostly use these. They sit where WCAG compliance holds by " ++
        "construction, in both appearances.");
    try tableOf(app, root, &.{
        &.{ "Alias", "Step", "Use" },
        &.{ "ink", "g2", "Body text. 14.2:1 on paper in light, 10.6:1 in dark — not the 21:1 true black would give, because past a point contrast stops buying legibility and starts costing comfort." },
        &.{ "dark", "g3", "Secondary text that still has to read as text (AAA)." },
        &.{ "mid", "g5", "Dimmed text: labels, details, captions (AA body)." },
        &.{ "light", "g9", "Boundaries and separators that carry no state." },
        &.{ "paper", "g12", "The page." },
    });

    try heading(app, root, .h2, "The type scale");
    try text(app, root, "Fixed. Six sizes, and every heading level maps onto one of them.");
    inline for (@typeInfo(nok.text.Scale).@"enum".fields) |f| {
        const s: nok.text.Scale = @enumFromInt(f.value);
        const label = try std.fmt.allocPrint(gpa, "{s} — {d}px on {d}px", .{ f.name, s.px(), s.lineHeight() });
        try styled(app, root, label, .{ .scale = s });
    }

    try heading(app, root, .h2, "Both families");
    try styled(app, root, "prose — IBM Plex Sans, four faces. Body copy, labels, headings.", .{});
    try styled(app, root, "mono — JetBrains Mono, four faces. Code, verbatim values, anything whose columns mean something.", .{ .family = .mono });
    try styled(app, root, "A fifth face carries the Arabic script — سلام دنیا — so Persian and Arabic render in one voice whatever family was asked for.", .{});

    try heading(app, root, .h2, "Where this comes from");
    try spanned(app, root, &.{
        plain("The bytes, the ratios and the reasoning are "),
        linkTo("the pixel model", "internals.pixel-model"),
        plain(". The palette itself is "),
        linkTo("src/core/color.zig", "../src/core/color.zig"),
        plain(", where a ramp byte that breaks compliance — in either direction, in either appearance — fails the build."),
    });
}

// -------------------------------------------------------------- gallery

fn gallery(app: *App) !void {
    const root = app.tree.rootId();

    try heading(app, root, .h1, "Every element");
    try text(app, root, "The complete, closed set. Every element carries its semantics with " ++
        "it — role, label and state are intrinsic, which is why " ++
        "accessibility can be derived rather than annotated. There is no " ++
        "styling API: if an element does not do what you want, the answer is " ++
        "a different composition of these, not a customization hook.");
    const note = try app.tree.appendId(root, .{ .box = .{} });
    try styled(app, note, "The controls below are specimens. They are drawn the way nokre " ++
        "draws them and they take focus the way nokre does; the ones with " ++
        "state — checkbox, toggle, radio, select, fields — really do change " ++
        "it, because a browser gives that for free. The buttons call " ++
        "nothing: on this edition there is no app behind them.", .{ .ink = .mid, .scale = .small });

    // ---- static ----
    try heading(app, root, .h2, "Static");

    try heading(app, root, .h3, "text");
    try text(app, root, "Body copy. Wraps greedily at word boundaries within the parent width.");
    try spanned(app, root, &.{
        plain("Inline structure comes from spans — Markdown's inline vocabulary: "),
        strong("strong"),
        plain(", "),
        .{ .text = "emphasis", .emphasis = true },
        plain(", "),
        mono("code"),
        plain(", "),
        .{ .text = "strike", .strike = true },
        plain(", and "),
        linkTo("an inline link", "elements"),
        plain(", which is a control and therefore its own tab stop."),
    });

    try heading(app, root, .h3, "heading");
    try text(app, root, "h1 through h6, mapped to fixed sizes. Headings are structure, not styling — the audit fails a skipped level. Every level draws bold, which is what keeps h5 and h6 reading as headings beside the prose they share a size with.");

    try heading(app, root, .h3, "icon");
    const icons = try app.tree.appendId(root, .{ .stack = .{ .axis = .horizontal, .gap = 8 } });
    try app.tree.append(icons, .{ .icon = .{ .name = .shapes, .label = "Shapes" } });
    try app.tree.append(icons, .{ .icon = .{ .name = .ruler, .label = "Ruler" } });
    try app.tree.append(icons, .{ .icon = .{ .name = .accessibility, .label = "Accessibility" } });
    try app.tree.append(icons, .{ .icon = .{ .name = .flask_conical, .label = "Flask" } });
    try app.tree.append(icons, .{ .icon = .{ .name = .globe, .ink = .mid } });
    try styled(app, root, "One named Lucide glyph, laid out as a square line-height box. An empty label means decorative, and decorative means hidden from assistive tech; a named one is announced and must clear the same contrast gate as text.", .{ .ink = .mid, .scale = .small });

    try heading(app, root, .h3, "divider");
    try divider(app, root);

    try heading(app, root, .h3, "badge");
    const badges = try app.tree.appendId(root, .{ .stack = .{ .axis = .horizontal, .gap = 8 } });
    try app.tree.append(badges, .{ .badge = .{ .label = "Active" } });
    try app.tree.append(badges, .{ .badge = .{ .label = "Owner" } });
    try app.tree.append(badges, .{ .badge = .{ .label = "3 pending" } });
    try styled(app, root, "Where color-coded chips carry state by hue elsewhere, here the words carry it.", .{ .ink = .mid, .scale = .small });

    try heading(app, root, .h3, "meter");
    try app.tree.append(root, .{ .meter = .{ .label = "12 of 30 days", .value = 12, .max = 30 } });
    try styled(app, root, "The label is mandatory and is what assistive tech hears; the fill only restates it. Never animated — for indeterminate waiting, write \"Loading…\" as text.", .{ .ink = .mid, .scale = .small });

    try heading(app, root, .h3, "qr");
    try app.tree.append(root, .{ .qr = .{
        .label = "This site",
        .value = "https://getnokre.github.io",
    } });

    // ---- containers ----
    try heading(app, root, .h2, "Containers");

    try heading(app, root, .h3, "stack");
    try text(app, root, "Vertical or horizontal flow, with a gap and a padding. The tree root is a vertical stack.");

    try heading(app, root, .h3, "box");
    const outer = try app.tree.appendId(root, .{ .box = .{} });
    try text(app, outer, "Grouping container: an optional 1px border, a padding, an optional fill. Boxes group; they do not decorate.");
    const inner = try app.tree.appendId(outer, .{ .box = .{ .fill = .g11 } });
    try text(app, inner, "A box's edge is a wall: the margin advice stops at it, so nothing ever bleeds across a border.");

    try heading(app, root, .h3, "scroll_region");
    const region = try app.tree.appendId(root, .{ .scroll_region = .{ .height = 120 } });
    try text(app, region, "A viewport over vertically flowing children, clipped, with a 2px indicator reflecting the offset.");
    try text(app, region, "The bar has two tones, switched by state and never by time: emphasized while its surface is engaged, quiet at rest.");
    try text(app, region, "At rest the primary \"more is there\" affordance is the content itself, cut mid-element at the viewport edge — which is why the audit fails a fixed-height region whose top edge cuts nothing visible.");

    // ---- interactive ----
    try heading(app, root, .h2, "Interactive");
    try spanned(app, root, &.{
        strong("Every interactive element requires a label. "),
        plain("That is not a convention and not a lint: "),
        mono("tree.append"),
        plain(" refuses to construct an interactive element with an empty one. An inaccessible control cannot exist."),
    });

    try heading(app, root, .h3, "button");
    const buttons = try app.tree.appendId(root, .{ .stack = .{ .axis = .horizontal, .gap = 8 } });
    try app.tree.append(buttons, .{ .button = .{ .label = "New note" } });
    try app.tree.append(buttons, .{ .button = .{ .label = "Cancel", .secondary = true } });
    try app.tree.append(buttons, .{ .button = .{ .label = "Delete", .disabled = true } });

    try heading(app, root, .h3, "link");
    try app.tree.append(root, .{ .link = .{ .label = "The routing contract", .route = "routing" } });

    try heading(app, root, .h3, "toggle");
    try app.tree.append(root, .{ .toggle = .{ .label = "Sync over cellular", .on = true } });

    try heading(app, root, .h3, "checkbox");
    try app.tree.append(root, .{ .checkbox = .{ .label = "Remember this device", .checked = true } });
    try app.tree.append(root, .{ .checkbox = .{ .label = "Send crash reports" } });

    try heading(app, root, .h3, "radio_group");
    try app.tree.append(root, .{ .radio_group = .{
        .label = "Export format",
        .options = &.{ "Markdown", "Plain text", "HTML" },
        .selected = 0,
    } });

    try heading(app, root, .h3, "segmented");
    try app.tree.append(root, .{ .segmented = .{
        .label = "View",
        .options = &.{ "All", "Starred", "Archived" },
        .selected = 1,
    } });
    try styled(app, root, "An exclusive choice among 2+ fixed options — radiogroup semantics, not tabs. There is deliberately no tablist element: nokre rebuilds subtrees instantly, so co-existing tab panels never exist and tablist semantics would be a lie.", .{ .ink = .mid, .scale = .small });

    try heading(app, root, .h3, "select");
    try app.tree.append(root, .{ .select = .{
        .label = "Sort by",
        .options = &.{ "Recently edited", "Recently created", "Title" },
        .selected = 0,
    } });

    try heading(app, root, .h3, "text_input");
    try app.tree.append(root, .{ .text_input = .{ .label = "Title", .value = "Grocery list" } });

    try heading(app, root, .h3, "text_area");
    try app.tree.append(root, .{ .text_area = .{
        .label = "Note",
        .placeholder = "Whitespace is preserved; the field grows to three lines and then scrolls.",
    } });

    try heading(app, root, .h3, "copyable");
    try app.tree.append(root, .{ .copyable = .{
        .label = "Recovery code",
        .value = "K7QM-2XPD-9ATV-6BLR",
    } });
    try styled(app, root, "Activation is intrinsic — it writes the value to the platform clipboard. There is no action to wire, so it cannot be miswired.", .{ .ink = .mid, .scale = .small });

    try heading(app, root, .h3, "tile_group and tile");
    const group = try app.tree.appendId(root, .{ .tile_group = .{
        .description = "Reach for tiles where a screen is a list of destinations or row-shaped actions.",
    } });
    try app.tree.append(group, .{ .tile = .{
        .label = "Accessibility",
        .detail = "Derivation, enforcement, the audit",
        .route = "accessibility",
    } });
    try app.tree.append(group, .{ .tile = .{
        .label = "Testing",
        .detail = "Harness, queries, golden screenshots",
        .route = "testing",
    } });

    try heading(app, root, .h3, "list and list_item");
    try bullets(app, root, &.{
        &.{plain("Markers are derived, never authored — so a list can never number itself wrongly.")},
        &.{plain("A list_item holds document blocks: text and nested lists, not arbitrary content.")},
        &.{plain("Nesting is capped at three levels, at append. Past that the indent has eaten the line without saying anything the words do not.")},
    });

    try heading(app, root, .h3, "blockquote");
    const quote = try app.tree.appendId(root, .{ .blockquote = .{} });
    try text(app, quote, "The attribution is words inside the quote, not a field on it: a quote whose source only a border implies is a quote whose source nobody hears.");
    try styled(app, quote, "— docs/elements.md", .{ .ink = .mid, .scale = .small });

    try heading(app, root, .h3, "code_block");
    try code(app, root,
        \\// Whitespace preserved, never reflowed: a wrapped code line
        \\// lies about where the code breaks.
        \\const focus = metrics.focus_stroke; // 2
    );

    try heading(app, root, .h3, "table, row and cell");
    try tableOf(app, root, &.{
        &.{ "Element", "Children must be" },
        &.{ "table", "row" },
        &.{ "row", "cell" },
        &.{ "cell", "anything" },
    });

    // ---- chrome ----
    try heading(app, root, .h2, "Navigation chrome");
    try spanned(app, root, &.{
        plain("The bar at the bottom of this page is a "),
        mono("nav"),
        plain(": two to five destinations, installed once and preserved across every router rebuild. It carries no labels of its own — what a screen is called is its route's title, declared once at the route table, so the nav and the screen cannot disagree. This screen is none of the destinations, so it names itself with the trailing "),
        mono("nav_here"),
        plain(" plate, which is a label and not a link."),
    });

    try heading(app, root, .h2, "Layers");
    try spanned(app, root, &.{
        plain("A "),
        mono("sheet"),
        plain(", a "),
        mono("notice"),
        plain(" and the select picker are opened by an event — a press, an arrival, a change. This edition has no events, so they cannot appear here. They are specified in "),
        linkTo("elements.md", "elements"),
        plain("."),
    });
}

// ------------------------------------------------------------- colophon

fn colophon(app: *App) !void {
    const root = app.tree.rootId();

    try heading(app, root, .h1, "Colophon");
    try text(app, root, "This site is a nokre app that renders to HTML. Not a site about " ++
        "nokre with a nokre-ish stylesheet: every page is a real element " ++
        "tree, built by a route builder with the same signature an app's " ++
        "screens have, checked by the same gates, and audited by the same " ++
        "audit before a byte of markup is written.");

    try heading(app, root, .h2, "How a page is made");
    const steps = try app.tree.appendId(root, .{ .list = .{ .ordered = true } });
    try step(app, steps, "One App is constructed with a route table of every page on this site. Duplicate or malformed route names fail there, in App.init, rather than at first navigation.");
    try step(app, steps, "The generator switches to each route in turn — switchTo, the motion the web shell uses for an inbound link, which is exactly what a visitor arriving at a static page has.");
    try step(app, steps, "The route's builder appends elements. Documentation pages append one document element holding nokre's own Markdown, which the parser expands into ordinary elements inside append.");
    try step(app, steps, "nokre's accessibility audit runs over the finished screen. A skipped heading level, an unlabeled control, two controls sharing a label, a contrast pair outside the floor or the ceiling — any of them fails the build.");
    try step(app, steps, "The tree is walked once more and written out as HTML: the same walk render/renderer.zig makes, with markup where it has draw calls.");

    try text(app, root, "There is no build server. The generator runs on a laptop and its " ++
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
        const lead: []const nok.element.Span =
            &.{plain("And which sources those were is stamped rather than assumed: " ++
                "this page was generated from nokre at ")};
        const mid: []const nok.element.Span = &.{plain(" and built atop ")};
        const site_clause: []const nok.element.Span = &.{mono(opts.site_rev)};
        const tail: []const nok.element.Span = &.{plain(" of this repository.")};
        break :prov lead ++ stamp(opts.nokre_rev, opts.nokre_dirty) ++
            mid ++ site_clause ++ tail;
    };
    try spanned(app, root, provenance);

    try heading(app, root, .h2, "The door was left open on purpose");
    const quote = try app.tree.appendId(root, .{ .blockquote = .{} });
    try text(app, quote, "A renderer is an interpretation of the semantic tree, the way a " ++
        "browser interprets HTML. It may draw each element however it likes, " ++
        "with capabilities the Skia edition refuses, so long as the semantics " ++
        "— element set, behavior, focus model, a11y tree — are conveyed " ++
        "faithfully.");
    try spanned(app, quote, &.{ plain("— "), linkTo("internals/renderer-editions.md", "internals.renderer-editions") });
    try text(app, root, "That document splits the guarantees in two. Grayscale, CPU raster, " ++
        "pixel determinism and byte-exact goldens belong to the Skia edition. " ++
        "The semantic tree, event behavior, focus traversal, the accessibility " ++
        "snapshot and the validate/audit rules live on the tree, so they hold " ++
        "whatever renders it. This edition keeps the second list whole.");

    try heading(app, root, .h2, "What this edition keeps");
    try bullets(app, root, &.{
        &.{
            strong("The closed set. "),
            plain("Every element has exactly one case in the writer. An element with no case is a compile error, not a div — which is the same discipline that makes the set closed in the first place."),
        },
        &.{
            strong("The semantics. "),
            plain("Roles, labels, states and focus order come from the tree, not from markup written by hand. A tile with a route is a link; a tile with an action is a button; the nav's own current entry is a label and not a destination, because it goes where you already are."),
        },
        &.{
            strong("The design system, to the byte. "),
            plain("The stylesheet is generated: thirteen grays in two ramps out of core/color.zig, six type scales out of core/text.zig, and every padding, radius, target and stroke out of core/layout.zig. Nothing is transcribed, so nothing can drift."),
        },
        &.{
            strong("The faces. "),
            plain("The same IBM Plex Sans, JetBrains Mono, Lucide and Vazirmatn binaries nokre bundles, subset to what this site draws. There is no font stack in the stylesheet, because nokre has no font stack."),
        },
        &.{
            strong("The refusals. "),
            plain("No animation, no transition, no hover rule anywhere in the stylesheet, no color, and no theme switch — the appearance follows the system, which is the whole of nokre's appearance API."),
        },
    });

    try heading(app, root, .h2, "The file is the first frame");
    try text(app, root, "A generated page is a screen measured with a ruler that is not " ++
        "yours. A build has no font metrics and no window, so the stand-in " ++
        "measurer answers every measured question against 1280 pixels: " ++
        "where prose wraps, whether a row of actions has to give up its " ++
        "tail, whether the nav roster fits on one line. On a phone each of " ++
        "those answers is about a screen nobody is looking at.");
    try text(app, root, "So the page ships with the app that made it. The same wasm module " ++
        "on every screen, the same route table, the same builders — it " ++
        "boots, measures the column you actually have, and retakes those " ++
        "decisions. The roster that could not fit collapses into a section " ++
        "chip, which is what nokre does on every other platform and what " ++
        "the file alone could never do.");
    try text(app, root, "It is an upgrade and not a requirement, which is the whole reason " ++
        "the pair exists. Nothing on this site waits for it: the markup is " ++
        "complete before a byte of script arrives, the links are real " ++
        "links, and a reader with JavaScript off gets the 1280-pixel " ++
        "reading of the page rather than an empty one. Navigation stays " ++
        "the browser's for the same reason — every screen here is a file " ++
        "with a URL of its own, so a link is something to follow rather " ++
        "than something to intercept.");

    try heading(app, root, .h2, "Where it stops short, exactly");
    try text(app, root, "Two places. Each is the web being the web, and each is a decision " ++
        "rather than an oversight.");
    try bullets(app, root, &.{
        &.{
            strong("Lines wrap where the browser wraps them. "),
            plain("Layout is computed and then ignored. Pixel determinism is the Skia edition's promise, not this one's, and a page that fixed its line breaks would break the first reader who changed their text size."),
        },
        &.{
            strong("There are external links. "),
            plain("nokre navigates its own screens and nothing else. A page that cites a source file has to leave the app, so those links carry an arrow and say so. They are the only ones on the site that do."),
        },
    });

    try heading(app, root, .h2, "What it costs the reader");
    try headerlessTableOf(app, root, &.{
        &.{ "JavaScript", "nokre's own live driver and nothing else. No framework, no dependency, no analytics, no cookies." },
        &.{ "Before it runs", "The whole page. Content, links, chrome — the script changes what is measured, not what is there." },
        &.{ "With it off", "The same page, wrapped for a 1280-pixel window." },
        &.{ "Requests", "One document, one stylesheet, one favicon, the faces the page uses, the live driver and the services module it imports, one wasm module, and — on a documentation page — its Markdown." },
        &.{ "Trackers, cookies, consent", "None, so no banner asking about any." },
        &.{ "Appearance", "Follows the system, both ramps generated." },
        &.{ "Print", "Chrome drops out; the content is the page." },
    });

    try heading(app, root, .h2, "Sources");
    try text(app, root, "Documentation pages are nokre's own Markdown, rendered by nokre's " ++
        "own parser — not a copy, and not a second parser. Every internal " ++
        "link in them is a route reference, resolved at build time against " ++
        "the route table; one that names a page this site does not publish " ++
        "fails the build the way error.UnknownRoute fails an app.");
    try text(app, root, "Which also means the subset is the subset. Where a document reaches " ++
        "for something the parser does not cover, it comes through as its " ++
        "own source text, markers and all — that is the rule that makes " ++
        "parsing bytes nobody reviewed safe, and it is exactly what a nokre " ++
        "app would put on screen. Nothing here quietly cleans it up first.");
    try tiles(app, root, &.{ "internals.renderer-editions", "internals.pixel-model", "markdown" });
}

// ------------------------------------------------------------ not found

fn notFound(app: *App) !void {
    const root = app.tree.rootId();
    try heading(app, root, .h1, "Not found");
    try spanned(app, root, &.{
        plain("No screen answers to that name. In an app this is "),
        mono("error.UnknownRoute"),
        plain(", and the router leaves you where you were rather than taking you somewhere nobody asked for. A web server has nowhere to leave you, so here is the way back."),
    });
    try tiles(app, root, &.{ "home", "docs", "internals" });
}

/// One checkout's clause in the provenance sentence: the short hash,
/// and — when the build read a working tree holding more than the
/// commit — the admission, in words. Words rather than a `-dirty`
/// suffix, because the sentence is prose and its reader need not be a
/// git user to be owed the fact.
fn stamp(comptime rev: []const u8, comptime dirty: bool) []const nok.element.Span {
    return if (dirty)
        &.{ mono(rev), plain(" (with uncommitted changes)") }
    else
        &.{mono(rev)};
}

fn step(app: *App, list: NodeId, body: []const u8) !void {
    const li = try app.tree.appendId(list, .{ .list_item = .{} });
    try app.tree.append(li, .{ .text = .{ .content = body } });
}
