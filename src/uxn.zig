//! Copyright (c) 2024 Rylee Alanza Lyman (zig port)
//! Copyright (c) 2022-2023 Devine Lu Linvega, Andrew Alderwick
//!
//! Permission to use, copy, modify, and distribute this software for any
//! purpose with or without fee is hereby granted, provided that the above
//! copyright notice and this permission notice appear in all copies.
//!
//! THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//! WITH REGARD TO THIS SOFTWARE.

const std = @import("std");
const root = @import("root");

const Stack = struct {
    dat: [0x100]u8,
    ptr: u8,
};

pub const Uxn = struct {
    ram: [0x10000]u8,
    dev: [0x100]u8,
    working_stack: Stack,
    return_stack: Stack,

    pub const emuDei = if (@hasDecl(root, "emuDei")) root.emuDei else defaultEmuDei;
    pub const emuDeo = if (@hasDecl(root, "emuDeo")) root.emuDeo else defaultEmuDeo;

    pub fn zero(u: *Uxn) void {
        @memset(&u.ram, 0);
        @memset(&u.dev, 0);
        @memset(&u.working_stack.dat, 0);
        u.working_stack.ptr = 0;
        @memset(&u.return_stack.dat, 0);
        u.return_stack.ptr = 0;
    }

    pub fn emuEval(u: *Uxn, pc: u16) bool {
        const ram = &u.ram;
        var program_counter = pc;
        if (pc == 0 or u.dev[0x0f] != 0) return false;
        while (true) {
            const ins: OpCode = @bitCast(ram[program_counter]);
            program_counter +%= 1;
            const stack = if (ins.ret) &u.return_stack else &u.working_stack;
            var kp: u8 = if (ins.keep) stack.ptr else 0;
            const sp = if (ins.keep) &kp else &stack.ptr;
            switch (ins.instruction) {
                .BRK => {
                    if (ins.eql(OpCode.BRK)) return true;
                    if (ins.eql(OpCode.JCI)) {
                        const x = pop(&u.working_stack, sp, false);
                        if (x == 0) {
                            program_counter +%= 1;
                            continue;
                        }
                    }
                    if (ins.eql(OpCode.JCI) or ins.eql(OpCode.JMI)) {
                        const short: u16 = short: {
                            const high = ram[program_counter];
                            program_counter +%= 1;
                            const low = ram[program_counter];
                            program_counter +%= 1;
                            const short: Short = .{ .high = high, .low = low };
                            break :short short.toU16();
                        };
                        program_counter +%= short;
                        continue;
                    }
                    if (ins.eql(OpCode.JSI)) {
                        push(&u.return_stack, true, Short.fromU16(program_counter +% 2));
                        const short: u16 = short: {
                            const high = ram[program_counter];
                            program_counter +%= 1;
                            const low = ram[program_counter];
                            program_counter +%= 1;
                            const short: Short = .{ .high = high, .low = low };
                            break :short short.toU16();
                        };
                        program_counter +%= short;
                        continue;
                    }
                    // LIT(k) + LIT2(k)
                    if (ins.short) {
                        const short: Short = short: {
                            const high = ram[program_counter];
                            program_counter +%= 1;
                            const low = ram[program_counter];
                            program_counter +%= 1;
                            break :short .{ .high = high, .low = low };
                        };
                        push(stack, true, short);
                    } else {
                        const byte = ram[program_counter];
                        program_counter +%= 1;
                        push(stack, false, byte);
                    }
                },
                .INC => {
                    if (ins.short) {
                        const short = pop(stack, sp, true).toU16();
                        push(stack, true, Short.fromU16(short +% 1));
                    } else {
                        const byte = pop(stack, sp, false);
                        push(stack, false, byte +% 1);
                    }
                },
                .POP => _ = if (ins.short) pop(stack, sp, true) else pop(stack, sp, false),
                .NIP => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        _ = pop(stack, sp, true);
                        push(stack, true, short);
                    } else push(stack, false, short.low);
                },
                .SWP => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        push(stack, true, short);
                        push(stack, true, other);
                    } else push(stack, true, .{ .high = short.low, .low = short.high });
                },
                .ROT => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const b = pop(stack, sp, true);
                        const a = pop(stack, sp, true);
                        push(stack, true, b);
                        push(stack, true, short);
                        push(stack, true, a);
                    } else {
                        const byte = pop(stack, sp, false);
                        push(stack, true, short);
                        push(stack, false, byte);
                    }
                },
                .DUP => {
                    if (ins.short) {
                        const res = pop(stack, sp, true);
                        push(stack, true, res);
                        push(stack, true, res);
                    } else {
                        const res = pop(stack, sp, false);
                        push(stack, false, res);
                        push(stack, false, res);
                    }
                },
                .OVR => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        push(stack, true, other);
                        push(stack, true, short);
                        push(stack, true, other);
                    } else {
                        push(stack, true, short);
                        push(stack, false, short.high);
                    }
                },
                .EQU => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        push(stack, false, if (other.toU16() == short.toU16()) 1 else 0);
                    } else {
                        push(stack, false, if (short.high == short.low) 1 else 0);
                    }
                },
                .NEQ => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        push(stack, false, if (other.toU16() == short.toU16()) 0 else 1);
                    } else push(stack, false, if (short.high == short.low) 0 else 1);
                },
                .GTH => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        push(stack, false, if (other.toU16() > short.toU16()) 1 else 0);
                    } else push(stack, false, if (short.high > short.low) 1 else 0);
                },
                .LTH => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        push(stack, false, if (other.toU16() >= short.toU16()) 0 else 1);
                    } else push(stack, false, if (short.high >= short.low) 0 else 1);
                },
                .JMP => {
                    if (ins.short) {
                        const short = pop(stack, sp, true).toU16();
                        program_counter +%= short;
                    } else {
                        const byte: i8 = @bitCast(pop(stack, sp, false));
                        const temp: i32 = @as(i32, program_counter) + @as(i32, byte);
                        program_counter = @intCast(@mod(temp, std.math.maxInt(u16)));
                    }
                },
                .JCN => {
                    if (ins.short) {
                        const short = pop(stack, sp, true).toU16();
                        const cond = pop(stack, sp, false);
                        if (cond > 0) program_counter +%= short;
                    } else {
                        const byte: i8 = @bitCast(pop(stack, sp, false));
                        const cond = pop(stack, sp, false);
                        if (cond != 0) {
                            const temp: i32 = @as(i32, program_counter) + @as(i32, byte);
                            program_counter = @intCast(@mod(temp, std.math.maxInt(u16)));
                        }
                    }
                },
                .JSR => {
                    if (ins.short) {
                        const short = pop(stack, sp, true).toU16();
                        push(if (ins.ret) &u.working_stack else &u.return_stack, true, Short.fromU16(program_counter));
                        program_counter +%= short;
                    } else {
                        const byte: i8 = @bitCast(pop(stack, sp, false));
                        push(if (ins.ret) &u.working_stack else &u.return_stack, true, Short.fromU16(program_counter));

                        const temp: i32 = @as(i32, program_counter) + @as(i32, byte);
                        program_counter = @intCast(@mod(temp, std.math.maxInt(u16)));
                    }
                },
                .STH => {
                    if (ins.short) {
                        const res = pop(stack, sp, true);
                        push(if (ins.ret) &u.working_stack else &u.return_stack, true, res);
                    } else {
                        const res = pop(stack, sp, false);
                        push(if (ins.ret) &u.working_stack else &u.return_stack, false, res);
                    }
                },
                .LDZ => {
                    const addr = pop(stack, sp, false);
                    if (ins.short) {
                        const short: Short = short: {
                            const high = ram[addr];
                            const low = ram[addr +% 1];
                            break :short .{ .high = high, .low = low };
                        };
                        push(stack, true, short);
                    } else {
                        push(stack, false, ram[addr]);
                    }
                },
                .STZ => {
                    const addr = pop(stack, sp, false);
                    if (ins.short) {
                        const short = pop(stack, sp, true);
                        ram[addr] = short.high;
                        ram[addr +% 1] = short.low;
                    } else ram[addr] = pop(stack, sp, false);
                },
                .LDR => {
                    const addr: i8 = @bitCast(pop(stack, sp, false));
                    const tmp: i32 = @as(i32, program_counter) + @as(i32, addr);
                    const new_addr: u16 = @intCast(@mod(tmp, std.math.maxInt(u16)));
                    if (ins.short) {
                        const short: Short = short: {
                            const high = ram[new_addr];
                            const low = ram[new_addr +% 1];
                            break :short .{ .high = high, .low = low };
                        };
                        push(stack, true, short);
                    } else push(stack, false, ram[new_addr]);
                },
                .STR => {
                    const addr: i8 = @bitCast(pop(stack, sp, false));
                    const tmp: i32 = @as(i32, program_counter) + @as(i32, addr);
                    const new_addr: u16 = @intCast(@mod(tmp, std.math.maxInt(u16)));
                    if (ins.short) {
                        const short = pop(stack, sp, true);
                        ram[new_addr] = short.high;
                        ram[new_addr +% 1] = short.low;
                    } else ram[new_addr] = pop(stack, sp, false);
                },
                .LDA => {
                    const addr = pop(stack, sp, true).toU16();
                    if (ins.short) {
                        const short: Short = short: {
                            const high = ram[addr];
                            const low = ram[addr +% 1];
                            break :short .{ .high = high, .low = low };
                        };
                        push(stack, true, short);
                    } else push(stack, false, ram[addr]);
                },
                .STA => {
                    const addr = pop(stack, sp, true).toU16();
                    if (ins.short) {
                        const short = pop(stack, sp, true);
                        ram[addr] = short.high;
                        ram[addr +% 1] = short.low;
                    } else ram[addr] = pop(stack, sp, false);
                },
                .DEI => {
                    const dev = pop(stack, sp, false);
                    if (ins.short) {
                        const short: Short = short: {
                            const high = u.emuDei(dev);
                            const low = u.emuDei(dev);
                            break :short .{ .high = high, .low = low };
                        };
                        push(stack, true, short);
                    } else push(stack, false, u.emuDei(dev));
                },
                .DEO => {
                    const dev = pop(stack, sp, false);
                    if (ins.short) {
                        const short = pop(stack, sp, true);
                        u.emuDeo(dev, short.high);
                        u.emuDeo(dev, short.low);
                    } else u.emuDeo(dev, pop(stack, sp, false));
                },
                .ADD => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        const ret = Short.fromU16(short.toU16() +% other.toU16());
                        push(stack, true, ret);
                    } else push(stack, false, short.high +% short.low);
                },
                .SUB => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        const ret = Short.fromU16(other.toU16() -% short.toU16());
                        push(stack, true, ret);
                    } else push(stack, false, short.high -% short.low);
                },
                .MUL => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        const ret = Short.fromU16(other.toU16() *% short.toU16());
                        push(stack, true, ret);
                    } else push(stack, false, short.low *% short.high);
                },
                .DIV => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true).toU16();
                        if (short.toU16() == 0) {
                            push(stack, true, Short.fromU16(0));
                        } else push(stack, true, Short.fromU16(@divTrunc(other, short.toU16())));
                    } else {
                        if (short.high == 0)
                            push(stack, false, 0)
                        else
                            push(stack, false, @divTrunc(short.high, short.low));
                    }
                },
                .AND => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        const ret = Short.fromU16(other.toU16() & short.toU16());
                        push(stack, true, ret);
                    } else push(stack, false, short.low & short.high);
                },
                .ORA => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        const ret = Short.fromU16(other.toU16() | short.toU16());
                        push(stack, true, ret);
                    } else push(stack, false, short.low | short.high);
                },
                .EOR => {
                    const short = pop(stack, sp, true);
                    if (ins.short) {
                        const other = pop(stack, sp, true);
                        const ret = Short.fromU16(other.toU16() ^ short.toU16());
                        push(stack, true, ret);
                    } else push(stack, false, short.low ^ short.high);
                },
                .SFT => {
                    const shift = pop(stack, sp, false);
                    const left = shift >> 4;
                    const right = shift & 0x0f;
                    if (ins.short) {
                        const short = pop(stack, sp, true).toU16();
                        if (left == 0xf or right == 0xf) {
                            push(stack, true, Short.fromU16(0));
                        } else {
                            const res = (short >> @intCast(right)) << @intCast(left);
                            push(stack, true, Short.fromU16(res));
                        }
                    } else {
                        const byte = pop(stack, sp, false);
                        if (left > 0x7 or right > 0x7) {
                            push(stack, false, 0);
                        } else {
                            push(stack, false, (byte >> @intCast(right)) << @intCast(left));
                        }
                    }
                },
            }
        }
    }
};

fn pop(stack: *Stack, ptr: *u8, comptime two: bool) if (two) Short else u8 {
    if (comptime two) {
        ptr.* -%= 1;
        const low = stack.dat[ptr.*];
        ptr.* -%= 1;
        const high = stack.dat[ptr.*];
        const ret: Short = .{ .high = high, .low = low };
        return ret;
    } else {
        ptr.* -%= 1;
        const ret = stack.dat[ptr.*];
        return ret;
    }
}

fn push(stack: *Stack, comptime two: bool, dat: if (two) Short else u8) void {
    if (comptime two) {
        stack.dat[stack.ptr] = dat.high;
        stack.ptr +%= 1;
        stack.dat[stack.ptr] = dat.low;
        stack.ptr +%= 1;
    } else {
        stack.dat[stack.ptr] = dat;
        stack.ptr +%= 1;
    }
}

pub fn defaultEmuDei(u: *Uxn, addr: u8) u8 {
    return u.dev[addr];
}

pub fn defaultEmuDeo(u: *Uxn, addr: u8, value: u8) void {
    u.dev[addr] = value;
}

pub const Short = packed struct {
    high: u8,
    low: u8,

    pub fn fromU16(short: u16) Short {
        return .{
            .high = @intCast(short >> 8),
            .low = @intCast(short & 0x00ff),
        };
    }

    pub fn toU16(short: Short) u16 {
        return @as(u16, short.high) << 8 | @as(u16, short.low);
    }
};

test "to and from u16" {
    const dead: u16 = 0xdead;
    const and_gone: Short = .{ .high = 0xde, .low = 0xad };
    try std.testing.expectEqual(dead, and_gone.toU16());
    try std.testing.expectEqual(and_gone, Short.fromU16(dead));
}

const OpCode = packed struct {
    instruction: enum(u5) {
        BRK,
        INC,
        POP,
        NIP,
        SWP,
        ROT,
        DUP,
        OVR,
        EQU,
        NEQ,
        GTH,
        LTH,
        JMP,
        JCN,
        JSR,
        STH,
        LDZ,
        STZ,
        LDR,
        STR,
        LDA,
        STA,
        DEI,
        DEO,
        ADD,
        SUB,
        MUL,
        DIV,
        AND,
        ORA,
        EOR,
        SFT,
    },
    short: bool = false,
    ret: bool = false,
    keep: bool = false,

    const BRK: OpCode = .{
        .instruction = .BRK,
    };
    const JCI: OpCode = .{
        .instruction = .BRK,
        .short = true,
    };
    const JMI: OpCode = .{
        .instruction = .BRK,
        .ret = true,
    };
    const JSI: OpCode = .{
        .instruction = .BRK,
        .short = true,
        .ret = true,
    };
    const LIT: OpCode = .{
        .instruction = .BRK,
        .keep = true,
    };
    const LIT2: OpCode = .{
        .instruction = .BRK,
        .keep = true,
        .short = true,
    };
    const LITr: OpCode = .{
        .instruction = .BRK,
        .keep = true,
        .ret = true,
    };
    const LIT2r: OpCode = .{
        .instruction = .BRK,
        .keep = true,
        .ret = true,
        .short = true,
    };

    pub fn eql(a: OpCode, b: OpCode) bool {
        return a.keep == b.keep and a.ret == b.ret and a.short == b.short and a.instruction == b.instruction;
    }

    pub fn format(value: OpCode, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (value.instruction == .BRK) {
            if (value.eql(OpCode.BRK)) try writer.writeAll("BRK");
            if (value.eql(OpCode.JCI)) try writer.writeAll("JCI");
            if (value.eql(OpCode.JMI)) try writer.writeAll("JMI");
            if (value.eql(OpCode.JSI)) try writer.writeAll("JSI");
            if (value.eql(OpCode.LIT)) try writer.writeAll("LIT");
            if (value.eql(OpCode.LITr)) try writer.writeAll("LITr");
            if (value.eql(OpCode.LIT2r)) try writer.writeAll("LIT2r");
            if (value.eql(OpCode.LIT2)) try writer.writeAll("LIT2");
        } else {
            try writer.writeAll(@tagName(value.instruction));
            if (value.short) try writer.writeAll("2");
            if (value.ret) try writer.writeAll("r");
            if (value.keep) try writer.writeAll("k");
        }
    }

    comptime {
        std.debug.assert(@sizeOf(OpCode) == @sizeOf(u8));
        std.debug.assert(@bitSizeOf(OpCode) == @bitSizeOf(u8));
    }
};
