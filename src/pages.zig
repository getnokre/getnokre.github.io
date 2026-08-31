const std = @import("std");
const nok = @import("nokre");

const L = @import("l10n.zig").L;

pub const IconName = nok.element.IconName;

pub const Kind = enum {
    home,
    docs_index,
    internals_index,
    palette,
    gallery,
    colophon,
    not_found,
    doc,
};

pub const Page = struct {
    name: []const u8,
    title: L.Key,
    blurb: L.Key,
    icon: IconName,
    kind: Kind = .doc,
    md: []const u8 = "",
    track: enum { none, consumer, contributor } = .none,
};

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
