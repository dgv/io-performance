// Run with:
// zig build-exe -O ReleaseFast optimized.zig
// sudo sysctl vm.drop_caches=3; ./optimized <kjvbible_x100.txt >/dev/null
// on macos use sync; sudo purge for cache drop

const std = @import("std");

pub fn main() anyerror!void {
    const tStart = try std.time.Instant.now();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const in = std.io.getStdIn();
    var br = std.io.bufferedReader(in.reader());
    var r = br.reader();

    var tRead: u64 = 0;

    var buf: [64 * 1024]u8 = undefined;

    var w = std.ArrayList(u8).init(allocator);
    defer w.deinit();
    var words = std.StringArrayHashMap(u32).init(allocator);
    defer words.deinit();
    while (true) {
        // Read input in 64KB blocks till EOF.
        const tRead1 = try std.time.Instant.now();
        const n = r.read(&buf) catch |err| {
            std.debug.print("{any}\n", .{err});
            break;
        };
        const tRead2 = try std.time.Instant.now();
        tRead += tRead2.since(tRead1);
        if (n == 0) {
            break;
        }

        for (buf) |c| {
            // Found a whitespace char, count last word.
            if (c <= ' ') {
                if (w.items.len > 0) {
                    const v = try words.getOrPutValue(w.items, 1);
                    if (v.found_existing) {
                        v.value_ptr.* += 1;
                    }
                    _ = try w.toOwnedSlice(); // reset word buffer
                }
                continue;
            }

            // Convert to ASCII lowercase as we go.
            var c_: u8 = undefined;
            if (c >= 'A' and c <= 'Z') {
                c_ = c + ('a' - 'A');
            }
            // Add non-space char to word buffer.
            try w.append(c_);
        }
    }
    const tProcess = try std.time.Instant.now();

    // not needed to convert into another slice for sorting
    const SortContext = struct {
        values: []u32,
        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            return ctx.values[a_index] > ctx.values[b_index];
        }
    };
    words.sort(SortContext{ .values = words.values() });
    const tSort = try std.time.Instant.now();

    var out = std.io.getStdOut().writer();
    for (words.keys()) |k| {
        try out.print("{s} {d}\n", .{ k, words.get(k).? });
    }
    const tEnd = try std.time.Instant.now();

    const elReading: f64 = @floatFromInt(tRead);
    const elProcessing: f64 = @floatFromInt(tProcess.since(tStart) - tRead);
    const elSorting: f64 = @floatFromInt(tSort.since(tProcess));
    const elOutputting: f64 = @floatFromInt(tEnd.since(tSort));
    const elTotal: f64 = @floatFromInt(tEnd.since(tStart));
    std.debug.print("Reading   : {d:.9}\n", .{elReading / std.time.ns_per_s}); // https://github.com/ziglang/zig/issues/17985
    std.debug.print("Processing: {d:.9}\n", .{elProcessing / std.time.ns_per_s}); // assume capacity?
    std.debug.print("Sorting   : {d:.9}\n", .{elSorting / std.time.ns_per_s}); // different from go the sorting order is constant
    std.debug.print("Outputting: {d:.9}\n", .{elOutputting / std.time.ns_per_s});
    std.debug.print("TOTAL     : {d:.9}\n", .{elTotal / std.time.ns_per_s});
}
