//! Copyright (c) 2024 Rylee Alanza Lyman (zig port)
//! Copyright (c) 2022-2023 Devine Lu Linvega, Andrew Alderwick
//!
//! Permission to use, copy, modify, and distribute this software for any
//! purpose with or without fee is hereby granted, provided that the above
//! copyright notice and this permission notice appear in all copies.
//!
//! THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//! WITH REGARD TO THIS SOFTWARE.

pub const InputType = enum(u8) { STD, ARG, EOA, END };

pub fn input(u: *Uxn, byte: u8, kind: InputType) bool {
    const d: [*]u8 = u.dev[0x10..].ptr;
    d[0x2] = byte;
    d[0x7] = @intFromEnum(kind);
    const short: Short = short: {
        const high = d[0];
        const low = d[1];
        break :short .{ .high = high, .low = low };
    };
    return u.emuEval(short.toU16());
}

pub fn listen(u: *Uxn, start_idx: usize, args: []const [:0]const u8) void {
    if (start_idx >= args.len) return;
    for (args[start_idx..], start_idx..) |arg, i| {
        for (arg) |byte| {
            _ = input(u, byte, .ARG);
        }
        _ = input(u, '\n', if (i == args.len - 1) .END else .EOA);
    }
}

pub fn deo(d: [*]u8, port: u8) void {
    switch (port) {
        0x18 => {
            const stdout = std.io.getStdOut().writer();
            stdout.print("{c}", .{d[port]}) catch std.debug.panic("writing to stdout failed!", .{});
        },
        0x19 => {
            const stderr = std.io.getStdErr().writer();
            stderr.print("{c}", .{d[port]}) catch std.debug.panic("writing to stderr failed!", .{});
        },
        else => {},
    }
}

const std = @import("std");
const uxn = @import("uxn");
const Uxn = uxn.Uxn;
const Short = uxn.Short;
