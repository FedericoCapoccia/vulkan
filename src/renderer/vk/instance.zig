const std = @import("std");

const vk = @import("vulkan");

pub const Instance = struct {
    handle: vk.Instance,
    wrapper: vk.InstanceWrapper,
    api_version: u32,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,

    pub const InitInfo = struct {
        allocator: std.mem.Allocator,
        base: vk.BaseWrapper,
        extensions: []const [*:0]const u8,
        enable_messenger: bool,
    };

    pub const InitError = error{
        VulkanError,
        OutOfMemory,
        UnsupportedVulkanVersion,
        UnsupportedExtension,
    };

    // TODO: make instance creation based on minimal profile: VP_LUNARG_minimum_requirements_1_3
    pub fn init(info: *const InitInfo) InitError!Instance {
        const instance_version = info.base.enumerateInstanceVersion() catch |err| {
            std.log.err("Failed to enumerate instance version: {}", .{err});
            return error.VulkanError;
        };

        if (instance_version < vk.API_VERSION_1_3.toU32()) {
            return error.UnsupportedVulkanVersion;
        }

        const version: vk.Version = @bitCast(instance_version);
        std.log.info("Vulkan instance API: {}.{}.{}", .{ version.major, version.minor, version.patch });

        const available_ext = info.base.enumerateInstanceExtensionPropertiesAlloc(null, info.allocator) catch |err| {
            std.log.err("Failed to enumerate available instance extensions: {}", .{err});
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.VulkanError,
            };
        };
        defer info.allocator.free(available_ext);

        if (!checkExtensions(available_ext, info.extensions)) {
            return error.UnsupportedExtension;
        }

        const messenger_cinfo = messengerCreateInfo();

        const app_info = vk.ApplicationInfo{
            .p_application_name = "Vulkan",
            .application_version = vk.makeApiVersion(0, 0, 1, 0).toU32(),
            .p_engine_name = "No Engine",
            .engine_version = vk.makeApiVersion(0, 0, 1, 0).toU32(),
            .api_version = instance_version,
        };

        const cinfo = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(info.extensions.len),
            .pp_enabled_extension_names = info.extensions[0..].ptr,
            .p_next = if (info.enable_messenger) &messenger_cinfo else null,
        };

        const loader = info.base.dispatch.vkGetInstanceProcAddr orelse {
            std.log.err("Base dispatch didn't load vkGetInstanceProcAddress", .{});
            return error.VulkanError;
        };

        const handle = info.base.createInstance(&cinfo, null) catch |err| {
            std.log.err("Failed to create VkInstance: {}", .{err});
            return error.VulkanError;
        };

        var self = Instance{
            .handle = handle,
            .wrapper = vk.InstanceWrapper.load(handle, loader),
            .api_version = instance_version,
            .debug_messenger = null,
        };
        const instance_proxy = vk.InstanceProxy.init(self.handle, &self.wrapper);
        errdefer self.deinit();

        if (info.enable_messenger) {
            self.debug_messenger = instance_proxy.createDebugUtilsMessengerEXT(&messenger_cinfo, null) catch |err| blk: {
                std.log.warn("Failed to create requested DebugMessenger: {}", .{err});
                break :blk null;
            };
        }

        return self;
    }

    pub fn deinit(self: *Instance) void {
        if (self.handle == .null_handle) return;

        const instance_proxy = self.proxy();

        if (self.debug_messenger) |messenger| {
            instance_proxy.destroyDebugUtilsMessengerEXT(messenger, null);
            self.debug_messenger = null;
        }

        instance_proxy.destroyInstance(null);
        self.handle = .null_handle;
        self.wrapper = undefined;
    }

    pub fn proxy(self: *const Instance) vk.InstanceProxy {
        return vk.InstanceProxy.init(self.handle, &self.wrapper);
    }
};

fn checkExtensions(available: []vk.ExtensionProperties, requested: []const [*:0]const u8) bool {
    std.log.info("Enabled instance extensions", .{});

    var all_found = true;
    for (requested) |requested_z| {
        const requested_name = std.mem.span(requested_z);
        var found: ?vk.ExtensionProperties = null;

        for (available) |extension| {
            const available_name = std.mem.sliceTo(&extension.extension_name, 0);
            if (std.mem.eql(u8, requested_name, available_name)) {
                found = extension;
                break;
            }
        }

        if (found) |extension| {
            std.log.info("\t[OK] {s} v{}", .{ requested_name, extension.spec_version });
        } else {
            all_found = false;
            std.log.err("\t[MISSING] {s} v0", .{requested_name});
        }
    }

    return all_found;
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
