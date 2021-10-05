const std = @import("std");
const random = std.crypto.random;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator;

    var paths = std.ArrayList([]const u8).init(allocator);
    {
        const paths_list = try std.io.getStdIn().reader().readAllAlloc(allocator, std.math.maxInt(usize));
        var paths_list_lines = std.mem.split(paths_list, "\n");
        while (paths_list_lines.next()) |path| try paths.append(path);
    }

    while (true) {
        const path_ix = random.uintLessThan(usize, paths.items.len);
        const file = try std.fs.cwd().openFile(paths.items[path_ix], .{ .write = true });
        const source = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        const source_z = try std.mem.dupeZ(allocator, u8, source);
        const tree = try std.zig.parse(allocator, source_z);
        if (try proposeMutation(allocator, source, tree)) |mutation| {
            const mutated = try std.mem.concat(allocator, u8, &.{
                source[0..mutation.range[0]],
                mutation.replacement,
                source[mutation.range[1]..],
            });
            if (!std.mem.eql(u8, source, mutated)) {
                try file.seekTo(0);
                try file.setEndPos(0);
                try file.writer().writeAll(mutated);
                return;
            }
        }
    }
}

const Mutation = struct {
    range: [2]usize,
    replacement: []const u8,
};

fn proposeMutation(allocator: *std.mem.Allocator, source: []const u8, tree: std.zig.ast.Tree) !?Mutation {
    var ranges = std.ArrayList([2]usize).init(allocator);
    var node_id: usize = 0;
    while (node_id < tree.nodes.len) : (node_id += 1) {
        const tag = tree.nodes.items(.tag)[node_id];
        if (tag == .integer_literal)
            try ranges.append(tokenRange(tree, tree.nodes.items(.main_token)[node_id]));
    }
    if (ranges.items.len == 0) return null;
    const range = ranges.items[random.uintLessThan(usize, ranges.items.len)];
    const int_source = source[range[0]..range[1]];
    const int = std.fmt.parseInt(i128, int_source, 0) catch 0;
    const diff =
        @floatToInt(i128, @floor(random.floatExp(f64))) *
        if (random.boolean()) @as(i128, 1) else (-1);
    const replacement_int = int + diff;
    var replacement = std.ArrayList(u8).init(allocator);
    if (std.mem.startsWith(u8, int_source, "0x")) {
        try std.fmt.format(replacement.writer(), "0x{x}", .{replacement_int});
    } else if (std.mem.startsWith(u8, int_source, "0o")) {
        try std.fmt.format(replacement.writer(), "0o{o}", .{replacement_int});
    } else if (std.mem.startsWith(u8, int_source, "0b")) {
        try std.fmt.format(replacement.writer(), "0b{b}", .{replacement_int});
    } else {
        try std.fmt.format(replacement.writer(), "{}", .{replacement_int});
    }
    return Mutation{ .range = range, .replacement = replacement.items };
}

fn tokenRange(tree: std.zig.ast.Tree, token_index: std.zig.ast.TokenIndex) [2]usize {
    const token_starts = tree.tokens.items(.start);
    var tokenizer: std.zig.Tokenizer = .{
        .buffer = tree.source,
        .index = token_starts[token_index],
        .pending_invalid_token = null,
    };
    const token = tokenizer.next();
    return .{ token.loc.start, token.loc.end };
}
