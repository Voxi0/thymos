const std = @import("std");

// Construct build graph
pub fn build(b: *std.Build) void {
    // Constants
    const PROJECT_NAME: []const u8 = "thymos";
    const INCLUDE_DIR: []const u8 = "include";

    // Target architecture - Target is the native platform by default
    const arch = b.option(std.Target.Cpu.Arch, "arch", "Target architecture") orelse std.Target.Cpu.Arch.x86_64;
    var targetQuery: std.Target.Query = .{
        .cpu_arch = arch,
        .abi = .none,
        .os_tag = .freestanding,
    };
    switch (arch) {
        .x86_64 => {
            targetQuery.cpu_features_add = std.Target.x86.featureSet(&.{.soft_float});
            targetQuery.cpu_features_sub = std.Target.x86.featureSet(&.{ .sse, .sse2 });
        },
        else => {},
    }

    // Optimization mode - Can be either `Debug`, `ReleaseSafe`, `ReleaseFast`, or `ReleaseSmall`
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    // Commonly used constants and imports
    const commonMod = b.addModule("common", .{
        .root_source_file = b.path("src/common.zig"),
        .target = b.resolveTargetQuery(targetQuery),
        .optimize = optimize,
    });
    commonMod.addIncludePath(b.path(INCLUDE_DIR));

    // Colors
    const colorsMod = b.addModule("colors", .{
        .root_source_file = b.path("src/colors.zig"),
        .target = b.resolveTargetQuery(targetQuery),
        .optimize = optimize,
    });

    // Architecture specific stuff
    const archMod = b.addModule("arch", .{
        .root_source_file = b.path("src/arch/arch.zig"),
        .target = b.resolveTargetQuery(targetQuery),
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = commonMod },
            .{ .name = "colors", .module = colorsMod },
        },
    });

    // Kernel
    const kernelMod = b.addModule(PROJECT_NAME, .{
        .root_source_file = b.path("src/kernel.zig"),
        .target = b.resolveTargetQuery(targetQuery),
        .optimize = optimize,
        .imports = &.{
            .{ .name = "common", .module = commonMod },
            .{ .name = "arch", .module = archMod },
            .{ .name = "colors", .module = colorsMod },
        },
        .code_model = .kernel,
        .link_libc = false,
        .link_libcpp = false,
        .stack_check = false,
        .stack_protector = false,
        .unwind_tables = .none,
        .red_zone = false,
        .pic = false,
        .sanitize_c = .off,
        .strip = true,
    });
    kernelMod.addIncludePath(b.path(INCLUDE_DIR));
    kernelMod.addAssemblyFile(b.path(b.fmt("src/arch/{s}/asm.s", .{@tagName(arch)})));
    kernelMod.addCSourceFile(.{
        .language = .c,
        .file = b.path("src/compat.c"),
    });
    kernelMod.addCSourceFile(.{
        .language = .c,
        .file = b.path(b.fmt("{s}/printf/printf.c", .{INCLUDE_DIR})),
        .flags = &.{"-DPRINTF_INCLUDE_CONFIG_H"},
    });

    // Binary
    const thymos = b.addExecutable(.{
        .name = PROJECT_NAME,
        .root_module = kernelMod,
        .linkage = .static,
    });
    thymos.bundle_ubsan_rt = false;
    thymos.use_llvm = true;
    thymos.linker_script = b.path(b.fmt("src/arch/{s}/linker.ld", .{@tagName(arch)}));
    thymos.lto = .none;
    thymos.link_z_max_page_size = 0x1000;
    thymos.link_function_sections = true;
    thymos.link_data_sections = true;
    thymos.link_gc_sections = true;

    // Install binary into install prefix
    b.installArtifact(thymos);

    // Generate docs
    const genDocs = b.addInstallDirectory(.{
        .source_dir = thymos.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const genDocsStep = b.step("mkDocs", "Generate documentation and place into `zig-out/docs`");
    genDocsStep.dependOn(&genDocs.step);

    // Test step
    const kernelTests = b.addTest(.{ .root_module = kernelMod });
    const runKernelTests = b.addRunArtifact(kernelTests);
    const testStep = b.step("test", "Run tests");
    testStep.dependOn(&runKernelTests.step);
}
