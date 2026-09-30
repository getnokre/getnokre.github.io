const std = @import("std");
const nokre_build = @import("nokre");

pub fn build(b: *std.Build) void {
    // No target option: the generator runs on the machine building it
    // and the app is built for the browser, so neither is the reader's
    // to choose.
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("nokre", .{
        .target = b.graph.host,
        .optimize = optimize,
    });

    // Where nokre's own tree lives, and where the site lands. Options
    // rather than constants so CI can point at a checkout.
    const repo = b.option([]const u8, "repo", "Path to a nokre checkout") orelse "../nokre";
    // The published tree, committed. GitHub Pages serves this folder
    // straight from the branch — there is no build running anywhere but
    // here, so what is in git is exactly what is on the site.
    const out = b.option([]const u8, "out", "Directory to write the site into") orelse "docs";

    // ---- provenance ------------------------------------------------
    //
    // The colophon names the sources a build actually read: the commit
    // each checkout was on, and whether anything uncommitted sat on top
    // of it. Asked here, at configure time, because the laptop running
    // this *is* the whole build system — there is no CI to ask instead.
    // The stamp makes the output depend on checkout state, and that is
    // the point: it is provenance. It does not cost determinism — a
    // rebuild on the same two clean commits is byte-identical but for
    // share-card.png, whose text the host's own stack renders (README,
    // "Publishing") — so `git diff --stat docs` keeps meaning what the
    // README says.
    const nokre_git = gitState(b, repo);
    const site_git = gitState(b, ".");

    const options = b.addOptions();
    options.addOption([]const u8, "repo_dir", repo);
    options.addOption([]const u8, "docs_dir", b.pathJoin(&.{ repo, "docs" }));
    options.addOption([]const u8, "out_dir", out);
    options.addOption([]const u8, "nokre_rev", nokre_git.rev);
    options.addOption(bool, "nokre_dirty", nokre_git.dirty);
    // No `site_dirty` beside it: the colophon's site clause says "built
    // atop" precisely because this tree is dirty at generation time by
    // construction — the rebuild is what dirties it — so the flag would
    // always be true and admit nothing (the sentence's rationale lives
    // in content.zig). nokre's flag stays: that checkout is only read,
    // so dirt there is a genuine finding.
    options.addOption([]const u8, "site_rev", site_git.rev);

    // ---- the app, declared once ------------------------------------
    //
    // nokre's own consumer path (`addApp` on a wasm target) over
    // `src/web.zig`, which is the route table this generator walks with
    // three decls around it. The declaration here is the site's whole
    // identity: page, manifest, icons, share card, the mark, the
    // pictures, the look. The module lands in the published tree
    // beside the pages, because that tree *is* the site — there is no
    // CI and no server, so a build artifact is committed like
    // everything else here.
    //
    // The driver's own files are not this graph's business: the
    // generator writes them, and `dom.driver_sources` hands it their
    // bytes rather than a path into a checkout (README.md's caveat on
    // `-Drepo` draws the same line). One place decides what this site
    // is made of, and it is the library.
    const live = nokre_build.addApp(dep, .{
        .name = "nokre-site",
        .root_source_file = b.path("src/web.zig"),
        .target = nokre_build.webTarget(b),
        .optimize = optimize, // addApp forces ReleaseSmall for wasm
        // A web app carries identity: page, manifest, icons and the
        // share card are outputs of this declaration, and so is the mark
        // the set derives from.
        .pkg = .{ .name = "nokre", .id = "io.github.getnokre", .version = "0.1.0", .build = 1 },
        .mark = .{ .silhouette = b.path("assets/mark.svg") },
        // The gallery's declared picture (docs/elements.md, "picture"):
        // read at build time, refused there if it is not a PNG nokre
        // can show, and published under `pictures_dir` by the
        // generator (src/main.zig).
        .pictures = &.{.{ .name = "hills", .png = b.path("assets/pictures/hills.png") }},
        // The gallery's store_badge specimen: this site is in no store,
        // so it shows another app's recorded badge screen on a stage
        // (docs/elements.md, "store_badge"). nokre's build records the
        // fixture's play and offers it under this name.
        .shows = &.{.{ .recordings = dep.namedLazyPath("store_badge_plays"), .play = "store-badges" }},
        .theme = .lamp,
        // The key rule only. This site's catalog gives nokre's chrome
        // its words; its prose is English by decision, written in the
        // route builders and in docs/ (AppOptions.L10n).
        .l10n = .{
            .template = b.path("src/l10n/site_en.arb"),
            .sources = nokre_build.pathList(b, &.{b.path("src")}),
            .words_from_catalog = false,
        },
    });
    // The same options module the generator reads: the live half builds
    // the same colophon, provenance sentence included, so it needs the
    // same facts. Compiling the stamp into the wasm module keeps the
    // pair honest — the screen the browser rebuilds says what the file
    // said — at the same cost: none, on the same two clean commits.
    live.module.addImport("site_options", options.createModule());
    // The recordings a stage fetches live in the assembled site under
    // `plays/`, named only by the gathering tool that wrote them, so the
    // generator copies them out of that tree by its manifest rather than
    // knowing their names. Its own options module rather than a field
    // on `site_options`: the live half imports that one, and the
    // assembled tree holds the live half, so the pair would be a loop.
    const site_tree = b.addOptions();
    site_tree.addOptionPath("dir", live.web.?);

    // ---- the generator, the other half of the pair -------------------
    //
    // A tool the build runs on this machine, importing the app's own
    // configured nokre (`App.tool_nokre`) rather than the dependency's
    // unconfigured module: the mark face the pages draw, the picture
    // names they spell, the declared look and address form all live in
    // the declaration above, and only that module carries them
    // (../nokre/docs/static-sites.md, "A generator's nokre is the
    // app's"). The two halves are one tree: the face and the mark the
    // generator writes are the ones the wasm module draws from.
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nokre", .module = live.tool_nokre },
            .{ .name = "site_options", .module = options.createModule() },
            .{ .name = "site_tree", .module = site_tree.createModule() },
        },
    });
    // The derived identity set — favicon.ico, the adaptive favicon.svg,
    // the touch icons, share-card.png — as bytes the generator writes
    // into its own tree, read out of the assembled site so the two
    // trees cannot disagree.
    mod.addImport("web_assets", nokre_build.webAssets(live, b));

    const gen = b.addExecutable(.{ .name = "generate", .root_module = mod });

    const run = b.addRunArtifact(gen);
    if (b.args) |args| run.addArgs(args);

    const publish = b.addUpdateSourceFiles();
    publish.addCopyFileToSource(live.artifact.getEmittedBin(), b.pathJoin(&.{ out, "app.wasm" }));

    const site = b.step("site", "Generate the site into --out (default: docs/)");
    site.dependOn(&run.step);
    site.dependOn(&publish.step);
    b.getInstallStep().dependOn(site);

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run the generator's unit tests").dependOn(&b.addRunArtifact(tests).step);
}

/// One checkout's provenance: the short hash of HEAD, and whether the
/// working tree holds more than that commit. `status --porcelain`
/// printing nothing is git's own definition of clean, so it is this
/// one's too — no parsing, just "did it say anything".
fn gitState(b: *std.Build, dir: []const u8) struct { rev: []const u8, dirty: bool } {
    const root = b.pathFromRoot(dir);
    const rev = b.run(&.{ "git", "-C", root, "rev-parse", "--short", "HEAD" });
    const status = b.run(&.{ "git", "-C", root, "status", "--porcelain" });
    return .{
        .rev = std.mem.trim(u8, rev, " \t\r\n"),
        .dirty = std.mem.trim(u8, status, " \t\r\n").len != 0,
    };
}
