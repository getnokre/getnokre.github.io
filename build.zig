const std = @import("std");
const nokre_build = @import("nokre");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("nokre", .{
        .target = target,
        .optimize = optimize,
    });
    const nokre = dep.module("nokre");

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
    // rebuild on the same two clean commits is byte-identical, so
    // `git diff --stat docs` keeps meaning what the README says.
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

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nokre", .module = nokre },
            .{ .name = "site_options", .module = options.createModule() },
        },
    });

    // The subset script, importable as text (`@embedFile` in icons.zig):
    // the ICONS table it subsets the icon face from is what the icon
    // checks — unit test and generation-time both — read as the ground
    // truth for what the served woff2 can draw.
    mod.addAnonymousImport("build-fonts.py", .{ .root_source_file = b.path("tools/build-fonts.py") });

    const gen = b.addExecutable(.{ .name = "generate", .root_module = mod });

    const run = b.addRunArtifact(gen);
    if (b.args) |args| run.addArgs(args);

    // ---- the other half of the pair --------------------------------
    //
    // The same app, for the browser: nokre's own consumer path
    // (`addApp` on a wasm target) over `src/web.zig`, which is the
    // route table this generator walks with three decls around it. The
    // module lands in the published tree beside the pages, because that
    // tree *is* the site — there is no CI and no server, so a build
    // artifact is committed like everything else here.
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
    });
    // The same options module the generator reads: the live half builds
    // the same colophon, provenance sentence included, so it needs the
    // same facts. Compiling the stamp into the wasm module keeps the
    // pair honest — the screen the browser rebuilds says what the file
    // said — at the same cost: none, on the same two clean commits.
    live.module.addImport("site_options", options.createModule());
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
