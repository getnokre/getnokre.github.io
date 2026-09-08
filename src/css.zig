const std = @import("std");

const Scan = struct {
    css: []const u8,
    i: usize = 0,

    fn skipTrivia(self: *Scan) bool {
        while (self.i < self.css.len) {
            if (std.ascii.isWhitespace(self.css[self.i])) {
                self.i += 1;
            } else if (self.starts("/*")) {
                self.i = if (std.mem.indexOfPos(u8, self.css, self.i + 2, "*/")) |at| at + 2 else self.css.len;
            } else return true;
        }
        return false;
    }

    fn starts(self: *const Scan, needle: []const u8) bool {
        return std.mem.startsWith(u8, self.css[self.i..], needle);
    }

    fn takeName(self: *Scan) []const u8 {
        const start = self.i;
        self.i += 2; // "--"
        while (self.i < self.css.len and (std.ascii.isAlphanumeric(self.css[self.i]) or self.css[self.i] == '-' or self.css[self.i] == '_')) self.i += 1;
        return self.css[start..self.i];
    }
};

pub fn rootDeclared(gpa: std.mem.Allocator, css: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(gpa);
    var s: Scan = .{ .css = css };
    var depth: usize = 0;
    var root_at: ?usize = null;
    while (s.skipTrivia()) {
        if (s.starts("{")) {
            depth += 1;
            s.i += 1;
        } else if (s.starts("}")) {
            if (root_at) |d| if (depth == d) {
                root_at = null;
            };
            depth -|= 1;
            s.i += 1;
        } else if (root_at == null and s.starts(":root")) {
            s.i += ":root".len;
            root_at = depth + 1;
        } else if (root_at != null and depth == root_at.? and s.starts("--")) {
            const name = s.takeName();
            var probe = s;
            if (probe.skipTrivia() and probe.starts(":")) try appendUnique(gpa, &out, name);
        } else {
            s.i += 1;
        }
    }
    return out.toOwnedSlice(gpa);
}

pub fn varsUsed(gpa: std.mem.Allocator, css: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(gpa);
    var s: Scan = .{ .css = css };
    while (s.skipTrivia()) {
        if (s.starts("var(--")) {
            s.i += "var(".len;
            try appendUnique(gpa, &out, s.takeName());
        } else s.i += 1;
    }
    return out.toOwnedSlice(gpa);
}

pub fn unresolvable(gpa: std.mem.Allocator, sheet: []const u8, shell: []const u8) ![]const []const u8 {
    const declared = try rootDeclared(gpa, sheet);
    defer gpa.free(declared);
    const used = try varsUsed(gpa, shell);
    defer gpa.free(used);
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(gpa);
    for (used) |name| {
        if (has(declared, name)) continue;
        try out.append(gpa, name);
    }
    return out.toOwnedSlice(gpa);
}

fn has(list: []const []const u8, needle: []const u8) bool {
    for (list) |s| {
        if (std.mem.eql(u8, s, needle)) return true;
    }
    return false;
}

fn appendUnique(gpa: std.mem.Allocator, out: *std.ArrayList([]const u8), name: []const u8) !void {
    if (has(out.items, name)) return;
    try out.append(gpa, name);
}

const testing = std.testing;

fn expectNames(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "a property published deeper than the document root is unresolvable above it" {
    const gpa = testing.allocator;
    const sheet =
        \\:root { --page-pad: 16px; --mid: #666; }
        \\.nokre { --pad: var(--page-pad); padding: var(--pad); }
        \\footer { padding: var(--pad); color: var(--mid); }
    ;
    const shell = "footer { padding: var(--pad); color: var(--mid); }";
    const bad = try unresolvable(gpa, sheet, shell);
    defer gpa.free(bad);
    try testing.expectEqual(@as(usize, 1), bad.len);
    try testing.expectEqualStrings("--pad", bad[0]);
}

test "root declarations are collected wherever the root block is written" {
    const gpa = testing.allocator;
    const sheet =
        \\:root { --a: 1px; }
        \\@media (prefers-color-scheme: dark) { :root:not([data-appearance]) { --b: 2px; } }
        \\:root[data-appearance="dark"] { --c: 3px; }
        \\@media (min-width: 900px) { :root { --d: 4px; } }
        \\.nokre { --e: 5px; }
    ;
    const declared = try rootDeclared(gpa, sheet);
    defer gpa.free(declared);
    try expectNames(&.{ "--a", "--b", "--c", "--d" }, declared);
}

test "the use scan reads every spelling and repeats once" {
    const gpa = testing.allocator;
    const used = try varsUsed(gpa, "a { x: var(--one); y: calc(var(--two) + 2 * var(--one)); }");
    defer gpa.free(used);
    try expectNames(&.{ "--one", "--two" }, used);
}
