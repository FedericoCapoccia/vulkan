const vk = @import("vulkan");

pub const Renderer = struct {
    device_handle: vk.Device,
    device_wrapper: vk.DeviceWrapper,

    pub fn create() void {}
    pub fn destroy() void {}
    pub fn drawFrame() void {}
    pub fn onResize() void {}
};
