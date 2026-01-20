// Runtime 模块统一入口
// 用于解决 Zig 0.15.2 模块系统的导入问题

// 核心类型系统
pub const types = @import("types.zig");
pub const vm = @import("vm.zig");
pub const func = @import("func.zig");
pub const opcode = @import("opcode.zig");

// 内存管理
pub const gc = @import("gc.zig");
pub const memory = @import("memory.zig");
pub const object_pool = @import("object_pool.zig");

// 性能优化
pub const type_feedback = @import("type_feedback.zig");
pub const optimization = @import("optimization.zig");
pub const loop_optimizer = @import("loop_optimizer.zig");
pub const fast_vm = @import("fast_vm.zig");
pub const fast_compiler = @import("fast_compiler.zig");
pub const fast_runtime = @import("fast_runtime.zig");

// 并发支持
pub const concurrency = @import("concurrency.zig");
pub const builtin_concurrency = @import("builtin_concurrency.zig");
pub const async_io = @import("async_io.zig");
pub const coroutine = @import("coroutine.zig");

// 调试和诊断
pub const stack_trace = @import("stack_trace.zig");
pub const debugger = @import("debugger.zig");
pub const profiler = @import("profiler.zig");
pub const leak_detector = @import("leak_detector.zig");
pub const crash_handler = @import("crash_handler.zig");
pub const flamegraph = @import("flamegraph.zig");

// 内置函数
pub const builtin_dispatch = @import("builtin_dispatch.zig");
pub const builtin_methods = @import("builtin_methods.zig");
pub const builtin_classes = @import("builtin_classes.zig");
pub const builtin_math = @import("builtin_math.zig");
pub const builtin_time = @import("builtin_time.zig");
pub const builtin_io = @import("builtin_io.zig");
pub const builtin_http = @import("builtin_http.zig");

// 导出常用类型（方便外部使用）
pub const Value = types.Value;
pub const PHPString = types.PHPString;
pub const PHPArray = types.PHPArray;
pub const PHPObject = types.PHPObject;
pub const PHPClass = types.PHPClass;
pub const PHPFunction = types.PHPFunction;
