const std = @import("std");
const random = std.crypto.random;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() anyerror!void {
    var paths = std.ArrayList([]const u8).init(allocator);
    {
        const paths_list = try std.io.getStdIn().reader().readAllAlloc(allocator, std.math.maxInt(usize));
        var paths_list_lines = std.mem.split(paths_list, "\n");
        while (paths_list_lines.next()) |path| try paths.append(path);
    }

    while (true) {
        const path = randomChoice(paths.items) catch return error.NoInputPaths;
        const file = try std.fs.cwd().openFile(path, .{ .write = true });
        const source = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        const source_z = try std.mem.dupeZ(allocator, u8, source);
        const tree = try std.zig.parse(allocator, source_z);
        if (proposeMutation(source, tree)) |mutation| {
            const mutated = try std.mem.concat(allocator, u8, &.{
                source[0..mutation.range[0]],
                mutation.replacement,
                source[mutation.range[1]..],
            });
            if (!std.mem.eql(u8, source, mutated)) {
                try file.seekTo(0);
                try file.setEndPos(0);
                try file.writer().writeAll(mutated);
                break;
            }
        } else |err| {
            switch (err) {
                error.NoMutation => continue,
                else => return err,
            }
        }
    }
}

const Strategy = enum {
    RemoveStatement,
    ChangeBooleanLiteral,
    ChangeIntegerLiteral,
    ChangeBooleanOp,
    ChangeIntegerOp,
    ChangeComparisonOp,
    // TODO
    // change string literal
    // change bit ops
    // mess with `while` conditions
    // add break/continue inside loop
    // switch variables (of same type)
};

const Mutation = struct {
    range: [2]usize,
    replacement: []const u8,
};

fn proposeMutation(source: []const u8, tree: std.zig.ast.Tree) !Mutation {
    const strategy_ix = random.uintLessThan(usize, @typeInfo(Strategy).Enum.fields.len);
    switch (@intToEnum(Strategy, @intCast(@typeInfo(Strategy).Enum.tag_type, strategy_ix))) {
        .RemoveStatement => {
            const node_id = try randomNodeByTag(tree, &.{ .@"defer", .@"errdefer", .assign_mul, .assign_div, .assign_mod, .assign_add, .assign_sub, .assign_bit_shift_left, .assign_bit_shift_right, .assign_bit_and, .assign_bit_xor, .assign_bit_or, .assign_mul_wrap, .assign_add_wrap, .assign_sub_wrap, .assign });
            var start = tokenRange(tree, tree.firstToken(node_id))[0];
            while (source[start - 1] == ' ') start -= 1;
            var end = tokenRange(tree, tree.lastToken(node_id))[1];
            if (source[end] == ';') end += 1;
            if (source[end] == '\n') end += 1;
            return Mutation{ .range = .{ start, end }, .replacement = "" };
        },
        .ChangeBooleanLiteral => {
            const node_id = try randomNodeByTag(tree, &.{ .false_literal, .true_literal });
            const range = tokenRange(tree, tree.nodes.items(.main_token)[node_id]);
            const replacement = if (random.boolean()) "true" else "false";
            return Mutation{ .range = range, .replacement = replacement };
        },
        .ChangeIntegerLiteral => {
            const node_id = try randomNodeByTag(tree, &.{.integer_literal});
            const range = tokenRange(tree, tree.nodes.items(.main_token)[node_id]);
            const text = source[range[0]..range[1]];
            const int = std.fmt.parseInt(i128, text, 0) catch 0;
            const diff =
                @floatToInt(i128, @floor(random.floatExp(f64))) *
                if (random.boolean()) @as(i128, 1) else (-1);
            const replacement_int = int + diff;
            var replacement = std.ArrayList(u8).init(allocator);
            if (std.mem.startsWith(u8, text, "0x")) {
                try std.fmt.format(replacement.writer(), "0x{x}", .{replacement_int});
            } else if (std.mem.startsWith(u8, text, "0o")) {
                try std.fmt.format(replacement.writer(), "0o{o}", .{replacement_int});
            } else if (std.mem.startsWith(u8, text, "0b")) {
                try std.fmt.format(replacement.writer(), "0b{b}", .{replacement_int});
            } else {
                try std.fmt.format(replacement.writer(), "{}", .{replacement_int});
            }
            return Mutation{ .range = range, .replacement = replacement.items };
        },
        .ChangeBooleanOp => {
            const ops: []const std.zig.ast.Node.Tag = &.{ .bool_and, .bool_or };
            const node_id = try randomNodeByTag(tree, ops);
            const range = tokenRange(tree, tree.nodes.items(.main_token)[node_id]);
            const replacement = switch (try randomChoice(ops)) {
                .bool_and => "and",
                .bool_or => "or",
                else => unreachable,
            };
            return Mutation{ .range = range, .replacement = replacement };
        },
        .ChangeIntegerOp => {
            const ops: []const std.zig.ast.Node.Tag = &.{ .mul, .div, .mod, .add, .sub, .mul_wrap, .add_wrap, .sub_wrap };
            const node_id = try randomNodeByTag(tree, ops);
            const range = tokenRange(tree, tree.nodes.items(.main_token)[node_id]);
            const replacement = switch (try randomChoice(ops)) {
                .mul => "*",
                .div => "/",
                .mod => "%",
                .add => "+",
                .sub => "-",
                .mul_wrap => "*%",
                .add_wrap => "+%",
                .sub_wrap => "-%",
                else => unreachable,
            };
            return Mutation{ .range = range, .replacement = replacement };
        },
        .ChangeComparisonOp => {
            const ops: []const std.zig.ast.Node.Tag = &.{ .equal_equal, .bang_equal, .less_than, .greater_than, .less_or_equal, .greater_or_equal };
            const node_id = try randomNodeByTag(tree, ops);
            const range = tokenRange(tree, tree.nodes.items(.main_token)[node_id]);
            const replacement = switch (try randomChoice(ops)) {
                .equal_equal => "==",
                .bang_equal => "!=",
                .less_than => "<",
                .greater_than => ">",
                .less_or_equal => "<=",
                .greater_or_equal => ">=",
                else => unreachable,
            };
            return Mutation{ .range = range, .replacement = replacement };
        },
    }
}

fn randomChoice(slice: anytype) !std.meta.Child(@TypeOf(slice)) {
    if (slice.len == 0) return error.NoMutation;
    return slice[random.uintLessThan(usize, slice.len)];
}

fn randomNodeByTag(tree: std.zig.ast.Tree, node_tags: []const std.zig.ast.Node.Tag) !std.zig.ast.TokenIndex {
    return randomChoice(try nodesByTag(tree, node_tags));
}

fn nodesByTag(tree: std.zig.ast.Tree, node_tags: []const std.zig.ast.Node.Tag) ![]const std.zig.ast.TokenIndex {
    var node_ids = std.ArrayList(std.zig.ast.TokenIndex).init(allocator);
    var node_id: std.zig.ast.TokenIndex = 0;
    while (node_id < tree.nodes.len) : (node_id += 1) {
        const tag = tree.nodes.items(.tag)[node_id];
        for (node_tags) |node_tag|
            if (tag == node_tag)
                try node_ids.append(node_id);
    }
    return node_ids.toOwnedSlice();
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
