const std = @import("std");
const builtin = @import("builtin");
const NyaWrite = @import("nyaffered_writer.zig").NyafferedWriter;


// Eventually make this configurable :3
const nyas = [_][]const u8{ "nya ", "nyaa~ ", "mwrp ", "mwrwrwp ", "uwu ", ">w< ", "ehehe~ " };

const MaxNya = blk: {
    comptime var maxlen: usize = 0;
    for (nyas) |nya| {
        maxlen = @max(nya.len, maxlen);
    }
    break :blk maxlen;
};
pub const PL = 8; // padding length
pub const precomp = 4;
var prng = std.rand.DefaultPrng.init(0);
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

    // precompute an appropriate buffer size
    comptime var nyalist_len: usize = std.math.pow(usize, nyas.len, precomp); 
    const for_chunks = 100;
    @setEvalBranchQuota(for_chunks * 10);
    const chunksize = MaxNya * precomp * for_chunks;

    // Initialize the special NyafferedWriter, which brings the nyas
    var buf_writer = NyaWrite(chunksize, @TypeOf(std.io.getStdOut().writer()))
    { .unbuffered_writer = std.io.getStdOut().writer() };
    // Current limitation of zig, cant initialize with pointer value from itself.
    buf_writer.init();

    // The nyalist will store precomputed strings of nyas up to precomp-length.
    var nyalist = std.ArrayList([]u8).init(alloc);
    defer {
        for (nyalist.items) |item| {
            const internal_length = (item.len / PL) * PL + PL;
            alloc.free(item.ptr[0..internal_length]);
        }
        nyalist.deinit();
    }

    // also we dont need to keep precomp fixed!
    // we can calculate it based on the amounts of nyas
    // this increases performance for low amounts of nyas

    // this is probably not the best way to precompute the nyas
    // we already know how long the final string is going to be
    // so there is technically no need to use an ArrayList.
    { var idx = [_]usize{0}**precomp; 
    while (idx[idx.len-1] < nyas.len) {
        var alist = std.ArrayList(u8).init(alloc);
        defer alist.deinit();
        for (idx) |j| {
            try alist.appendSlice(nyas[j]);
        }        

        // pad the length to a multiple of 8
        // we know that len > 0
        const real_length = alist.items.len;
        try alist.appendNTimes(' ',  (alist.items.len/PL + 1)*PL - alist.items.len);

        // the memory allocated by array list is managed by the nyalist now
        var cpy = try alloc.dupe(u8, alist.items);

        // check for alignment
        if (!std.mem.isAligned(@intFromPtr(cpy.ptr), PL)) {
            return error.NyaNyotAligned;
        }

        // now nyalist contains a slice that has padding to the nearest 8-boundary
        // put the real length back for ease of implementation
        try nyalist.append(@alignCast(cpy[0..real_length]));

        // counts up the indices one at a time
         { comptime var i: usize = 0; 
        inline while (i < idx.len) : (i += 1) {
            idx[i] += if (i == 0 or idx[i-1] == nyas.len) 1 else 0;
            if (i > 0) idx[i-1] = if (idx[i-1] == nyas.len) 0 else idx[i-1];
        }}
    }}
    
    std.log.debug(\\ Interesting nya stats! 
    \\ Number of precomputed nyas {}
    \\ Precomputed index size {}
    , .{nyalist.items.len, precomp});

    // In Debug builds, tell us something about the length of the precomputed nya strings.
    // This is occasionally useful to optimize the memcpy operation in the NyafferedWriter.
    if (builtin.mode == .Debug) {
        // compute the lengths of nyas
        var stats = std.AutoHashMap(usize, usize).init(alloc);
        defer stats.deinit();
        for (nyalist.items) |nyastr| {
            if (stats.contains(nyastr.len)) {
                const nyalen = stats.get(nyastr.len).?;
                try stats.put(nyastr.len, nyalen+1);
            } else {
                try stats.put(nyastr.len, 1);
            }
        }

        { var it = stats.iterator();
        var statlist = std.ArrayList(std.AutoHashMap(usize, usize).Entry).init(alloc);
        defer statlist.deinit();
        while (it.next()) |stat| {
            try statlist.append(stat);
        }

        std.sort.heap(@TypeOf(statlist.pop()), statlist.items, .{}, ltf);
        for (statlist.items) |stat| {
            std.log.debug("{}: {}\n", .{stat.key_ptr.*, stat.value_ptr.*});
        }
        }

        // As nyalist_len is precomputed, it may be out-of-sync if significant changes to nyalist occur.
        std.debug.assert(nyalist.items.len == nyalist_len);
    }


    // Split up the nyas into a fast path and a slow path
    // Nyas are nya-ed chunkwise until we hit less than a full chunk
    // then we use a slow path.
    var rems = nya_num % (precomp * for_chunks);
    nya_num -= rems;

    while (nya_num > 0) {
        // This breaks for precomps that are too large
        // Todo: Find a flexible way to get a reasonable native Unsigned-Type
        const RngType = u16;
        var precalc_rng: [for_chunks]RngType = undefined;
        // Pcg beats by other RNGs by kilometers
        pcg.fill(std.mem.sliceAsBytes(precalc_rng[0..]));
        for (0..precalc_rng.len) |i| {precalc_rng[i] = precalc_rng[i] % @as(u16, nyalist_len); }

        for (0..for_chunks) |i| {
            var mlem = precalc_rng[i];
            buf_writer.write_fast(nyalist.items[mlem]);
        }
        nya_num -= precomp * for_chunks;
        try buf_writer.flush();
    }

    while (rems > 0) : (rems -= 1) {
        var mlem = prng.next() % nyas.len;
        buf_writer.write(nyas[mlem]);
    }

    try buf_writer.flush();
    try stdout.print("\n", .{});
}
