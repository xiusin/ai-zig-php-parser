// Zig-PHP 统一根导入文件
// 用于解决 Zig 0.15.2 不允许使用 `../` 跨目录导入的问题
//
// 使用方式：
// const root = @import("root");
// const ast = root.compiler.ast;
// const Value = root.runtime.Value;

const std = @import("std");

// ============================================================================
// 编译器模块 (Compiler)
// ============================================================================

pub const compiler = struct {
    pub const ast = @import("compiler/ast.zig");
    pub const token = @import("compiler/token.zig");
    pub const parser = @import("compiler/parser.zig");
    pub const lexer = @import("compiler/lexer.zig");
    pub const syntax_mode = @import("compiler/syntax_mode.zig");
    pub const escape_analysis = @import("compiler/escape_analysis.zig");
    pub const register_alloc = @import("compiler/register_alloc.zig");
    pub const value = @import("compiler/value.zig");
};

// ============================================================================
// 运行时模块 (Runtime)
// ============================================================================

pub const runtime = struct {
    pub const types = @import("runtime/types.zig");
    pub const Value = types.Value;
    pub const vm = @import("runtime/vm.zig");
    pub const environment = @import("runtime/environment.zig");
    pub const exceptions = @import("runtime/exceptions.zig");
    pub const stdlib = @import("runtime/stdlib.zig");
    pub const reflection = @import("runtime/reflection.zig");
    pub const builtin_classes = @import("runtime/builtin_classes.zig");
    pub const builtin_registry = @import("runtime/builtin_registry.zig"); // Deprecated: 使用 fn_dispatch 替代
    pub const database = @import("runtime/database.zig");
    pub const string_utils = @import("runtime/string_utils.zig");
    pub const builtin_methods = @import("runtime/builtin_methods.zig");
    pub const builtin_concurrency = @import("runtime/builtin_concurrency.zig");
    pub const builtin_http = @import("runtime/builtin_http.zig");
    pub const builtin_io = @import("runtime/builtin_io.zig");
    pub const coroutine = @import("runtime/coroutine.zig");
    pub const gc = @import("runtime/gc.zig");
    pub const type_feedback = @import("runtime/type_feedback.zig");
    pub const optimization = @import("runtime/optimization.zig");
    pub const func = @import("runtime/func.zig");
    pub const opcode = @import("runtime/opcode.zig");
};

// ============================================================================
// 字节码模块 (Bytecode)
// ============================================================================

pub const bytecode = struct {
    pub const vm = @import("bytecode/vm.zig");
    pub const instruction = @import("bytecode/instruction.zig");
    pub const optimizer = @import("bytecode/optimizer.zig");
    pub const jit = @import("bytecode/jit.zig");
    pub const generator = @import("bytecode/generator.zig");
    pub const register_bytecode_gen = @import("bytecode/register_bytecode_gen.zig");
};

// ============================================================================
// JIT 编译器模块 (JIT)
// ============================================================================

pub const jit = struct {
    pub const compiler = @import("jit/compiler.zig");
    pub const code_cache = @import("jit/code_cache.zig");
    pub const assembler_arm64 = @import("jit/assembler_arm64.zig");
    pub const codegen_x64 = @import("jit/codegen_x64.zig");
    pub const type_inference = @import("jit/type_inference.zig");
    pub const inline_decision = @import("jit/inline_decision.zig");
    pub const perf_counter = @import("jit/perf_counter.zig");
    pub const hotspot_detector = @import("jit/hotspot_detector.zig");
    pub const fallback = @import("jit/fallback.zig");
    pub const debug_info = @import("jit/debug_info.zig");
    pub const stack_trace_integration = @import("jit/stack_trace_integration.zig");
};

// ============================================================================
// AOT 编译器模块 (AOT)
// ============================================================================

pub const aot = struct {
    pub const root = @import("aot/root.zig");
    pub const codegen = @import("aot/codegen.zig");
    pub const ir_generator = @import("aot/ir_generator.zig");
    pub const diagnostics = @import("aot/diagnostics.zig");
    pub const platform = @import("aot/platform.zig");
    pub const dwarf_debug_info = @import("aot/dwarf_debug_info.zig");
};

// ============================================================================
// 基准测试模块 (Benchmark)
// ============================================================================

pub const benchmark = struct {
    pub const string_benchmark = @import("benchmark/string_benchmark.zig");
    pub const array_benchmark = @import("benchmark/array_benchmark.zig");
    pub const jit_benchmark = @import("benchmark/jit_benchmark.zig");
    pub const aot_benchmark = @import("benchmark/aot_benchmark.zig");
    pub const regression_detector = @import("benchmark/regression_detector.zig");
    pub const ci_integration = @import("benchmark/ci_integration.zig");
    pub const perf_cli = @import("benchmark/perf_cli.zig");
};

// ============================================================================
// 扩展系统模块 (Extension)
// ============================================================================

pub const extension = struct {
    pub const api = @import("extension/api.zig");
    pub const registry = @import("extension/registry.zig");
};

// ============================================================================
// 测试工具 (Test Utilities)
// ============================================================================

pub const test_utils = struct {
    pub const std_lib = std;
    pub const testing = std.testing;
};
