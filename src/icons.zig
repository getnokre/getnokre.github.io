//! The contract between the icons this site emits and the woff2 subset
//! it serves.
//!
//! tools/build-fonts.py subsets Lucide by codepoint, from its own
//! hand-kept ICONS table. Nothing structural ties that table to nokre
//! or to the pages — which is how a copy-glyph once shipped as tofu —
//! so the tie is checked from both ends instead. A unit test here
//! proves every table entry names a `nok.element.IconName` at that
//! exact codepoint: the wrong-codepoint class (somebody else's glyph
//! renders) dies at `zig build test`. The generator proves every icon
//! codepoint it emitted is in the table: the missing-glyph class (tofu
//! renders) dies before a byte is written (main.zig).

const std = @import("std");
const nok = @import("nokre");

const dom = nok.render.dom;

/// The subset script, as text — the same bytes the laptop's subset run
/// executes, wired in build.zig as a file import. Embedding rather than
/// reading at run time keeps the pair in one compile: a stale copy of
/// the table cannot outlive the binary that checks against it.
pub const py = @embedFile("build-fonts.py");

pub const Entry = struct { name: []const u8, codepoint: u21 };

/// The ICONS table, by line. Names are slices of `text` — the embedded
/// script is static, so nothing here outlives it.
pub fn parse(gpa: std.mem.Allocator, text: []const u8) ![]const Entry {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer entries.deinit(gpa);
    var in_table = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!in_table) {
            if (std.mem.eql(u8, trimmed, "ICONS = {")) in_table = true;
            continue;
        }
        if (std.mem.eql(u8, trimmed, "}")) return entries.toOwnedSlice(gpa);
        try entries.append(gpa, try parseEntry(trimmed));
    }
    return error.IconTableMissing;
}

/// `"name": 0xE0F5,` and no other shape. Dumb and total on purpose: a
/// comment, a blank line, a decimal literal — anything unrecognized
/// fails the parse rather than being skipped, because a skipped line is
/// a glyph both checks silently stop covering.
fn parseEntry(line: []const u8) !Entry {
    if (line.len == 0 or line[0] != '"') return error.IconTableSurprise;
    const name_end = std.mem.indexOfScalarPos(u8, line, 1, '"') orelse return error.IconTableSurprise;
    const rest = line[name_end + 1 ..];
    if (!std.mem.startsWith(u8, rest, ": 0x")) return error.IconTableSurprise;
    if (!std.mem.endsWith(u8, rest, ",")) return error.IconTableSurprise;
    const hex = rest[": 0x".len .. rest.len - ",".len];
    const cp = std.fmt.parseInt(u21, hex, 16) catch return error.IconTableSurprise;
    return .{ .name = line[1..name_end], .codepoint = cp };
}

pub fn covered(entries: []const Entry, cp: u21) bool {
    for (entries) |e| {
        if (e.codepoint == cp) return true;
    }
    return false;
}

/// nokre's name for a codepoint, for an error message somebody fixes by
/// adding one line to ICONS and re-running the subset.
pub fn nameOf(cp: u21) []const u8 {
    for (std.enums.values(nok.element.IconName)) |n| {
        if (@intFromEnum(n) == cp) return @tagName(n);
    }
    return "no nokre icon";
}

/// The Private Use Area the icon face maps its glyphs into. Keying both
/// scans on it is what lets them stay dumb: an ordinary entity or CSS
/// escape decodes outside the range and passes through unclaimed.
fn isIconCodepoint(cp: u21) bool {
    return cp >= 0xE000 and cp <= 0xF8FF;
}

/// Every icon codepoint in a run's output, deduplicated. Icons reach
/// the output in exactly two spellings: the serializer's numeric entity
/// (`&#xE09E;` — serialize.zig deliberately never puts a private-use
/// codepoint in the byte stream raw) and the stylesheet's CSS escape
/// (`\e04d` in a `content:` rule, both nokre's and the shell's).
pub fn collectEmitted(gpa: std.mem.Allocator, documents: []const []const u8, css: []const u8) ![]const u21 {
    var out: std.ArrayList(u21) = .empty;
    errdefer out.deinit(gpa);
    for (documents) |d| try scanEntities(gpa, &out, d);
    try scanEntities(gpa, &out, css);
    try scanCssEscapes(gpa, &out, css);
    return out.toOwnedSlice(gpa);
}

fn scanEntities(gpa: std.mem.Allocator, out: *std.ArrayList(u21), bytes: []const u8) !void {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, i, "&#x")) |at| {
        const start = at + "&#x".len;
        i = start;
        const end = std.mem.indexOfScalarPos(u8, bytes, start, ';') orelse continue;
        const cp = std.fmt.parseInt(u21, bytes[start..end], 16) catch continue;
        i = end + 1;
        if (isIconCodepoint(cp)) try appendUnique(gpa, out, cp);
    }
}

fn scanCssEscapes(gpa: std.mem.Allocator, out: *std.ArrayList(u21), css: []const u8) !void {
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, css, i, '\\')) |at| {
        var end = at + 1;
        while (end < css.len and end - (at + 1) < 6 and std.ascii.isHex(css[end])) end += 1;
        i = end;
        if (end == at + 1) {
            i = at + 1;
            continue;
        }
        const cp = std.fmt.parseInt(u21, css[at + 1 .. end], 16) catch continue;
        if (isIconCodepoint(cp)) try appendUnique(gpa, out, cp);
    }
}

fn appendUnique(gpa: std.mem.Allocator, out: *std.ArrayList(u21), cp: u21) !void {
    for (out.items) |seen| {
        if (seen == cp) return;
    }
    try out.append(gpa, cp);
}

/// Not `std.meta.stringToEnum`: that builds a comptime string map,
/// which trips the eval branch quota on a 1500-name enum. A linear scan
/// runs a few dozen times in one test and needs no comptime at all.
fn iconNamed(name: []const u8) ?nok.element.IconName {
    for (std.enums.values(nok.element.IconName)) |n| {
        if (std.mem.eql(u8, @tagName(n), name)) return n;
    }
    return null;
}

test "every subset entry names a nokre icon at its exact codepoint" {
    const gpa = std.testing.allocator;
    const entries = try parse(gpa, py);
    defer gpa.free(entries);
    try std.testing.expect(entries.len > 0);
    for (entries) |e| {
        const name = iconNamed(e.name) orelse {
            std.debug.print("build-fonts.py names \"{s}\", which is no nokre icon\n", .{e.name});
            return error.UnknownIconName;
        };
        // The wrong-codepoint class dies here: the enum value IS the
        // font codepoint (icon_names.zig), so disagreeing with it is
        // rendering somebody else's glyph.
        try std.testing.expectEqual(@intFromEnum(name), e.codepoint);
    }
}

test "a table line the parser does not recognize fails rather than skips" {
    const gpa = std.testing.allocator;
    const cases = [_][]const u8{
        "ICONS = {\n    # a comment\n}\n",
        "ICONS = {\n\n}\n",
        "ICONS = {\n    \"house\": 57589,\n}\n",
        "ICONS = {\n    \"house\": 0xE0F5\n}\n",
    };
    for (cases) |c| {
        try std.testing.expectError(error.IconTableSurprise, parse(gpa, c));
    }
    // ...and a table the script lost entirely is not an empty success.
    try std.testing.expectError(error.IconTableMissing, parse(gpa, "FACES = []\n"));
}

test "the scans read the two spellings icons ship in" {
    const gpa = std.testing.allocator;
    const emitted = try collectEmitted(gpa, &.{
        "<span class=\"icon\">&#xE06C;</span> &#39; &#x41; &#xE06C;",
    }, "input.check::after { content: \"\\e04d\"; margin: 0 }");
    defer gpa.free(emitted);
    try std.testing.expectEqualSlices(u21, &.{ 0xE06C, 0xE04D }, emitted);
}

test "a real emitter's icon lands in the scan, so the entity spelling is pinned" {
    // The check above spells `&#xE06C;` by hand, which proves the
    // scanner and nothing else: if the edition ever wrote a private-use
    // codepoint raw, or as `&#57452;`, or in lowercase hex, the scan
    // would go on passing while covering nothing — and the failure it
    // exists to prevent (a glyph missing from the subset, drawn as tofu
    // on every reader's screen) is invisible to every other check,
    // because the tree only ever knows names. So one icon makes the
    // whole round trip: element, emitter, markup, scan.
    const gpa = std.testing.allocator;
    var app = try nok.App.init(gpa, .{
        .viewport = .{ .w = 400, .h = 400 },
        .services = .mocks(),
    });
    defer app.deinit();
    try nok.cursor.root(&app).icon(.{ .name = .house, .label = "Home" });

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var em: dom.Emitter = .{ .gpa = gpa, .app = &app, .out = &out };
    defer em.deinit();
    try dom.content(&em);

    const emitted = try collectEmitted(gpa, &.{out.items}, "");
    defer gpa.free(emitted);
    try std.testing.expectEqualSlices(u21, &.{@intFromEnum(nok.element.IconName.house)}, emitted);
    // …and it is in the subset, which is the thing generation checks.
    const subset = try parse(gpa, py);
    defer gpa.free(subset);
    try std.testing.expect(covered(subset, @intFromEnum(nok.element.IconName.house)));
}
