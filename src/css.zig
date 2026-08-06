//! The one thing a generated stylesheet cannot say about itself:
//! whether the names it spends are names anything declares *where the
//! rule using them applies*.
//!
//! CSS custom properties inherit, so `var(--x)` in a rule outside the
//! subtree that declares `--x` resolves to nothing — and a declaration
//! whose value resolves to nothing is dropped whole, silently. This
//! site shipped exactly that: the footer and the skip link are body
//! children, they were written with `var(--pad)`, and `--pad` is the
//! root stack's own field, published by nokre on `.nokre` and nowhere
//! above it. Every `padding` and `max-width` those two rules carried
//! was thrown away, so the footer ran unpadded across the whole window
//! for as long as nobody looked (main.zig's own comment at the rules
//! that replaced it).
//!
//! Nothing catches that: it is valid CSS, the generator's output is
//! byte-identical run to run, and the pages pass every audit — the
//! tree does not know the document around it exists. So the check is
//! this: the shell's own rules apply to the *document*, which is
//! outside `.nokre`, so every property they spend must be declared at
//! `:root`. Names published deeper are exactly the ones the shell must
//! not reach for.

const std = @import("std");

/// A comment-aware cursor over a stylesheet. Comments matter here
/// twice over: this file's own guard is *explained* in a CSS comment
/// that names the property it was written to catch, so a scanner
/// reading comments would report the sheet's own documentation as a
/// defect. CSS comments do not nest.
const Scan = struct {
    css: []const u8,
    i: usize = 0,

    /// Advances past whitespace and comments; answers false at the end.
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

    /// `--name` at the cursor, cursor left after it.
    fn takeName(self: *Scan) []const u8 {
        const start = self.i;
        self.i += 2; // "--"
        while (self.i < self.css.len and (std.ascii.isAlphanumeric(self.css[self.i]) or self.css[self.i] == '-' or self.css[self.i] == '_')) self.i += 1;
        return self.css[start..self.i];
    }
};

/// The custom properties declared inside a `:root` block — any of them,
/// including the appearance-scoped `:root[data-appearance="dark"]` and
/// the ones nested in a media query, since all of them land on the
/// document root and inherit to everything.
pub fn rootDeclared(gpa: std.mem.Allocator, css: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(gpa);
    var s: Scan = .{ .css = css };
    var depth: usize = 0;
    var root_at: ?usize = null; // the depth a :root block opened at
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
            // The selector runs to its block; what is between is
            // `:not(...)`, an attribute test or a comma, none of which
            // opens one.
            s.i += ":root".len;
            root_at = depth + 1;
        } else if (root_at != null and depth == root_at.? and s.starts("--")) {
            const name = s.takeName();
            // A declaration, not a `var()` use: only the former is
            // followed by a colon.
            var probe = s;
            if (probe.skipTrivia() and probe.starts(":")) try appendUnique(gpa, &out, name);
        } else {
            s.i += 1;
        }
    }
    return out.toOwnedSlice(gpa);
}

/// Every `var(--name)` the text spends, deduplicated. Comments are not
/// text.
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

/// The names `shell` spends that `sheet` does not publish at `:root` —
/// empty when the shell is sound. `sheet` is the whole composed
/// stylesheet, shell included, because the shell declares a few of its
/// own at `:root` too.
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

/// `expectEqualSlices` over slices-of-slices compares pointers, not
/// words.
fn expectNames(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "a property published deeper than the document root is unresolvable above it" {
    const gpa = testing.allocator;
    // The shape of the bug, minimized: `--pad` exists, but on `.nokre`,
    // and the footer is not inside one.
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
