const std = @import("std");

const vk = @import("vulkan");
const vp = @import("vulkan-profiles");

pub const EngineProfile = enum {
    minimal,
    roadmap2024,
    roadmap2026,
};

pub const EngineFeature = enum {
    shader_draw_parameters,
};

pub const EngineExtension = enum {
    swapchain,
};

// Extensions and features required but not included in VP_LUNARG_minimum_requirements_1_3
pub const EngineRequirements = struct {
    extra_device_extensions: []const EngineExtension,
    extra_features: []const EngineFeature,
};

pub fn supportedProfile(
    instance: *const vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    requirements: *const EngineRequirements,
    allocator: std.mem.Allocator,
) !?EngineProfile {
    const candidates = [_]EngineProfile{
        .roadmap2026,
        .roadmap2024,
        .minimal,
    };

    for (candidates) |candidate| {
        var props = vp.VpProfileProperties{};
        const name = switch (candidate) {
            .minimal => blk: {
                props.specVersion = vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_SPEC_VERSION;
                break :blk std.mem.sliceTo(vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_NAME, 0);
            },
            .roadmap2024 => blk: {
                props.specVersion = vp.VP_KHR_ROADMAP_2024_SPEC_VERSION;
                break :blk std.mem.sliceTo(vp.VP_KHR_ROADMAP_2024_NAME, 0);
            },
            .roadmap2026 => blk: {
                props.specVersion = vp.VP_KHR_ROADMAP_2026_SPEC_VERSION;
                break :blk std.mem.sliceTo(vp.VP_KHR_ROADMAP_2026_NAME, 0);
            },
        };
        @memmove(props.profileName[0..name.len], name);

        var supported: vp.VkBool32 = vp.VK_FALSE;
        try check(vp.vpGetPhysicalDeviceProfileSupport(
            toCInstance(instance.handle),
            toCPhysicalDevice(pdev),
            &props,
            &supported,
        ));

        if (supported == vp.VK_TRUE and
            try hasExtraDeviceExtensions(instance, pdev, candidate, requirements.extra_device_extensions, allocator) and
            hasExtraFeatures(instance, pdev, candidate, requirements.extra_features))
        {
            return candidate;
        }
    }

    return null;
}

fn hasExtraDeviceExtensions(
    instance: *const vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    engine_profile: EngineProfile,
    extra_extensions: []const EngineExtension,
    allocator: std.mem.Allocator,
) !bool {
    const available = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(available);

    for (extra_extensions) |extension| {
        if (profileProvidesExtension(engine_profile, extension)) continue;

        const required_name = std.mem.span(extensionName(extension));
        var found = false;
        for (available) |available_extension| {
            const available_name = std.mem.sliceTo(&available_extension.extension_name, 0);
            if (std.mem.eql(u8, required_name, available_name)) {
                found = true;
                break;
            }
        }

        if (!found) return false;
    }

    return true;
}

fn hasExtraFeatures(
    instance: *const vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    engine_profile: EngineProfile,
    extra_features: []const EngineFeature,
) bool {
    var features_1_1 = vk.PhysicalDeviceVulkan11Features{};
    var features = vk.PhysicalDeviceFeatures2{
        .features = .{},
        .p_next = &features_1_1,
    };
    instance.getPhysicalDeviceFeatures2(pdev, &features);

    for (extra_features) |feature| {
        if (profileProvidesFeature(engine_profile, feature)) continue;

        switch (feature) {
            .shader_draw_parameters => {
                if (features_1_1.shader_draw_parameters == .false) return false;
            },
        }
    }

    return true;
}

// For each extra feature added mark the profile that provides it
fn profileProvidesFeature(engine_profile: EngineProfile, feature: EngineFeature) bool {
    return switch (feature) {
        .shader_draw_parameters => switch (engine_profile) {
            .minimal => false,
            .roadmap2024, .roadmap2026 => true,
        },
    };
}

fn profileProvidesExtension(engine_profile: EngineProfile, extension: EngineExtension) bool {
    return switch (extension) {
        .swapchain => switch (engine_profile) {
            .minimal, .roadmap2024 => false,
            .roadmap2026 => true,
        },
    };
}

fn extensionName(extension: EngineExtension) [*:0]const u8 {
    return switch (extension) {
        .swapchain => vk.extensions.khr_swapchain.name,
    };
}

pub fn createDevice(
    pdev: vk.PhysicalDevice,
    queue_family: u32,
    extensions: []const [*:0]const u8,
) !vk.Device {
    var vulkan_11_features = vp.VkPhysicalDeviceVulkan11Features{
        .sType = vp.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        .shaderDrawParameters = vp.VK_TRUE,
    };

    const queue_priority = [_]f32{1.0};
    const queue_cinfo = [_]vp.VkDeviceQueueCreateInfo{.{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority,
    }};

    const device_cinfo = vp.VkDeviceCreateInfo{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vulkan_11_features,
        .queueCreateInfoCount = queue_cinfo.len,
        .pQueueCreateInfos = &queue_cinfo,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = if (extensions.len == 0) null else @ptrCast(extensions.ptr),
    };

    var selected_profile = profile();
    const profile_cinfo = vp.VpDeviceCreateInfo{
        .pCreateInfo = &device_cinfo,
        .enabledFullProfileCount = 1,
        .pEnabledFullProfiles = &selected_profile,
    };

    var device: vp.VkDevice = null;
    try check(vp.vpCreateDevice(
        toCPhysicalDevice(pdev),
        &profile_cinfo,
        null,
        &device,
    ));

    return fromCDevice(device);
}

fn profile() vp.VpProfileProperties {
    var props = vp.VpProfileProperties{
        .specVersion = vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_SPEC_VERSION,
    };
    const name = std.mem.sliceTo(vp.VP_LUNARG_MINIMUM_REQUIREMENTS_1_3_NAME, 0);
    @memmove(props.profileName[0..name.len], name);
    return props;
}

fn check(result: vp.VkResult) !void {
    switch (result) {
        vp.VK_SUCCESS => {},
        vp.VK_ERROR_OUT_OF_HOST_MEMORY => return error.OutOfHostMemory,
        vp.VK_ERROR_OUT_OF_DEVICE_MEMORY => return error.OutOfDeviceMemory,
        vp.VK_ERROR_INITIALIZATION_FAILED => return error.VulkanProfileInitializationFailed,
        vp.VK_ERROR_EXTENSION_NOT_PRESENT => return error.VulkanProfileExtensionNotPresent,
        vp.VK_ERROR_FEATURE_NOT_PRESENT => return error.VulkanProfileFeatureNotPresent,
        vp.VK_ERROR_INCOMPATIBLE_DRIVER => return error.VulkanProfileIncompatibleDriver,
        else => {
            std.log.err("Vulkan Profiles call failed with VkResult {}", .{result});
            return error.VulkanProfileFailed;
        },
    }
}

fn fromCInstance(handle: vp.VkInstance) vk.Instance {
    return @enumFromInt(@intFromPtr(handle));
}

fn toCInstance(handle: vk.Instance) vp.VkInstance {
    return @ptrFromInt(@intFromEnum(handle));
}

fn toCPhysicalDevice(handle: vk.PhysicalDevice) vp.VkPhysicalDevice {
    return @ptrFromInt(@intFromEnum(handle));
}

fn fromCDevice(handle: vp.VkDevice) vk.Device {
    return @enumFromInt(@intFromPtr(handle));
}
