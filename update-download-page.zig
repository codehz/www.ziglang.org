const std = @import("std");
const path = std.fs.path;
const mem = std.mem;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;

    const download_dir = "www" ++ path.sep_str ++ "download";
    try std.fs.cwd().makePath(download_dir);
    {
        const out_file = download_dir ++ path.sep_str ++ "index.html";
        const in_file = "src" ++ path.sep_str ++ "download" ++ path.sep_str ++ "index.html";
        try render(allocator, in_file, out_file, .html);
    }
    {
        const out_file = download_dir ++ path.sep_str ++ "index.json";
        const in_file = "src" ++ path.sep_str ++ "download" ++ path.sep_str ++ "index.json";
        try render(allocator, in_file, out_file, .plain);
    }
}

fn render(
    allocator: *mem.Allocator,
    in_file: []const u8,
    out_file: []const u8,
    fmt: enum {
        html,
        plain,
    },
) !void {
    const in_contents = try std.fs.cwd().readFileAlloc(allocator, in_file, 1 * 1024 * 1024);

    var vars = try std.process.getEnvMap(allocator);

    var buffer = try std.Buffer.initSize(allocator, 0);
    errdefer buffer.deinit();

    const State = enum {
        Start,
        OpenBrace,
        VarName,
        EndBrace,
    };
    const out = buffer.outStream();
    var state = State.Start;
    var var_name_start: usize = undefined;
    var line: usize = 1;
    for (in_contents) |byte, index| {
        switch (state) {
            State.Start => switch (byte) {
                '{' => {
                    state = State.OpenBrace;
                },
                else => try out.writeByte(byte),
            },
            State.OpenBrace => switch (byte) {
                '{' => {
                    state = State.VarName;
                    var_name_start = index + 1;
                },
                else => {
                    try out.writeByte('{');
                    try out.writeByte(byte);
                    state = State.Start;
                },
            },
            State.VarName => switch (byte) {
                '}' => {
                    const var_name = in_contents[var_name_start..index];
                    if (vars.get(var_name)) |value| {
                        const trimmed = mem.trim(u8, value, " \r\n");
                        if (fmt == .html and mem.endsWith(u8, var_name, "BYTESIZE")) {
                            try out.print("{Bi:.1}", .{try std.fmt.parseInt(u64, trimmed, 10)});
                        } else {
                            try out.writeAll(trimmed);
                        }
                    } else {
                        std.debug.warn("line {}: missing variable: {}\n", .{ line, var_name });
                        try out.writeAll("(missing)");
                    }
                    state = State.EndBrace;
                },
                else => {},
            },
            State.EndBrace => switch (byte) {
                '}' => {
                    state = State.Start;
                },
                else => {
                    std.debug.warn("line {}: invalid byte: '0x{x}'", .{ line, byte });
                    std.process.exit(1);
                },
            },
        }
        if (byte == '\n') {
            line += 1;
        }
    }
    try std.fs.cwd().writeFile(out_file, buffer.span());
}
