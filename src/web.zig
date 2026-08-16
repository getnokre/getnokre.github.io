const std = @import("std");
const nok = @import("nokre");

const content = @import("content.zig");
const links = @import("links.zig");
const pages = @import("pages.zig");

comptime {
    _ = nok;
}

const initial: nok.Size = .{ .w = 320, .h = 568 };

var sources: [pages.all.len][]const u8 = @splat("");
var site: content.Site = undefined;
var destinations: [pages.destinations.len]nok.Destination = undefined;
var resolver: links.Live = undefined;

pub fn nokreWebSeed(bytes: []const u8) void {
    for (pages.all, 0..) |p, i| {
        if (p.md.len != 0) sources[i] = bytes;
    }
}

pub fn nokreWebBuild(gpa: std.mem.Allocator) !*nok.App {
    site = .{ .gpa = gpa, .sources = &sources };
    resolver = .{ .arena = .init(gpa) };

    const app = try gpa.create(nok.App);
    app.* = try nok.App.init(gpa, .{
        .viewport = initial,
        .routes = &content.routes,
        .ctx = &site,
    });
    for (pages.destinations, 0..) |name, i| {
        destinations[i] = .{ .route = name, .icon = pages.find(name).?.icon };
    }
    try app.setNav(&destinations);
    try app.router.switchTo(app, "home");
    return app;
}

pub fn nokreWebRefs(_: *nok.App) nok.render.dom.Refs {
    return resolver.refs();
}
