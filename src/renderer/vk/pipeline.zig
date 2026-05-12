const vk = @import("vulkan");

pub const GraphicsPipeline = struct {
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,

    pub const CreateInfo = struct {
        device: vk.DeviceProxy,
        shader: vk.ShaderModule,
        extent: vk.Extent2D,
        format: vk.Format,
    };

    pub fn create(info: CreateInfo) !GraphicsPipeline {
        const stages = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .stage = .{ .vertex_bit = true },
                .module = info.shader,
                .p_name = "vertMain",
            },
            .{
                .stage = .{ .fragment_bit = true },
                .module = info.shader,
                .p_name = "fragMain",
            },
        };

        const vertex_input_state = vk.PipelineVertexInputStateCreateInfo{};

        const input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        const viewports = [_]vk.Viewport{.{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(info.extent.width),
            .height = @floatFromInt(info.extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        }};

        const scissors = [_]vk.Rect2D{.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = info.extent,
        }};

        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = @intCast(viewports.len),
            .p_viewports = viewports[0..].ptr,
            .scissor_count = @intCast(scissors.len),
            .p_scissors = scissors[0..].ptr,
        };

        const rasterizer = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
            .line_width = 1.0,
        };

        const multisampling = vk.PipelineMultisampleStateCreateInfo{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1.0,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        const color_blend_attachments = [_]vk.PipelineColorBlendAttachmentState{.{
            .blend_enable = .false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{
                .r_bit = true,
                .g_bit = true,
                .b_bit = true,
                .a_bit = true,
            },
        }};

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = color_blend_attachments[0..].ptr,
            .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
        };

        const dynamic_states = [_]vk.DynamicState{
            .viewport,
            .scissor,
        };

        const dynamic_state_info = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = @intCast(dynamic_states.len),
            .p_dynamic_states = dynamic_states[0..].ptr,
        };

        const color_attachments = [_]vk.Format{info.format};

        const rendering_cinfo = vk.PipelineRenderingCreateInfo{
            .view_mask = 0,
            .color_attachment_count = @intCast(color_attachments.len),
            .p_color_attachment_formats = color_attachments[0..].ptr,
            .depth_attachment_format = .undefined,
            .stencil_attachment_format = .undefined,
        };

        const layout = try info.device.createPipelineLayout(&.{
            .set_layout_count = 0,
            .push_constant_range_count = 0,
        }, null);
        errdefer info.device.destroyPipelineLayout(layout, null);

        const pipeline_cinfos = [_]vk.GraphicsPipelineCreateInfo{.{
            .stage_count = @intCast(stages.len),
            .p_stages = stages[0..].ptr,
            .p_vertex_input_state = &vertex_input_state,
            .p_input_assembly_state = &input_assembly_state,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisampling,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &dynamic_state_info,
            .layout = layout,
            .render_pass = .null_handle,
            .subpass = 0,
            .base_pipeline_index = -1,
            .p_next = &rendering_cinfo,
        }};

        var pipelines: [1]vk.Pipeline = undefined;
        const res = try info.device.createGraphicsPipelines(.null_handle, pipeline_cinfos[0..], null, pipelines[0..]);
        if (res != .success) return error.CreateGraphicsPipelineFailed;

        return GraphicsPipeline{
            .handle = pipelines[0],
            .layout = layout,
        };
    }

    pub fn destroy(self: *const GraphicsPipeline, device: vk.DeviceProxy) void {
        device.destroyPipeline(self.handle, null);
        device.destroyPipelineLayout(self.layout, null);
    }
};
