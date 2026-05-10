const std = @import("std");

const vk = @import("vulkan");
const profile = @import("../profile.zig");

pub const Instance = struct {
    handle: vk.Instance,
    wrapper: vk.InstanceWrapper,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,
};

pub fn create(
    base: *const vk.BaseWrapper,
    extensions: []const [*:0]const u8,
    log_messages: bool,
    allocator: std.mem.Allocator,
) !Instance {
    const available_extensions = try base.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    defer allocator.free(available_extensions);

    var messenger_cinfo = messengerCreateInfo();
    const handle = try profile.createInstance(
        extensions,
        if (log_messages) &messenger_cinfo else null,
    );
    const wrapper = vk.InstanceWrapper.load(handle, base.dispatch.vkGetInstanceProcAddr.?);
    errdefer wrapper.destroyInstance(handle, null);

    const debug_messenger = if (log_messages)
        try wrapper.createDebugUtilsMessengerEXT(handle, &messenger_cinfo, null)
    else
        null;

    return .{
        .handle = handle,
        .wrapper = wrapper,
        .debug_messenger = debug_messenger,
    };
}

fn messengerCreateInfo() vk.DebugUtilsMessengerCreateInfoEXT {
    const severity = vk.DebugUtilsMessageSeverityFlagsEXT{
        .error_bit_ext = true,
        .warning_bit_ext = true,
    };

    const mtype = vk.DebugUtilsMessageTypeFlagsEXT{
        .device_address_binding_bit_ext = false,
        .general_bit_ext = true,
        .performance_bit_ext = true,
        .validation_bit_ext = true,
    };

    return vk.DebugUtilsMessengerCreateInfoEXT{
        .message_severity = severity,
        .message_type = mtype,
        .pfn_user_callback = debugCallback,
    };
}

fn debugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = p_user_data;

    const callback_data = p_callback_data orelse return .false;
    const message = callback_data.p_message orelse "<no message>";

    const message_type = if (message_types.general_bit_ext)
        "GENERAL"
    else if (message_types.validation_bit_ext)
        "VALIDATION"
    else if (message_types.performance_bit_ext)
        "PERFORMANCE"
    else if (message_types.device_address_binding_bit_ext)
        "DEVICE ADDRESS BINDING"
    else
        "UNKNOWN";

    switch (message_severity.toInt()) {
        (vk.DebugUtilsMessageSeverityFlagsEXT{ .error_bit_ext = true }).toInt() => std.log.err("Vulkan [{s}]: {s}", .{ message_type, message }),
        (vk.DebugUtilsMessageSeverityFlagsEXT{ .warning_bit_ext = true }).toInt() => std.log.warn("Vulkan [{s}]: {s}", .{ message_type, message }),
        (vk.DebugUtilsMessageSeverityFlagsEXT{ .info_bit_ext = true }).toInt() => std.log.info("Vulkan [{s}]: {s}", .{ message_type, message }),
        (vk.DebugUtilsMessageSeverityFlagsEXT{ .verbose_bit_ext = true }).toInt() => std.log.debug("Vulkan [{s}]: {s}", .{ message_type, message }),
        else => std.log.debug("Vulkan {s}: {s}", .{ message_type, message }),
    }

    return .false;
}
