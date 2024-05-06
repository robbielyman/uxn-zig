//! Copyright (c) 2024 Rylee Alanza Lyman (zig port)
//! Copyright (c) 2022-2023 Devine Lu Linvega, Andrew Alderwick
//!
//! Permission to use, copy, modify, and distribute this software for any
//! purpose with or without fee is hereby granted, provided that the above
//! copyright notice and this permission notice appear in all copies.
//!
//! THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//! WITH REGARD TO THIS SOFTWARE.

pub fn emuDeo(u: *Uxn, addr: u8, value: u8) void {
    u.dev[addr] = value;
    console.deo(u.dev[0..].ptr, addr);
}

pub fn main() !u8 {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const u = try allocator.create(Uxn);
    defer allocator.destroy(u);
    u.zero();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    if (args.len < 2) {
        try stdout.print("usage: {s} file.rom [args..]\n", .{args[0]});
        try bw.flush();
        return 0;
    }
    const file = try std.fs.cwd().openFile(args[1], .{});
    if (args.len > 257) {
        std.debug.panic("too many arguments!", .{});
    }
    u.dev[0x17] = @intCast(args.len - 2);
    _ = try file.readAll(u.ram[0x100..]);
    file.close();
    if (u.emuEval(0x100) and (@as(u16, u.dev[0x10]) << 8 | @as(u16, u.dev[0x11])) != 0) {
        console.listen(u, 3, args);
        const stdin = std.io.getStdIn().reader();
        while (u.dev[0x0f] == 0) {
            const byte = stdin.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    _ = console.input(u, 0, .END);
                    break;
                } else return err;
            };
            _ = console.input(u, byte, .STD);
        }
    }
    return u.dev[0x0f] & 0x7f;
}

const uxn = @import("uxn");
const console = @import("console.zig");
const Uxn = uxn.Uxn;
const std = @import("std");
