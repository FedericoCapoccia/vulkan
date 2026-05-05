const std = @import("std");

const glfw = @import("zglfw");
const vk = @import("vulkan");

pub const Instance = struct {
    handle: vk.Instance,
    wrapper: vk.InstanceWrapper,

    pub fn create(
        required_layers: []const [*:0]const u8,
        required_ext: []const [*:0]const u8,
        allocator: std.mem.Allocator,
    ) !Instance {
        const base = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

        const available_ext = try base.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
        defer allocator.free(available_ext);
        try checkInstanceExtensions(required_ext, available_ext);

        const available_layers = try base.enumerateInstanceLayerPropertiesAlloc(allocator);
        defer allocator.free(available_layers);
        try checkInstanceLayers(required_layers, available_layers);

        const app_info = vk.ApplicationInfo{
            .p_application_name = "Vulkan",
            .application_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
            .p_engine_name = "No Engine",
            .engine_version = vk.makeApiVersion(0, 1, 0, 0).toU32(),
            .api_version = vk.API_VERSION_1_4.toU32(),
        };

        const create_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(required_ext.len),
            .pp_enabled_extension_names = required_ext.ptr,
            .enabled_layer_count = @intCast(required_layers.len),
            .pp_enabled_layer_names = required_layers.ptr,
        };

        const instance_handle = try base.createInstance(&create_info, null);
        const instance_wrapper = vk.InstanceWrapper.load(instance_handle, base.dispatch.vkGetInstanceProcAddr.?);

        return .{
            .handle = instance_handle,
            .wrapper = instance_wrapper,
        };
    }

    pub fn destroy(self: *const Instance) void {
        self.wrapper.destroyInstance(self.handle, null);
    }
};

fn checkInstanceExtensions(required_ext: []const [*:0]const u8, available_ext: []const vk.ExtensionProperties) !void {
    std.log.info("Available instance extensions:", .{});
    for (available_ext) |ext| {
        const name = std.mem.sliceTo(&ext.extension_name, 0);
        var symbol: []const u8 = "➖";
        for (required_ext) |required_ext_z| {
            if (std.mem.eql(u8, std.mem.span(required_ext_z), name)) {
                symbol = "✅";
                break;
            }
        }

        std.log.info("\t{s} {s} v{}", .{ symbol, name, ext.spec_version });
    }

    for (required_ext) |required_ext_z| {
        const required_ext_name = std.mem.span(required_ext_z);
        var found = false;
        for (available_ext) |ext| {
            const name = std.mem.sliceTo(&ext.extension_name, 0);
            if (std.mem.eql(u8, required_ext_name, name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            std.log.err("Missing required Vulkan instance extension: {s}", .{required_ext_name});
            return error.MissingRequiredInstanceExtension;
        }
    }
}

fn checkInstanceLayers(required_layers: []const [*:0]const u8, available_layers: []const vk.LayerProperties) !void {
    std.log.info("Available instance layers:", .{});
    for (available_layers) |layer| {
        const name = std.mem.sliceTo(&layer.layer_name, 0);
        var symbol: []const u8 = "➖";
        for (required_layers) |required_layer_z| {
            if (std.mem.eql(u8, std.mem.span(required_layer_z), name)) {
                symbol = "✅";
                break;
            }
        }

        const version: vk.Version = @bitCast(layer.spec_version);
        std.log.info("\t{s} {s} v{}.{}.{}", .{
            symbol,
            name,
            version.major,
            version.minor,
            version.patch,
        });
    }

    for (required_layers) |required_layer_z| {
        const required_layer_name = std.mem.span(required_layer_z);
        var found = false;
        for (available_layers) |layer| {
            const name = std.mem.sliceTo(&layer.layer_name, 0);
            if (std.mem.eql(u8, required_layer_name, name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            std.log.err("Missing required Vulkan instance layer: {s}", .{required_layer_name});
            return error.MissingRequiredInstanceLayer;
        }
    }
}
