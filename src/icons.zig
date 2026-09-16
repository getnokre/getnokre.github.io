const std = @import("std");
const nok = @import("nokre");

const dom = nok.render.dom;

pub fn nameOf(cp: u21) []const u8 {
    for (std.enums.values(nok.element.IconName)) |n| {
        if (@intFromEnum(n) == cp) return @tagName(n);
    }
    return "no nokre icon";
}

fn isIconCodepoint(cp: u21) bool {
    return cp >= 0xE000 and cp <= 0xF8FF;
}

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

test "the scans read the two spellings icons ship in" {
    const gpa = std.testing.allocator;
    const emitted = try collectEmitted(gpa, &.{
        "<span class=\"icon\">&#xE06C;</span> &#39; &#x41; &#xE06C;",
    }, "input.check::after { content: \"\\e04d\"; margin: 0 }");
    defer gpa.free(emitted);
    try std.testing.expectEqualSlices(u21, &.{ 0xE06C, 0xE04D }, emitted);
}

test "a real emitter's icon lands in the scan, so the entity spelling is pinned" {
    const gpa = std.testing.allocator;
    var app = try nok.App.init(gpa, .{
        .viewport = .{ .w = 400, .h = 400 },
        .services = .mocks(),
    });
    defer app.deinit();
    try nok.cursor.root(&app).icon(.{ .name = .lucide_house, .label = "Home" });

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var em: dom.Emitter = .{ .gpa = gpa, .app = &app, .out = &out };
    defer em.deinit();
    try dom.content(&em);

    const emitted = try collectEmitted(gpa, &.{out.items}, "");
    defer gpa.free(emitted);
    try std.testing.expectEqualSlices(u21, &.{@intFromEnum(nok.element.IconName.lucide_house)}, emitted);
    try std.testing.expect(nok.render.icon_face.maps(@intFromEnum(nok.element.IconName.lucide_house)));
}
