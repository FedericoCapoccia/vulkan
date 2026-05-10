const std = @import("std");

const vk = @import("vulkan");
const profile = @import("profile.zig");

pub const Instance = struct {
    handle: vk.Instance,
    wrapper: vk.InstanceWrapper,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,
};

pub fn create(
    base: *const vk.BaseWrapper,
    requirements: *const profile.EngineRequirements,
    log_messages: bool,
    allocator: std.mem.Allocator,
) !Instance {
    const available_extensions = try base.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    defer allocator.free(available_extensions);
    try checkExtensions(requirements.instance_extensions, available_extensions);

    var messenger_cinfo = messengerCreateInfo();

    const instance_version = try base.enumerateInstanceVersion();
    if (instance_version < vk.API_VERSION_1_3.toU32()) {
        return error.UnsupportedVulkanInstanceVersion;
    }

    const app_info = vk.ApplicationInfo{
        .p_application_name = "Vulkan",
        .application_version = vk.makeApiVersion(0, 0, 1, 0).toU32(),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(0, 0, 1, 0).toU32(),
        .api_version = instance_version,
    };

    const cinfo = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(requirements.instance_extensions.len),
        .pp_enabled_extension_names = if (requirements.instance_extensions.len == 0) null else requirements.instance_extensions.ptr,
        .p_next = if (log_messages) &messenger_cinfo else null,
    };

    const handle = try base.createInstance(&cinfo, null);
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

fn checkExtensions(required: []const [*:0]const u8, available: []const vk.ExtensionProperties) !void {
    std.log.info("Enabled instance extensions", .{});

    var all_found = true;
    for (required) |required_z| {
        const required_name = std.mem.span(required_z);
        var found: ?vk.ExtensionProperties = null;

        for (available) |extension| {
            const available_name = std.mem.sliceTo(&extension.extension_name, 0);
            if (std.mem.eql(u8, required_name, available_name)) {
                found = extension;
                break;
            }
        }

        if (found) |extension| {
            std.log.info("\t[OK] {s} v{}", .{ required_name, extension.spec_version });
        } else {
            all_found = false;
            std.log.err("\t[MISSING] {s} v0", .{required_name});
        }
    }

    if (!all_found) return error.MissingRequiredInstanceExtension;
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
