const std = @import("std");
const generate = @import("generate.zig");

const rayguiSrc = "raygui/src/";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    //--- parse raygui and generate JSONs for all signatures --------------------------------------
    const jsons = b.step("parse", "parse raygui headers and generate raylib parser output as json");
    const raylib_parser_build = b.addExecutable(.{
        .name = "raylib_parser",
        .root_source_file = std.build.FileSource.relative("raylib_parser.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    raylib_parser_build.addCSourceFile("../raylib/raylib/parser/raylib_parser.c", &.{});
    raylib_parser_build.linkLibC();

    //raygui
    const raygui_H = b.addRunArtifact(raylib_parser_build);
    raygui_H.addArgs(&.{
        "-i", "raygui/src/raygui.h",
        "-o", "raygui.json",
        "-f", "JSON",
        "-d", "RAYGUIAPI",
    });
    jsons.dependOn(&raygui_H.step);

    //--- Generate intermediate -------------------------------------------------------------------
    const intermediate = b.step("intermediate", "generate intermediate representation of the results from 'zig build parse' (keep custom=true)");
    var intermediateZig = b.addRunArtifact(b.addExecutable(.{
        .name = "intermediate",
        .root_source_file = std.build.FileSource.relative("intermediate.zig"),
        .target = target,
    }));
    intermediate.dependOn(&intermediateZig.step);

    //--- Generate bindings -----------------------------------------------------------------------
    const bindings = b.step("bindings", "generate bindings in from bindings.json");
    var generateZig = b.addRunArtifact(b.addExecutable(.{
        .name = "generate",
        .root_source_file = std.build.FileSource.relative("generate.zig"),
        .target = target,
    }));
    const fmt = b.addFmt(.{ .paths = &.{generate.outputFile} });
    fmt.step.dependOn(&generateZig.step);
    bindings.dependOn(&fmt.step);

    //--- just build raylib_parser.exe ------------------------------------------------------------
    const raylib_parser_install = b.step("raylib_parser", "build ./zig-out/bin/raylib_parser.exe");
    const generateBindings_install = b.addInstallArtifact(raylib_parser_build);
    raylib_parser_install.dependOn(&generateBindings_install.step);
}

// above: generate library
// below: linking (use as dependency)

fn current_file() []const u8 {
    return @src().file;
}

const cwd = std.fs.path.dirname(current_file()).?;
const sep = std.fs.path.sep_str;
const dir_raygui = cwd ++ sep ++ "raygui/src";

/// add this package to lib
pub fn addTo(b: *std.Build, lib: *std.build.LibExeObjStep, target: std.zig.CrossTarget, optimize: std.builtin.Mode) void {
    _ = b;
    _ = optimize;
    _ = target;

    if (lib.modules.get("raylib") orelse lib.modules.get("raylib.zig") orelse lib.modules.get("raylib-zig")) |raylib| {
        lib.addAnonymousModule("raygui", .{
            .source_file = .{ .path = cwd ++ sep ++ "raygui.zig" },
            .dependencies = &.{
                .{ .name = "raylib", .module = raylib },
            },
        });
        lib.addIncludePath(dir_raygui);
        lib.addIncludePath(cwd);
        lib.linkLibC();
        lib.addCSourceFile(cwd ++ sep ++ "raygui_marshal.c", &.{"-DRAYGUI_IMPLEMENTATION"});
    } else {
        std.debug.panic("lib needs to have 'raylib', 'raylib.zig' or 'raylib-zig' as module dependency", .{});
    }
}
