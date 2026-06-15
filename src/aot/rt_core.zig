const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

//! AOT Runtime Library Template
//!
//! 这是AOT编译器使用的完整运行时库模板。
//! 实现了PHP值类型系统和所有必需的运算符函数。
//!
//! ## 设计原则
//! 1. **零依赖**：除了Zig标准库，不依赖任何其他模块
//! 2. **内存安全**：使用引用计数管理内存，防止泄漏
//! 3. **性能优化**：使用NaN boxing技术，48位整数快速路径
//! 4. **PHP语义**：严格遵循PHP 8.5的类型转换和运算规则
//!
//! @ownership TRANSFER (Value类型通过引用计数管理)
//! @thread-safety ISOLATED (每个编译的程序独立运行)
//! @memory-model Reference Counting with Cycle Detection

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const concurrency = @import("concurrency_runtime.zig");
const array_ops_shared = @import("array_ops_shared.zig");
const nanbox_abi = @import("nanbox_abi.zig");
pub const profiler = @import("profiler.zig");
pub const flamegraph = @import("flamegraph.zig");
pub const pprof = @import("pprof.zig");

