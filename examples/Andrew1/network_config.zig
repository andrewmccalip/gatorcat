const gcat = @import("gatorcat");

pub const eni = gcat.ENI{
    .subdevices = &.{ beckhoff_EK1100, beckhoff_EL3314, beckhoff_EL2008 },
};

const beckhoff_EK1100 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0x44c2c52,
        .revision_number = 0x120000,
    },
};

const beckhoff_EL3314 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0xcf23052,
        .revision_number = 0x190000,
    },
    .coe_startup_parameters = &.{
        .{
            .transition = .PS,
            .direction = .write,
            .index = 0x8000,
            .subindex = 0x2,
            .complete_access = false,
            .data = &.{2},
            .timeout_us = 10_000,
        },
    },
    .inputs_bit_length = 128,
};

const beckhoff_EL2008 = gcat.ENI.SubDeviceConfiguration{
    .identity = .{
        .vendor_id = 0x2,
        .product_code = 0x7d83052,
        .revision_number = 0x100000,
    },
    .outputs_bit_length = 8, // 8 digital outputs × 1 bit per output
};
