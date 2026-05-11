const vk = @import("vulkan");

pub const GraphicPipeline = struct {
    handle: vk.Pipeline,
    layout: vk.PipelineLayout,

    pub fn create(
        device: vk.DeviceProxy,
        shader: vk.ShaderModule,
        swap_extent: vk.Extent2D,
        swap_format: vk.Format,
    ) !GraphicPipeline {
        const ss_cinfo = [_]vk.PipelineShaderStageCreateInfo{
            .{
                .stage = .{ .vertex_bit = true },
                .module = shader,
                .p_name = "vertMain",
            },
            .{
                .stage = .{ .fragment_bit = true },
                .module = shader,
                .p_name = "fragMain",
            },
        };

        const dyn_state = [_]vk.DynamicState{
            .viewport,
            .scissor,
        };

        const ds_cinfo = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dyn_state.len,
            .p_dynamic_states = dyn_state[0..].ptr,
        };
        const vi_cinfo = vk.PipelineVertexInputStateCreateInfo{};
        const ass_cinfo = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        const viewport = vk.Viewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(swap_extent.width),
            .height = @floatFromInt(swap_extent.height),
            .min_depth = 0.0,
            .max_depth = 1.0,
        };

        const scissor = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swap_extent,
        };
        const viewports = [_]vk.Viewport{viewport};
        const scissors = [_]vk.Rect2D{scissor};

        const vs_cinfo = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = viewports[0..].ptr,
            .scissor_count = 1,
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

        const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
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
        };
        const color_blend_attachments = [_]vk.PipelineColorBlendAttachmentState{color_blend_attachment};

        const color_blending = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = color_blend_attachments[0..].ptr,
            .blend_constants = .{ 0.0, 0.0, 0.0, 0.0 },
        };

        const layout_cinfo = vk.PipelineLayoutCreateInfo{
            .set_layout_count = 0,
            .push_constant_range_count = 0,
        };

        const layout = try device.createPipelineLayout(&layout_cinfo, null);
        errdefer device.destroyPipelineLayout(layout, null);

        const rendering_cinfo = vk.PipelineRenderingCreateInfo{
            .view_mask = 0,
            .color_attachment_count = 1,
            .p_color_attachment_formats = @ptrCast(&swap_format),
            .depth_attachment_format = .undefined,
            .stencil_attachment_format = .undefined,
        };

        const pipeline_cinfo = vk.GraphicsPipelineCreateInfo{
            .p_next = &rendering_cinfo,
            .stage_count = ss_cinfo.len,
            .p_stages = &ss_cinfo,
            .p_vertex_input_state = &vi_cinfo,
            .p_input_assembly_state = &ass_cinfo,
            .p_viewport_state = &vs_cinfo,
            .p_rasterization_state = &rasterizer,
            .p_multisample_state = &multisampling,
            .p_color_blend_state = &color_blending,
            .p_dynamic_state = &ds_cinfo,
            .layout = layout,
            .render_pass = .null_handle,
            .subpass = 0,
            .base_pipeline_index = -1,
        };

        var pipelines: [1]vk.Pipeline = undefined;
        const pipeline_cinfos = [_]vk.GraphicsPipelineCreateInfo{pipeline_cinfo};
        const result = try device.createGraphicsPipelines(
            .null_handle,
            pipeline_cinfos[0..],
            null,
            pipelines[0..],
        );
        if (result != .success) return error.CreateGraphicsPipelineFailed;

        return GraphicPipeline{
            .handle = pipelines[0],
            .layout = layout,
        };
    }

    pub fn destroy(self: *const GraphicPipeline, device: vk.DeviceProxy) void {
        device.destroyPipeline(self.handle, null);
        device.destroyPipelineLayout(self.layout, null);
    }
};
