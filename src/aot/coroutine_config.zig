//! Go 式协程运行时构建配置（默认值）。
//!
//! 本文件为**源码树内默认配置**，供 `zig build test` 等树内编译解析。
//! AOT 产物构建时由 `native_linker.zig` 按编译器构建旗
//! （`-Dcoroutine=on|off`、`-Dcoroutine_backend=asm|ucontext`）
//! 在产物临时目录中重写本文件，实现构建期可切的回退开关（设计稿 §7）。

/// 协程总开关：false 时 Scheduler/Channel 退化为存根语义（设计稿 §7 回退）。
pub const enabled: bool = true;

/// 上下文切换后端。
pub const Backend = enum {
    /// 手写汇编切换（aarch64-macos/linux、x86_64-linux 正式路径）。
    @"asm",
    /// ucontext（makecontext/swapcontext）备份后端。
    ucontext,
};

/// 构建期选定的后端；对 asm 不支持的目标由 concurrency_runtime 在 comptime 回退 ucontext。
pub const backend: Backend = .@"asm";
