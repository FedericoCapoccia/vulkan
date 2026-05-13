const std = @import("std");

const vk = @import("vulkan");
const vp = @import("vulkan-profiles");

pub const EngineProfile = enum {
    minimal,
    roadmap2024,
    roadmap2026,

    pub fn properties(self: EngineProfile) vp.VpProfileProperties {
        var props = vp.VpProfileProperties{};
        const name = switch (self) {
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
        return props;
    }
};

pub const EngineFeature = enum {
    shader_draw_parameters,

    pub fn providedBy(self: EngineFeature, engine_profile: EngineProfile) bool {
        return switch (self) {
            .shader_draw_parameters => switch (engine_profile) {
                .minimal => false,
                .roadmap2024, .roadmap2026 => true,
            },
        };
    }
};

pub const EngineExtension = enum {
    swapchain,

    pub fn providedBy(self: EngineExtension, engine_profile: EngineProfile) bool {
        return switch (self) {
            .swapchain => switch (engine_profile) {
                .minimal, .roadmap2024 => false,
                .roadmap2026 => true,
            },
        };
    }

    pub fn name(self: EngineExtension) [*:0]const u8 {
        return switch (self) {
            .swapchain => vk.extensions.khr_swapchain.name,
        };
    }
};

// Extensions and features required but not included in VP_LUNARG_minimum_requirements_1_3
pub const EngineRequirements = struct {
    extra_device_extensions: []const EngineExtension,
    extra_features: []const EngineFeature,
};

const max_extra_device_extensions = @typeInfo(EngineExtension).@"enum".fields.len;

pub fn supportedProfile(
    base: vk.BaseWrapper,
    instance_api_version: u32,
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    requirements: *const EngineRequirements,
    allocator: std.mem.Allocator,
) error{ OutOfMemory, VulkanError }!?EngineProfile {
    const capabilities = createCapabilities(base, instance_api_version, instance) catch return error.VulkanError;
    defer vp.vpDestroyCapabilities(capabilities, null);

    const candidates = [_]EngineProfile{
        .roadmap2026,
        .roadmap2024,
        .minimal,
    };

    for (candidates) |candidate| {
        var props = candidate.properties();

        var supported: vp.VkBool32 = vp.VK_FALSE;
        check(vp.vpGetPhysicalDeviceProfileSupport(
            capabilities,
            toCInstance(instance.handle),
            toCPhysicalDevice(pdev),
            &props,
            &supported,
        )) catch return error.VulkanError;

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
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    engine_profile: EngineProfile,
    extra_extensions: []const EngineExtension,
    allocator: std.mem.Allocator,
) error{ OutOfMemory, VulkanError }!bool {
    const available = instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator) catch |err| {
        std.log.err("Failed to enumerate available device extensions: {}", .{err});
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.VulkanError,
        };
    };
    defer allocator.free(available);

    for (extra_extensions) |extension| {
        if (extension.providedBy(engine_profile)) continue;

        const required_name = std.mem.span(extension.name());
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
    instance: vk.InstanceProxy,
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
        if (feature.providedBy(engine_profile)) continue;

        switch (feature) {
            .shader_draw_parameters => {
                if (features_1_1.shader_draw_parameters == .false) return false;
            },
        }
    }

    return true;
}

pub fn createDevice(
    base: vk.BaseWrapper,
    instance_api_version: u32,
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    queue_family: u32,
    engine_profile: EngineProfile,
    requirements: *const EngineRequirements,
) !vk.Device {
    const capabilities = try createCapabilities(base, instance_api_version, instance);
    defer vp.vpDestroyCapabilities(capabilities, null);

    std.log.info("Creating logical device", .{});
    std.log.info("\tEngine profile: {s}", .{@tagName(engine_profile)});

    var vulkan_11_features = vp.VkPhysicalDeviceVulkan11Features{
        .sType = vp.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
    };

    var p_next: ?*anyopaque = null;
    if (requiresManualFeature(engine_profile, requirements.extra_features, .shader_draw_parameters)) {
        vulkan_11_features.shaderDrawParameters = vp.VK_TRUE;
        p_next = &vulkan_11_features;
        std.log.info("\t[EXTRA FEATURE] shader_draw_parameters", .{});
    }

    var extension_storage: [max_extra_device_extensions][*:0]const u8 = undefined;
    var extension_count: usize = 0;
    for (requirements.extra_device_extensions) |extension| {
        if (extension.providedBy(engine_profile)) continue;
        extension_storage[extension_count] = extension.name();
        extension_count += 1;
        std.log.info("\t[EXTRA EXTENSION] {s}", .{std.mem.span(extension.name())});
    }
    const extensions = extension_storage[0..extension_count];

    const queue_priority = [_]f32{1.0};
    const queue_cinfo = [_]vp.VkDeviceQueueCreateInfo{.{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family,
        .queueCount = 1,
        .pQueuePriorities = queue_priority[0..].ptr,
    }};

    const device_cinfo = vp.VkDeviceCreateInfo{
        .sType = vp.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = p_next,
        .queueCreateInfoCount = queue_cinfo.len,
        .pQueueCreateInfos = queue_cinfo[0..].ptr,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = if (extensions.len == 0) null else @ptrCast(extensions.ptr),
    };

    var selected_profile = engine_profile.properties();
    const profile_cinfo = vp.VpDeviceCreateInfo{
        .pCreateInfo = &device_cinfo,
        .enabledFullProfileCount = 1,
        .pEnabledFullProfiles = &selected_profile,
    };

    var device: vp.VkDevice = null;
    try check(vp.vpCreateDevice(
        capabilities,
        toCPhysicalDevice(pdev),
        &profile_cinfo,
        null,
        &device,
    ));

    return fromCDevice(device);
}

fn createCapabilities(base: vk.BaseWrapper, instance_api_version: u32, instance: vk.InstanceProxy) !vp.VpCapabilities {
    const vulkan_functions = vp.VpVulkanFunctions{
        .GetInstanceProcAddr = @ptrCast(base.dispatch.vkGetInstanceProcAddr),
        .GetDeviceProcAddr = @ptrCast(instance.wrapper.dispatch.vkGetDeviceProcAddr),
        .EnumerateInstanceVersion = @ptrCast(base.dispatch.vkEnumerateInstanceVersion),
        .EnumerateInstanceExtensionProperties = @ptrCast(base.dispatch.vkEnumerateInstanceExtensionProperties),
        .EnumerateDeviceExtensionProperties = @ptrCast(instance.wrapper.dispatch.vkEnumerateDeviceExtensionProperties),
        .GetPhysicalDeviceFeatures2 = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceFeatures2),
        .GetPhysicalDeviceProperties2 = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceProperties2),
        .GetPhysicalDeviceFormatProperties2 = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceFormatProperties2),
        .GetPhysicalDeviceQueueFamilyProperties2 = @ptrCast(instance.wrapper.dispatch.vkGetPhysicalDeviceQueueFamilyProperties2),
        .CreateInstance = @ptrCast(base.dispatch.vkCreateInstance),
        .CreateDevice = @ptrCast(instance.wrapper.dispatch.vkCreateDevice),
    };
    const cap_cinfo = vp.VpCapabilitiesCreateInfo{
        .apiVersion = instance_api_version,
        .pVulkanFunctions = &vulkan_functions,
    };

    var capabilities: vp.VpCapabilities = undefined;
    try check(vp.vpCreateCapabilities(&cap_cinfo, null, &capabilities));
    return capabilities;
}

fn requiresManualFeature(engine_profile: EngineProfile, extra_features: []const EngineFeature, feature: EngineFeature) bool {
    if (feature.providedBy(engine_profile)) return false;

    for (extra_features) |extra_feature| {
        if (extra_feature == feature) return true;
    }

    return false;
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
