//! The site's route table.
//!
//! Every page is a nokre route, and the route's name is its one URL
//! segment — flat, no directories. That is `docs/routing.md`'s **no
//! paths** refusal taken at its word: a reference names a screen and
//! says nothing about where the screen sits, so `internals.pixel-model`
//! is a name with a dot in it and not a path with a level in it. The
//! router never reads the dot as a level, and neither does this site.
//!
//! What stands in front of that segment is the locale, and it is not
//! this file's business either: `links.zig` puts it there and nothing
//! in a route name knows it exists. Nothing here holds words, only
//! catalog keys — a route table is the one part of a site the locale
//! axis multiplies, so it is the one part that must not be written in a
//! language.

const std = @import("std");
const nok = @import("nokre");

const L = @import("l10n.zig").L;

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
    /// once here, so the nav and the page cannot differ about it — and
    /// a catalog key rather than words, because this site has a locale
    /// axis and a title is a function of it (`Title.of_locale`,
    /// content.zig's `routes`).
    ///
    /// The key is not free-form: `keyName` below derives it from the
    /// route name and a test holds every entry to that, so a page
    /// cannot end up wearing another page's title. Written out rather
    /// than computed here so a typo is a compile error at the entry
    /// that made it.
    title: L.Key,
    /// One line. Used as the tile's detail in an index, and as the
    /// page's meta description — the same sentence in both places, and
    /// a catalog key for the same reason `title` is.
    blurb: L.Key,
    icon: IconName,
    kind: Kind = .doc,
    /// Path under nokre's `docs/`, for `.doc` pages.
    md: []const u8 = "",
    /// Whether this page belongs to an index, and which.
    track: enum { none, consumer, contributor } = .none,
};

/// The three nav destinations, in bar order. A closed set, floored and
/// capped by `setNav` — the cap is `nav.max_nav_items`, which nokre
/// derives rather than picks, so it is cited and not copied here.
/// Everything else on this site is an off-roster screen and names
/// itself with a `nav_here` plate, which is the framework's job and not
/// this file's.
///
/// Every one of them wears a mark (`Page.icon`, required by this file),
/// which is one of the two uniform rosters `setNav` accepts — a mixture
/// is `error.NavIconsMixed`.
pub const destinations = [_][]const u8{ "home", "docs", "internals" };

pub const all = [_]Page{
    .{
        .name = "home",
        .title = .titleHome,
        .blurb = .blurbHome,
        .icon = .house,
        .kind = .home,
    },
    .{
        .name = "docs",
        .title = .titleDocs,
        .blurb = .blurbDocs,
        .icon = .book_open,
        .kind = .docs_index,
    },
    .{
        .name = "internals",
        .title = .titleInternals,
        .blurb = .blurbInternals,
        .icon = .wrench,
        .kind = .internals_index,
    },

    // ---- consumer track ----
    .{
        .name = "introduction",
        .title = .titleIntroduction,
        .blurb = .blurbIntroduction,
        .icon = .feather,
        .md = "introduction.md",
        .track = .consumer,
    },
    .{
        .name = "getting-started",
        .title = .titleGettingStarted,
        .blurb = .blurbGettingStarted,
        .icon = .milestone,
        .md = "getting-started.md",
        .track = .consumer,
    },
    .{
        .name = "elements",
        .title = .titleElements,
        .blurb = .blurbElements,
        .icon = .shapes,
        .md = "elements.md",
        .track = .consumer,
    },
    .{
        .name = "routing",
        .title = .titleRouting,
        .blurb = .blurbRouting,
        .icon = .signpost,
        .md = "routing.md",
        .track = .consumer,
    },
    .{
        .name = "markdown",
        .title = .titleMarkdown,
        .blurb = .blurbMarkdown,
        .icon = .pilcrow,
        .md = "markdown.md",
        .track = .consumer,
    },
    .{
        .name = "accessibility",
        .title = .titleAccessibility,
        .blurb = .blurbAccessibility,
        .icon = .accessibility,
        .md = "accessibility.md",
        .track = .consumer,
    },
    .{
        .name = "localization",
        .title = .titleLocalization,
        .blurb = .blurbLocalization,
        .icon = .languages,
        .md = "localization.md",
        .track = .consumer,
    },
    .{
        .name = "static-sites",
        .title = .titleStaticSites,
        .blurb = .blurbStaticSites,
        .icon = .file_text,
        .md = "static-sites.md",
        .track = .consumer,
    },
    .{
        .name = "testing",
        .title = .titleTesting,
        .blurb = .blurbTesting,
        .icon = .flask_conical,
        .md = "testing.md",
        .track = .consumer,
    },
    .{
        .name = "services",
        .title = .titleServices,
        .blurb = .blurbServices,
        .icon = .package,
        .md = "services.md",
        .track = .consumer,
    },
    .{
        .name = "roadmap",
        .title = .titleRoadmap,
        .blurb = .blurbRoadmap,
        .icon = .map,
        .md = "roadmap.md",
        .track = .consumer,
    },

    // ---- contributor track ----
    .{
        .name = "internals.architecture",
        .title = .titleInternalsArchitecture,
        .blurb = .blurbInternalsArchitecture,
        .icon = .layers,
        .md = "internals/architecture.md",
        .track = .contributor,
    },
    .{
        .name = "internals.contributing",
        .title = .titleInternalsContributing,
        .blurb = .blurbInternalsContributing,
        .icon = .git_branch,
        .md = "internals/contributing.md",
        .track = .contributor,
    },
    .{
        .name = "internals.pixel-model",
        .title = .titleInternalsPixelModel,
        .blurb = .blurbInternalsPixelModel,
        .icon = .ruler,
        .md = "internals/pixel-model.md",
        .track = .contributor,
    },
    .{
        .name = "internals.platform-shells",
        .title = .titleInternalsPlatformShells,
        .blurb = .blurbInternalsPlatformShells,
        .icon = .monitor,
        .md = "internals/platform-shells.md",
        .track = .contributor,
    },
    .{
        .name = "internals.renderer-editions",
        .title = .titleInternalsRendererEditions,
        .blurb = .blurbInternalsRendererEditions,
        .icon = .component,
        .md = "internals/renderer-editions.md",
        .track = .contributor,
    },
    .{
        .name = "internals.dom-edition",
        .title = .titleInternalsDomEdition,
        .blurb = .blurbInternalsDomEdition,
        .icon = .code,
        .md = "internals/dom-edition.md",
        .track = .contributor,
    },
    .{
        .name = "internals.skia-build",
        .title = .titleInternalsSkiaBuild,
        .blurb = .blurbInternalsSkiaBuild,
        .icon = .hammer,
        .md = "internals/skia-build.md",
        .track = .contributor,
    },
    .{
        .name = "internals.workers",
        .title = .titleInternalsWorkers,
        .blurb = .blurbInternalsWorkers,
        .icon = .cpu,
        .md = "internals/workers.md",
        .track = .contributor,
    },
    .{
        .name = "internals.haptics",
        .title = .titleInternalsHaptics,
        .blurb = .blurbInternalsHaptics,
        .icon = .zap,
        .md = "internals/haptics.md",
        .track = .contributor,
    },
    .{
        .name = "internals.http",
        .title = .titleInternalsHttp,
        .blurb = .blurbInternalsHttp,
        .icon = .globe,
        .md = "internals/http.md",
        .track = .contributor,
    },
    .{
        .name = "internals.secure_store",
        .title = .titleInternalsSecureStore,
        .blurb = .blurbInternalsSecureStore,
        .icon = .lock,
        .md = "internals/secure_store.md",
        .track = .contributor,
    },
    .{
        .name = "internals.oauth",
        .title = .titleInternalsOauth,
        .blurb = .blurbInternalsOauth,
        .icon = .key,
        .md = "internals/oauth.md",
        .track = .contributor,
    },
    .{
        .name = "internals.notifications",
        .title = .titleInternalsNotifications,
        .blurb = .blurbInternalsNotifications,
        .icon = .bell,
        .md = "internals/notifications.md",
        .track = .contributor,
    },
    .{
        .name = "internals.share",
        .title = .titleInternalsShare,
        .blurb = .blurbInternalsShare,
        .icon = .share,
        .md = "internals/share.md",
        .track = .contributor,
    },
    .{
        .name = "internals.iap",
        .title = .titleInternalsIap,
        .blurb = .blurbInternalsIap,
        .icon = .credit_card,
        .md = "internals/iap.md",
        .track = .contributor,
    },

    // ---- pages this site adds ----
    .{
        .name = "gallery",
        .title = .titleGallery,
        .blurb = .blurbGallery,
        .icon = .shapes,
        .kind = .gallery,
    },
    .{
        .name = "palette",
        .title = .titlePalette,
        .blurb = .blurbPalette,
        .icon = .palette,
        .kind = .palette,
    },
    .{
        .name = "notfound",
        .title = .titleNotfound,
        .blurb = .blurbNotfound,
        .icon = .ban,
        .kind = .not_found,
    },
    .{
        .name = "colophon",
        .title = .titleColophon,
        .blurb = .blurbColophon,
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

/// The catalog key a route's `prefix` message lives under: the prefix,
/// then the route name camel-cased at the three bytes a name may hold
/// as separators — `internals.pixel-model`'s title is
/// `titleInternalsPixelModel`, `internals.secure_store`'s is
/// `titleInternalsSecureStore`.
///
/// The same shape nokre derives its own reserved keys with
/// (`l10n.zig`'s `chromeKeyName`, `chromeCurrentScreen` from
/// `current_screen`), and here for the same purpose: the route name and
/// the key it reads under are one fact, so a page renamed without its
/// messages renamed fails the test below rather than quietly showing
/// another page's words.
pub fn keyName(comptime prefix: []const u8, comptime name: []const u8) []const u8 {
    comptime var out: []const u8 = prefix;
    comptime var upper = true;
    inline for (name) |c| {
        if (c == '.' or c == '-' or c == '_') {
            upper = true;
            continue;
        }
        out = out ++ &[_]u8{if (upper) std.ascii.toUpper(c) else c};
        upper = false;
    }
    return out;
}

test "every page's title and blurb read the key its own name derives" {
    // Two comptime string builds for every page in the table, each a
    // branch per byte of the route name.
    @setEvalBranchQuota(20_000);
    inline for (all) |p| {
        try std.testing.expectEqual(
            @field(L.Key, keyName("title", p.name)),
            p.title,
        );
        try std.testing.expectEqual(
            @field(L.Key, keyName("blurb", p.name)),
            p.blurb,
        );
    }
}

test "no route is named after a locale this site publishes" {
    // A route called `en` would publish `/en/index.html` from two
    // writers — the locale directory's home page and that route's own
    // page under it — and the second would land at `/en/en/`. The
    // collision is silent in the output and loud here.
    inline for (@import("l10n.zig").locales) |loc| {
        try std.testing.expect(indexOf(L.tag(loc)) == null);
    }
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
