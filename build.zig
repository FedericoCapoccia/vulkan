const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const python = b.option([]const u8, "python", "Python executable") orelse "python3";
    const slangc = b.option([]const u8, "slangc", "Slang compiler executable") orelse "slangc";
    const x11 = b.option(bool, "x11", "Enable GLFW X11 backend") orelse false;
    const wayland = b.option(bool, "wayland", "Enable GLFW Wayland backend") orelse true;

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const registry = vulkan_headers.path("registry/vk.xml");
    addGenerateVulkanProfilesStep(b, python, registry);

    const vulkan_zig = b.dependency("vulkan", .{
        .registry = registry,
    }).module("vulkan-zig");
    const vma = addVma(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .vulkan_include = vulkan_headers.path("include"),
    });
    const profiles = addVulkanProfiles(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .vulkan_include = vulkan_headers.path("include"),
    });

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = true,
        .x11 = x11,
        .wayland = wayland,
    });
    const zglfw_mod = zglfw.module("root");
    zglfw_mod.addImport("vulkan", vulkan_zig);

    const mod = b.addModule("vulkan", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("vulkan", vulkan_zig);
    mod.addImport("vma", vma.module);
    mod.addImport("zglfw", zglfw_mod);
    mod.addImport("vulkan-profiles", profiles.module);
    mod.linkLibrary(vma.library);
    mod.linkLibrary(profiles.library);
    if (target.result.os.tag != .emscripten) {
        mod.linkLibrary(zglfw.artifact("glfw"));
    }

    const exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
        .use_llvm = true,
    });
    b.installArtifact(exe);

    const shaders_step = b.step("shaders", "Compile and install shaders");
    addShaderInstallSteps(b, shaders_step, slangc);
    b.getInstallStep().dependOn(shaders_step);

    const check_exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
        .use_llvm = true,
    });

    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&check_exe.step);

    const run_step = b.step("run", "Run the installed app");
    const run_cmd = b.addSystemCommand(&.{b.getInstallPath(.bin, "vulkan")});
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

const VulkanProfiles = struct {
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
};

const Vma = struct {
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
};

const VmaOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_include: std.Build.LazyPath,
};

fn addVma(options: VmaOptions) Vma {
    const b = options.b;

    const lib_mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .link_libcpp = true,
    });
    lib_mod.addIncludePath(b.path("vendor/vma"));
    lib_mod.addIncludePath(options.vulkan_include);
    lib_mod.addCSourceFile(.{
        .file = b.path("vendor/vma/vma_impl.cpp"),
        .flags = &.{
            "-std=c++17",
            "-fno-exceptions",
            "-fno-rtti",
            "-DVMA_STATIC_VULKAN_FUNCTIONS=0",
            "-DVMA_DYNAMIC_VULKAN_FUNCTIONS=1",
        },
    });

    const library = b.addLibrary(.{
        .name = "vma",
        .root_module = lib_mod,
        .linkage = .static,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("vendor/vma/vk_mem_alloc.h"),
        .target = options.target,
        .optimize = options.optimize,
    });
    translate_c.addIncludePath(b.path("vendor/vma"));
    translate_c.addIncludePath(options.vulkan_include);
    translate_c.defineCMacro("VMA_STATIC_VULKAN_FUNCTIONS", "0");
    translate_c.defineCMacro("VMA_DYNAMIC_VULKAN_FUNCTIONS", "1");

    return .{
        .module = translate_c.createModule(),
        .library = library,
    };
}

const VulkanProfilesOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_include: std.Build.LazyPath,
};

fn addVulkanProfiles(options: VulkanProfilesOptions) VulkanProfiles {
    const b = options.b;
    const include_path = b.path("vendor/vulkan_profiles/generated/include");
    const header = b.path("vendor/vulkan_profiles/generated/include/vulkan/vulkan_profiles.h");

    const lib_mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .link_libcpp = true,
    });
    lib_mod.addIncludePath(include_path);
    lib_mod.addIncludePath(options.vulkan_include);
    lib_mod.addCSourceFile(.{
        .file = b.path("vendor/vulkan_profiles/generated/src/vulkan_profiles.cpp"),
        .flags = &.{
            "-std=c++17",
            "-fno-exceptions",
            "-fno-rtti",
            "-DVK_NO_PROTOTYPES",
            "-DVP_USE_OBJECT",
            "-DVP_NO_STATIC_VULKAN_FUNCTIONS",
        },
    });

    const library = b.addLibrary(.{
        .name = "vulkan_profiles",
        .root_module = lib_mod,
        .linkage = .static,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = header,
        .target = options.target,
        .optimize = options.optimize,
    });
    translate_c.addIncludePath(include_path);
    translate_c.addIncludePath(options.vulkan_include);
    translate_c.defineCMacro("VK_NO_PROTOTYPES", null);
    translate_c.defineCMacro("VP_USE_OBJECT", null);

    return .{
        .module = translate_c.createModule(),
        .library = library,
    };
}

fn addGenerateVulkanProfilesStep(b: *std.Build, python: []const u8, registry: std.Build.LazyPath) void {
    const step = b.step("generate-vulkan-profiles", "Generate Vulkan Profiles C API files into vendor");

    const cmd = b.addSystemCommand(&.{ python, "-W", "ignore::DeprecationWarning", "-c" });
    cmd.addArg(
        \\import os, runpy, shutil, sys
        \\out_dir, registry_path, input_dir, script = sys.argv[1:5]
        \\if os.path.exists(out_dir):
        \\    shutil.rmtree(out_dir)
        \\include_dir = os.path.join(out_dir, "include", "vulkan")
        \\src_dir = os.path.join(out_dir, "src")
        \\os.makedirs(include_dir, exist_ok=True)
        \\os.makedirs(src_dir, exist_ok=True)
        \\sys.argv = [
        \\    script,
        \\    "--registry", registry_path,
        \\    "--input", input_dir,
        \\    "--output-library-inc", include_dir,
        \\    "--output-library-src", src_dir,
        \\]
        \\runpy.run_path(script, run_name="__main__")
    );
    cmd.addArg("vendor/vulkan_profiles/generated");
    cmd.addFileArg(registry);
    cmd.addDirectoryArg(b.path("vendor/vulkan_profiles/profiles"));
    cmd.addFileArg(b.path("vendor/vulkan_profiles/gen_profiles_solution.py"));

    step.dependOn(&cmd.step);
}

fn addShaderInstallSteps(b: *std.Build, shaders_step: *std.Build.Step, slangc: []const u8) void {
    const dir = std.Io.Dir.cwd().openDir(b.graph.io, "resources/shaders", .{ .iterate = true }) catch {
        @panic("resources/shaders is required");
    };
    defer dir.close(b.graph.io);

    var found_shader = false;
    var iterator = dir.iterate();
    while (iterator.next(b.graph.io) catch @panic("failed to iterate resources/shaders")) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".slang")) continue;
        found_shader = true;

        const output_name = b.fmt("{s}.spv", .{entry.name[0 .. entry.name.len - ".slang".len]});
        const cmd = b.addSystemCommand(&.{slangc});
        cmd.addFileArg(b.path(b.pathJoin(&.{ "resources/shaders", entry.name })));
        cmd.addArgs(&.{
            "-target",
            "spirv",
            "-profile",
            "spirv_1_4",
            "-emit-spirv-directly",
            "-fvk-use-entrypoint-name",
            "-entry",
            "vertMain",
            "-entry",
            "fragMain",
            "-o",
        });

        const output = cmd.addOutputFileArg(output_name);
        const install = b.addInstallFileWithDir(
            output,
            .bin,
            b.pathJoin(&.{ "resources/shaders", output_name }),
        );
        shaders_step.dependOn(&install.step);
    }

    if (!found_shader) {
        @panic("resources/shaders must contain at least one .slang shader");
    }
}
