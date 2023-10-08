// This is a modified version of buffered_writer.zig from the zig standard library.

// Copyright (c) Zig contributors 
// MIT-License (text at bottom)

const std = @import("std");

const io = std.io;
const mem = std.mem;



pub fn NyafferedWriter(comptime buffer_size: usize, comptime WriterType: type) type {
    return struct {
        unbuffered_writer: WriterType,
        buf: [buffer_size]u8 = undefined,
        end: usize = 0,

        const Error = {};
        pub const Writer = io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn flush(self: *Self) !void {
            try self.unbuffered_writer.writeAll(self.buf[0..self.end]);
            self.end = 0;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        // It is the responsibility of the caller to not violate the length of the buffer
        // Boundschecking in the write function has been omitted for performance reasons.
        pub inline fn write(self: *Self, bytes: []const u8) void {
            var _bytes = bytes;
            while (_bytes.len >= 8) {
                @memcpy(self.buf[self.end..self.end+8], _bytes[0..8]);
                self.end += 8;
                _bytes = _bytes[8..];
            } else {
                switch(_bytes.len) {
                    inline 0...7 => |i| {
                        @memcpy(self.buf[self.end..self.end+i], _bytes[0..i]);
                        self.end += i;
                    },
                    else => unreachable,
                }
            }
        }
    };
}

// MIT-License text:

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.