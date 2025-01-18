const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const gcat = @import("gatorcat");

const eni = @import("network_config.zig").eni;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var raw_socket = switch (builtin.target.os.tag) {
        .linux => try gcat.nic.RawSocket.init("enx00e04c68191a"),
        .windows => try gcat.nic.WindowsRawSocket.init("\\Device\\NPF_{FD6FB7B9-BB54-438B-8178-07EEAFAC6294}"),
        else => @compileError("unsupported target os"),
    };
    defer raw_socket.deinit();
    var port = gcat.Port.init(raw_socket.linkLayer(), .{});
    try port.ping(10000);

    const estimated_stack_usage = comptime gcat.MainDevice.estimateAllocSize(eni) + 8;
    var stack_memory: [estimated_stack_usage]u8 = undefined;
    var stack_fba = std.heap.FixedBufferAllocator.init(&stack_memory);

    var md = try gcat.MainDevice.init(
        stack_fba.allocator(),
        &port,
        .{ .recv_timeout_us = 200000, .eeprom_timeout_us = 100000 },
        eni,
    );
    defer md.deinit(stack_fba.allocator());

    try md.busInit(5_000_000);
    try md.busPreop(10_000_000);
    try md.busSafeop(10_000_000);
    try md.busOp(10_000_000);

    var print_timer = try std.time.Timer.start();
    var blink_timer = try std.time.Timer.start();
    var kill_timer = try std.time.Timer.start();
    var wkc_error_timer = try std.time.Timer.start();
    var cycle_count: u32 = 0;

    const ek1100 = &md.subdevices[0];
    const el3314 = &md.subdevices[1];
    const el2008 = &md.subdevices[2];

    var temps = el3314.packFromInputProcessData(EL3314ProcessData);

    while (true) {
        // input and output mapping
        temps = el3314.packFromInputProcessData(EL3314ProcessData);

        // exchange process data
        const diag = md.sendRecvCyclicFramesDiag() catch |err| switch (err) {
            error.RecvTimeout => {
                std.log.warn("recv timeout", .{});
                continue;
            },
            error.LinkError,
            error.CurruptedFrame,
            error.NoTransactionAvailable,
            => |err2| return err2,
        };
        if (diag.brd_status_wkc != eni.subdevices.len) return error.TopologyChanged;
        if (diag.brd_status.state != .OP) {
            std.log.err("Not all subdevices in OP! brd status {}", .{diag.brd_status});
            return error.NotAllSubdevicesInOP;
        }
        if (diag.process_data_wkc != md.expectedProcessDataWkc() and wkc_error_timer.read() > 1 * std.time.ns_per_s) {
            wkc_error_timer.reset();
            std.log.err("process data wkc wrong: {}, expected: {}", .{ diag.process_data_wkc, md.expectedProcessDataWkc() });
        }
        // if (diag.process_data_wkc == md.expectedProcessDataWkc()) std.debug.print("SUCCESS!!!!!!!!!!!!!!\n", .{});
        cycle_count += 1;

        // do application
        if (print_timer.read() > std.time.ns_per_s * 1) {
            print_timer.reset();
            std.debug.print("frames/s: {}\n", .{cycle_count});
            std.debug.print("\nTemperature Readings:\n", .{});
            std.debug.print("  Channel 1: {d:>6.2}\n", .{@as(f32, @floatFromInt(temps.ch1.value)) / 100.0});
            std.debug.print("  Channel 2: {d:>6.2}\n", .{@as(f32, @floatFromInt(temps.ch2.value)) / 100.0});
            std.debug.print("  Channel 3: {d:>6.2}\n", .{@as(f32, @floatFromInt(temps.ch3.value)) / 100.0});
            std.debug.print("  Channel 4: {d:>6.2}\n", .{@as(f32, @floatFromInt(temps.ch4.value)) / 100.0});
            cycle_count = 0;
        }
        if (blink_timer.read() > std.time.ns_per_s * 0.1) {
            blink_timer.reset();
            // Toggle only the first bit
            el2008.runtime_info.pi.outputs[0] ^= 1;
        }
        if (kill_timer.read() > std.time.ns_per_s * 60) {
            kill_timer.reset();
            try ek1100.setALState(&port, .SAFEOP, 10000, 10000);
        }
    }
}

const EL3314Channel = packed struct(u32) {
    underrange: bool,
    overrange: bool,
    limit1: u2,
    limit2: u2,
    err: bool,
    _reserved: u7,
    txpdo_state: bool,
    txpdo_toggle: bool,
    value: i16,
};

const EL3314ProcessData = packed struct {
    ch1: EL3314Channel,
    ch2: EL3314Channel,
    ch3: EL3314Channel,
    ch4: EL3314Channel,
};
