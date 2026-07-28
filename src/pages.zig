//! The site's route table.
//!
//! Every page is a nokre route, and the URL is the route's name — flat,
//! one segment, no directories. That is `docs/routing.md`'s **no paths**
//! refusal taken at its word: a reference names a screen and says
//! nothing about where the screen sits, so `internals.pixel-model` is a
//! name with a dot in it and not a path with a level in it. The router
//! never reads the dot as a level, and neither does this site.

const std = @import("std");
const nok = @import("nokre");

pub const IconName = nok.element.IconName;

pub const Kind = enum {
    /// The one page that is not prose: the argument, in elements.
    home,
    /// A generated index over one docs track.
    docs_index,
    internals_index,
    /// Generated from nokre's own source: the palette and the type scale.
    palette,
    /// Every element in the closed set, drawn once.
    gallery,
    /// How this site is made, and by what.
    colophon,
    /// What a visitor gets for a URL this site does not have. A screen
    /// like any other — the shell just serves it under a different
    /// name, because that is the name the host looks for.
    not_found,
    /// One of nokre's Markdown documents, expanded by nokre's own
    /// `document` element.
    doc,
};

pub const Page = struct {
    /// Route name, URL segment, and — for a doc — the key its Markdown
    /// source is looked up under. One string, three jobs, which is what
    /// keeps them from disagreeing.
    name: []const u8,
    /// `RouteDef.title`: what the chrome calls this screen. Declared
    /// once here, so the nav and the page cannot differ about it.
    title: []const u8,
    /// One line. Used as the tile's detail in an index, and as the
    /// page's meta description — the same sentence in both places.
    blurb: []const u8,
    icon: IconName,
    kind: Kind = .doc,
    /// Path under nokre's `docs/`, for `.doc` pages.
    md: []const u8 = "",
    /// Whether this page belongs to an index, and which.
    track: enum { none, consumer, contributor } = .none,
};

/// The three nav destinations, in bar order. A closed 2–5 set, per
/// `setNav` — everything else on this site is an off-roster screen and
/// names itself with a `nav_here` plate, which is the framework's job
/// and not this file's.
pub const destinations = [_][]const u8{ "home", "docs", "internals" };

pub const all = [_]Page{
    .{
        .name = "home",
        .title = "Home",
        .blurb = "A deliberately limited GUI library: text, lines, and boxes.",
        .icon = .house,
        .kind = .home,
    },
    .{
        .name = "docs",
        .title = "Docs",
        .blurb = "Build and ship an app: the philosophy, the course, and one reference per surface.",
        .icon = .book_open,
        .kind = .docs_index,
    },
    .{
        .name = "internals",
        .title = "Internals",
        .blurb = "How the promises are kept inside: the layer cake, the pixel contract, the shells.",
        .icon = .wrench,
        .kind = .internals_index,
    },

    // ---- consumer track ----
    .{
        .name = "introduction",
        .title = "Introduction",
        .blurb = "The philosophy: what nokre refuses, and what each refusal buys.",
        .icon = .feather,
        .md = "introduction.md",
        .track = .consumer,
    },
    .{
        .name = "getting-started",
        .title = "Getting started",
        .blurb = "The course: build one app that uses everything, test it as you go, ship it to six platforms.",
        .icon = .milestone,
        .md = "getting-started.md",
        .track = .consumer,
    },
    .{
        .name = "elements",
        .title = "Elements",
        .blurb = "The closed element set: each element's meaning, its visual spec, and when to reach for it.",
        .icon = .shapes,
        .md = "elements.md",
        .track = .consumer,
    },
    .{
        .name = "routing",
        .title = "Routing",
        .blurb = "Screens as named builders, navigation as a stack, and references that carry no path.",
        .icon = .signpost,
        .md = "routing.md",
        .track = .consumer,
    },
    .{
        .name = "markdown",
        .title = "Markdown",
        .blurb = "The document element: the subset it parses, and the rule that everything else degrades.",
        .icon = .pilcrow,
        .md = "markdown.md",
        .track = .consumer,
    },
    .{
        .name = "accessibility",
        .title = "Accessibility",
        .blurb = "The a11y contract: how the snapshot is derived, what construction refuses, what the audit catches.",
        .icon = .accessibility,
        .md = "accessibility.md",
        .track = .consumer,
    },
    .{
        .name = "localization",
        .title = "Localization",
        .blurb = "ARB catalogs at comptime, ICU messages, right-to-left, and what the compiler checks.",
        .icon = .languages,
        .md = "localization.md",
        .track = .consumer,
    },
    .{
        .name = "testing",
        .title = "Testing",
        .blurb = "The headless e2e harness: semantic queries, the input driver, byte-exact golden screenshots.",
        .icon = .flask_conical,
        .md = "testing.md",
        .track = .consumer,
    },
    .{
        .name = "services",
        .title = "Services",
        .blurb = "Optional OS capabilities beyond the window, and each one's consumer contract.",
        .icon = .package,
        .md = "services.md",
        .track = .consumer,
    },
    .{
        .name = "roadmap",
        .title = "Roadmap",
        .blurb = "What's built and what remains: the last services, nokre-owned Skia builds, tooling.",
        .icon = .map,
        .md = "roadmap.md",
        .track = .consumer,
    },

    // ---- contributor track ----
    .{
        .name = "internals.architecture",
        .title = "Architecture",
        .blurb = "The layer cake and the module map: what may depend on what, and why.",
        .icon = .layers,
        .md = "internals/architecture.md",
        .track = .contributor,
    },
    .{
        .name = "internals.contributing",
        .title = "Contributing",
        .blurb = "The checklists: a new element, a new service, and what each one owes the rest.",
        .icon = .git_branch,
        .md = "internals/contributing.md",
        .track = .contributor,
    },
    .{
        .name = "internals.pixel-model",
        .title = "The pixel model",
        .blurb = "The normative contract behind same viewport ⇒ same bytes: the ramps, the geometry, the type scale.",
        .icon = .ruler,
        .md = "internals/pixel-model.md",
        .track = .contributor,
    },
    .{
        .name = "internals.platform-shells",
        .title = "Platform shells",
        .blurb = "The six shells and the contract each keeps: window, input, IME, clipboard, screen reader.",
        .icon = .monitor,
        .md = "internals/platform-shells.md",
        .track = .contributor,
    },
    .{
        .name = "internals.renderer-editions",
        .title = "Renderer editions",
        .blurb = "Why a second renderer is possible, which seams keep it possible, and what it would owe the first.",
        .icon = .component,
        .md = "internals/renderer-editions.md",
        .track = .contributor,
    },
    .{
        .name = "internals.dom-edition",
        .title = "The DOM edition",
        .blurb = "The second renderer: the same tree walk written as markup, and what it keeps.",
        .icon = .code,
        .md = "internals/dom-edition.md",
        .track = .contributor,
    },
    .{
        .name = "internals.skia-build",
        .title = "Skia builds",
        .blurb = "The path to nokre-owned Skia: FreeType everywhere, and byte-identity across platforms.",
        .icon = .hammer,
        .md = "internals/skia-build.md",
        .track = .contributor,
    },
    .{
        .name = "internals.workers",
        .title = "Workers",
        .blurb = "Long-lived compute actors off the UI thread: typed messages in, typed replies out.",
        .icon = .cpu,
        .md = "internals/workers.md",
        .track = .contributor,
    },
    .{
        .name = "internals.haptics",
        .title = "Haptics",
        .blurb = "The one knock nokre fires, why it is the framework's and not an app's.",
        .icon = .zap,
        .md = "internals/haptics.md",
        .track = .contributor,
    },
    .{
        .name = "internals.http",
        .title = "HTTP",
        .blurb = "The request lane: the native transport, the web leg, and what the mock journals.",
        .icon = .globe,
        .md = "internals/http.md",
        .track = .contributor,
    },
    .{
        .name = "internals.secure_store",
        .title = "Secure store",
        .blurb = "Keychain, Credential Manager, libsecret: one contract over five very different vaults.",
        .icon = .lock,
        .md = "internals/secure_store.md",
        .track = .contributor,
    },
    .{
        .name = "internals.oauth",
        .title = "OAuth",
        .blurb = "PKCE, the redirect legs per platform, and the native Sign in with Apple path.",
        .icon = .key,
        .md = "internals/oauth.md",
        .track = .contributor,
    },
    .{
        .name = "internals.iap",
        .title = "In-app purchases",
        .blurb = "StoreKit on Apple, Play Billing on Android, and no store anywhere else.",
        .icon = .credit_card,
        .md = "internals/iap.md",
        .track = .contributor,
    },

    // ---- pages this site adds ----
    .{
        .name = "gallery",
        .title = "Every element",
        .blurb = "The closed set, drawn once each — the whole vocabulary on one screen.",
        .icon = .shapes,
        .kind = .gallery,
    },
    .{
        .name = "palette",
        .title = "Palette and scale",
        .blurb = "Thirteen grays, two ramps, six type scales — read out of nokre's own source.",
        .icon = .palette,
        .kind = .palette,
    },
    .{
        .name = "notfound",
        .title = "Not found",
        .blurb = "No screen answers to that name.",
        .icon = .ban,
        .kind = .not_found,
    },
    .{
        .name = "colophon",
        .title = "Colophon",
        .blurb = "This site is a nokre app. What that means, and where the edition stops short.",
        .icon = .square_asterisk,
        .kind = .colophon,
    },
};

pub fn indexOf(name: []const u8) ?usize {
    for (all, 0..) |p, i| {
        if (std.mem.eql(u8, p.name, name)) return i;
    }
    return null;
}

pub fn find(name: []const u8) ?*const Page {
    return if (indexOf(name)) |i| &all[i] else null;
}

test "every declared destination is a route" {
    for (destinations) |d| try std.testing.expect(indexOf(d) != null);
}

test "route names are flat and unique" {
    for (all, 0..) |p, i| {
        try std.testing.expect(p.name.len != 0);
        try std.testing.expect(std.mem.indexOfScalar(u8, p.name, '/') == null);
        try std.testing.expect(std.mem.indexOfScalar(u8, p.name, '~') == null);
        for (all[i + 1 ..]) |q| try std.testing.expect(!std.mem.eql(u8, p.name, q.name));
    }
}
