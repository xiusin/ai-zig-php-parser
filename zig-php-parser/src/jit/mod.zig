// JIT 模块统一入口
// 用于解决 Zig 0.15.2 模块系统的导入问题

pub const compiler = @import("compiler.zig");
pub const codegen = @import("codegen_x64.zig");
pub const type_inference = @import("type_inference.zig");
pub const hotspot_detector = @import("hotspot_detector.zig");
pub const osr = @import("osr.zig");
pub const code_cache = @import("code_cache.zig");

// 导出常用类型
pub const JITCompiler = compiler.JITCompiler;
pub const CodeGenerator = codegen.CodeGenerator;
pub const CodeCache = code_cache.CodeCache;
pub const Compiler = compiler.Compiler;
