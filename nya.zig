const std = @import("std");
const builtin = @import("builtin");
const NyaWrite = @import("nyaffered_writer.zig").NyafferedWriter;


// Eventually make this configurable :3
const nyas = [_][]const u8{ "nya", "nyaa~", "mwrp", "mwrwrwp", "uwu", ">w<", "ehehe~" };

const MaxNya = blk: {
    comptime var maxlen: usize = 0;
    for (nyas) |nya| {
        maxlen = @max(nya.len, maxlen);
    }
    break :blk maxlen;
};

const NyaTotalPL = blk: {
    var sum: usize = 0;
    for (nyas) |nya| {
        if (nya.len == 0) @compileError("One of the nyas is zero-length.");
        sum += 8 * ((nya.len - 1) / 8 + 1);
    }
    break :blk sum;
};

const nya_string = blk: {
    var buf = [_]u8{' '}**NyaTotalPL;
    var cursor = 0;
    for (nyas) |nya| {
        var steps = (nya.len - 1) / 8 + 1;
        const new_cursor = cursor + steps;
        @memcpy(buf[8*cursor..8*cursor+nya.len], nya);
        cursor = new_cursor;
    }
    break :blk buf;
};

const nya_lens = blk: {
    var lens = [_]u8{0}**nyas.len;
    for (nyas, 0..) |nya, i| {
        lens[i] = @intCast(nya.len + 1);
    }
    break :blk lens;
};

var pcg = std.rand.Pcg.init(0);
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();

fn ltf(context: @TypeOf(.{}), lhs: std.AutoHashMap(usize, usize).Entry, rhs: std.AutoHashMap(usize, usize).Entry) bool {
    _ = context;
    return lhs.key_ptr.* < rhs.key_ptr.*;
}

pub fn main() !void {
    // Classic Zig stuff
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Timer for benching during development
    var timer = try std.time.Timer.start();
    defer {
        const time: u64 = timer.read();
        const timef: f64 = @floatFromInt(time);
        const time_s = timef / std.time.ns_per_s;
        stderr.print("\n\nTime elapsed: {d:.4} s\n", .{time_s}) catch {};
    }

    // Accept a number as an argument, this number specfies the number of nyas
    // to print.
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    
    if (args.len != 2) {
        try stderr.print("Usage: {s} <number of nyas>\n", .{args[0]});
        return;
    }
    var nya_num = try std.fmt.parseInt(u64, args[1], 10);
    const chunksize = 4096;

    // Initialize the special NyafferedWriter, which brings the nyas
    var buf_writer = NyaWrite(chunksize, @TypeOf(std.io.getStdOut().writer()))
    { .unbuffered_writer = std.io.getStdOut().writer() };
    // Current limitation of zig, cant initialize with pointer value from itself.
    buf_writer.init();

    while (nya_num > 0) {
        const nya_this_iteration = @min(64, nya_num);
        var precalc_rng: [64]u8 = undefined;
        // Pcg beats by other RNGs by kilometers
        pcg.fill(std.mem.sliceAsBytes(precalc_rng[0..]));
        for (0..precalc_rng.len) |i| {
            precalc_rng[i] = precalc_rng[i] % @as(u8, nyas.len); 
        }

        for (0..nya_this_iteration) |i| {
            const choice = precalc_rng[i];
            const nyalen = nya_lens[choice];
            var str_choice: [8]u8 = undefined;
            @memcpy(str_choice[0..], nya_string[choice*8..choice*8 + 8]);
            buf_writer.write_fast(&str_choice, nyalen);
        }
        
        nya_num -= nya_this_iteration;
        
        if (buf_writer.end.len < precalc_rng.len * MaxNya + 1) {
            try buf_writer.flush();
        }
    }

    try buf_writer.flush();
    try stdout.print("\n", .{});
}
