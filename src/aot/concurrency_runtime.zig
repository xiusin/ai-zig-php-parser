//! Go 式协程运行时（M1：N:1 单线程协作式调度）
//!
//! 设计依据：docs/design/2026-11-08-go-style-coroutine-design.md（老铁已批准）
//! 永久裁决：协程能力由 AOT 运行时自有的 Go 风格协程系统提供（AGENTS.md §七.1/§七.9），
//! 不实现 PHP Fiber/生成器语义，面命名保持 go* + Channel（与 PHP 内建零冲突）。
//!
//! M1 内容：asm/ucontext 上下文切换 + 64KB 定长栈（末尾保护页）+ ready FIFO/blocked 集
//! + Channel 真阻塞语义 + go/go_join/go_wait_all 换真 + 每协程全局态快照（hooks）
//! + 死锁检测 + 协程内未捕获异常整程序致命（D1=A）+ cycle-GC 多协程期禁用配合（D4=A）。

const std = @import("std");
const builtin = @import("builtin");
const co_config = @import("coroutine_config.zig");
const Allocator = std.mem.Allocator;

/// 协程总开关（-Dcoroutine=off 时为 false，Scheduler/Channel 退化为存根语义——设计稿 §7 回退）。
pub const enabled = co_config.enabled;

// ============================================================================
// ExecutionContext（既有面：作用域/called class，每协程私有、切换时随动）
// ============================================================================

pub const ExecutionContext = struct {
    called_class: ?usize = null,
    scope_class: ?usize = null,
};

threadlocal var execution_context: ExecutionContext = .{};

pub fn getExecutionContext() *ExecutionContext {
    return &execution_context;
}

// ============================================================================
// 全局态快照 hooks（模板侧注册：异常旗/pending 异常、@抑制深度、src 位置、实参链、q4 FIFO）
// ============================================================================

/// 每协程快照缓冲容量（设计容量；模板注册时校验实际尺寸不超过该值）。
pub const STATE_SNAPSHOT_CAPACITY: usize = 4096;

/// 全局态快照钩子。所有权纪律（防泄漏/防双重释放）：
///   - init：写入「新协程初始态」（全空/清零）；
///   - save：把当前全局态拷入 buf（buf 中原有的堆持有已在 restore 时清空）；
///   - restore：把 buf 态写回全局，并清空 buf 内堆持有标记（所有权移回全局）；
///   - deinit：释放 buf 内仍持有的堆资源（协程收尾与调度器销毁时用）。
pub const StateHooks = struct {
    /// 模板侧快照结构体实际字节数（必须 <= STATE_SNAPSHOT_CAPACITY）。
    size: usize,
    init: *const fn (buf: [*]u8) void,
    save: *const fn (buf: [*]u8) void,
    restore: *const fn (buf: [*]const u8) void,
    deinit: *const fn (buf: [*]u8) void,
};

var state_hooks: ?StateHooks = null;

pub fn registerStateHooks(hooks: StateHooks) void {
    std.debug.assert(hooks.size <= STATE_SNAPSHOT_CAPACITY);
    state_hooks = hooks;
}

// ============================================================================
// 机器上下文与切换（asm 正式路径 + ucontext 备份后端）
// ============================================================================

const native_arch = builtin.cpu.arch;
const native_os = builtin.os.tag;

/// 设计稿 §3.1 平台矩阵：aarch64-macos/aarch64-linux/x86_64-linux 走 asm；
/// 其余（如 x86_64-macos）comptime 回退 ucontext。
const asm_supported = switch (native_arch) {
    .aarch64 => native_os == .macos or native_os == .linux,
    .x86_64 => native_os == .linux,
    else => false,
};

/// 实际生效后端（构建旗选定 asm 但目标不支持时自动落 ucontext）。
pub const backend_effective: co_config.Backend = if (co_config.backend == .@"asm" and asm_supported) .@"asm" else .ucontext;

/// 汇编后端上下文（设计稿 §3.1：callee-saved 寄存器 + fp/sp/pc 全集显式保存）。
/// 保全策略：裸函数 go_ctx_switch 经 ABI 调用边界（bl/call）切入——
///   caller-saved 寄存器由编译器按调用约定自行溢出；
///   callee-saved 寄存器（含 aarch64 d8-d15）由切换汇编逐个存入/读出 Context；
///   pc 槽保存本调用点返回地址（lr/栈顶），恢复后执行流在调用方自然继续。
pub const Context = switch (native_arch) {
    .aarch64 => extern struct {
        x19: u64 = 0,
        x20: u64 = 0,
        x21: u64 = 0,
        x22: u64 = 0,
        x23: u64 = 0,
        x24: u64 = 0,
        x25: u64 = 0,
        x26: u64 = 0,
        x27: u64 = 0,
        x28: u64 = 0,
        d8: u64 = 0,
        d9: u64 = 0,
        d10: u64 = 0,
        d11: u64 = 0,
        d12: u64 = 0,
        d13: u64 = 0,
        d14: u64 = 0,
        d15: u64 = 0,
        fp: u64 = 0,
        sp: u64 = 0,
        pc: u64 = 0,
    },
    .x86_64 => extern struct {
        rbx: u64 = 0,
        rbp: u64 = 0,
        r12: u64 = 0,
        r13: u64 = 0,
        r14: u64 = 0,
        r15: u64 = 0,
        rsp: u64 = 0,
        rip: u64 = 0,
    },
    else => extern struct {
        sp: u64 = 0,
        fp: u64 = 0,
        pc: u64 = 0,
    },
};

/// go_ctx_switch：保存当前 CPU 态到 save，恢复 restore 中保存的 CPU 态（永不直接返回——
/// 执行流在**另一次**切换恢复本上下文时，从本调用点的返回地址继续）。
/// 全局汇编定义（.globl 外部符号）：LLVM 看不到函数体，无法内联/去虚拟化——
/// 这是「按 ABI 调用但语义为栈切换」唯一稳妥的落地形（libco/Boost.Context 同宗；
/// 此前的 Zig naked fn + 函数指针路径在 Release 下被 LLVM 内联克隆裸体而寄存器错位）。
/// callee-saved 全由汇编存入/读出 Context，pc 槽存调用点返回地址。
extern "c" fn go_ctx_switch(save: *Context, restore: *const Context) void;

comptime {
    const sym = if (native_os == .macos or native_os == .ios) "_go_ctx_switch" else "go_ctx_switch";
    switch (native_arch) {
        .aarch64 => asm (".globl " ++ sym ++ "\n.p2align 2\n" ++ sym ++ ":\n" ++
            \\ stp x19, x20, [x0, #0]
            \\ stp x21, x22, [x0, #16]
            \\ stp x23, x24, [x0, #32]
            \\ stp x25, x26, [x0, #48]
            \\ stp x27, x28, [x0, #64]
            \\ stp d8,  d9,  [x0, #80]
            \\ stp d10, d11, [x0, #96]
            \\ stp d12, d13, [x0, #112]
            \\ stp d14, d15, [x0, #128]
            \\ mov x9, sp
            \\ stp x29, x9, [x0, #144]
            \\ str x30, [x0, #160]
            \\ ldp x19, x20, [x1, #0]
            \\ ldp x21, x22, [x1, #16]
            \\ ldp x23, x24, [x1, #32]
            \\ ldp x25, x26, [x1, #48]
            \\ ldp x27, x28, [x1, #64]
            \\ ldp d8,  d9,  [x1, #80]
            \\ ldp d10, d11, [x1, #96]
            \\ ldp d12, d13, [x1, #112]
            \\ ldp d14, d15, [x1, #128]
            \\ ldp x29, x9, [x1, #144]
            \\ mov sp, x9
            \\ ldr x9, [x1, #160]
            \\ br x9
        ),
        .x86_64 => asm (".globl " ++ sym ++ "\n.p2align 4\n" ++ sym ++ ":\n" ++
            \\ movq %rbx, 0(%rdi)
            \\ movq %rbp, 8(%rdi)
            \\ movq %r12, 16(%rdi)
            \\ movq %r13, 24(%rdi)
            \\ movq %r14, 32(%rdi)
            \\ movq %r15, 40(%rdi)
            \\ movq %rsp, 48(%rdi)
            \\ movq (%rsp), %rax
            \\ movq %rax, 56(%rdi)
            \\ movq 0(%rsi), %rbx
            \\ movq 8(%rsi), %rbp
            \\ movq 16(%rsi), %r12
            \\ movq 24(%rsi), %r13
            \\ movq 32(%rsi), %r14
            \\ movq 40(%rsi), %r15
            \\ movq 48(%rsi), %rsp
            \\ movq 56(%rsi), %rax
            \\ jmpq *%rax
        ),
        else => {},
    }
}

// ---- ucontext 备份后端 ----

/// POSIX stack_t 字段序随平台不同（darwin: ptr,size,int；linux: ptr,int,size），
/// 这里按平台给出 ucontext 头部布局，尾部留足 mcontext 空间（aarch64-linux mcontext 含 4KB 扩展区）。
const UContextHead = switch (native_os) {
    .macos, .ios, .tvos, .watchos, .visionos, .maccatalyst, .driverkit => extern struct {
        uc_onstack: c_int,
        uc_sigmask: u32,
        ss_sp: ?*anyopaque,
        ss_size: usize,
        ss_flags: c_int,
        uc_link: ?*anyopaque,
    },
    .linux => extern struct {
        uc_flags: u64,
        uc_link: ?*anyopaque,
        ss_sp: ?*anyopaque,
        ss_flags: c_int,
        ss_size: usize,
    },
    else => extern struct {
        uc_link: ?*anyopaque = null,
        ss_sp: ?*anyopaque = null,
        ss_flags: c_int = 0,
        ss_size: usize = 0,
    },
};

/// ucontext_t  opaque 承载（头部显式布局 + 尾部足够容纳各平台 mcontext）。
const UContext = extern struct {
    head: UContextHead,
    tail: [8192 - @sizeOf(UContextHead)]u8 align(16),
};

extern "c" fn getcontext(ucp: *UContext) c_int;
extern "c" fn makecontext(ucp: *UContext, func: *const fn () callconv(.c) void, argc: c_int, ...) void;
extern "c" fn swapcontext(oucp: *UContext, ucp: *const UContext) c_int;

fn go_ctx_switch_ucontext(save: *UContext, restore: *const UContext) void {
    if (swapcontext(save, restore) != 0) unreachable;
}

/// 机器上下文统一承载（comptime 按生效后端二选一）。
const MachineContext = switch (backend_effective) {
    .@"asm" => Context,
    .ucontext => UContext,
};

/// 统一切换入口。asm 路径为外部符号 ABI 调用（callee-saved 由汇编保全，caller-saved 由编译器保全）。
fn machineCtxSwitch(save: *MachineContext, restore: *MachineContext) void {
    switch (backend_effective) {
        .@"asm" => go_ctx_switch(save, restore),
        .ucontext => go_ctx_switch_ucontext(save, restore),
    }
}

// ============================================================================
// 栈分配（64KB 定长 + 末尾保护页；设计 D2：M1 定长，M3 才评审扩容）
// ============================================================================

/// 每协程可用栈尺寸。
/// ★AOT-CODEGEN-012 组9 验收（L-3）：原 64KB 实测仅容纳 ~30 层 PHP 调用帧
/// （AOT 每帧约 2KB：寄存器暂存 + Value 临时量），40 层即保护页致命，无法满足
/// 「协程内正常业务调用（20+ 层）」；提升到 256KB（≈120 层）。
/// 虚拟占用 256KB+1 页/协程（1 万协程 ≈ 2.6GB 虚拟，按需驻留——实测 RSS 与 64KB
/// 时同级，因仅触碰实际使用页）；M3 动态扩容（D2 决议）仍按设计推进。
pub const STACK_SIZE: usize = 256 * 1024;

const StackAlloc = struct {
    /// 完整映射（含低址保护页）。
    mapping: []align(std.heap.page_size_min) u8,
    guard_size: usize,
    /// 可用区顶（16 字节对齐；栈向下生长，初始 sp 取此）。
    usable_top: usize,
    /// 可用区底（= mapping 基址 + guard_size）。
    usable_base: usize,

    fn alloc(size: usize) !StackAlloc {
        const page = std.heap.pageSize();
        const guard = page;
        const total = std.mem.alignForward(usize, guard + size, page);
        const mem = try std.posix.mmap(
            null,
            total,
            .{ .READ = true, .WRITE = true },
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        errdefer std.posix.munmap(mem);
        // 末尾（低址）保护页：越界即 SIGSEGV，由信号处理器转可读致命错（设计稿 §3.1/§7）。
        if (std.c.mprotect(@ptrCast(mem.ptr), guard, .{}) != 0) {
            std.posix.munmap(mem);
            return error.OutOfMemory;
        }
        const base = @intFromPtr(mem.ptr);
        return .{
            .mapping = mem,
            .guard_size = guard,
            .usable_base = base + guard,
            .usable_top = std.mem.alignBackward(usize, base + total, 16),
        };
    }

    fn deinit(self: *StackAlloc) void {
        std.posix.munmap(self.mapping);
    }

    fn guardStart(self: *const StackAlloc) usize {
        return @intFromPtr(self.mapping.ptr);
    }

    fn guardEnd(self: *const StackAlloc) usize {
        return @intFromPtr(self.mapping.ptr) + self.guard_size;
    }
};

// ============================================================================
// 协程体
// ============================================================================

pub const CoroutineState = enum { ready, running, blocked, finished };

pub const Coroutine = struct {
    id: u64,
    state: CoroutineState,
    func_ptr: *const fn (?*anyopaque) anyerror!void,
    context: ?*anyopaque,
    result: ?*anyopaque,
    err: ?anyerror,
    allocator: Allocator,

    // ---- M1 调度内核 ----
    ctx: MachineContext = undefined,
    stack: ?StackAlloc = null,
    is_main: bool = false,
    started: bool = false,
    join_waiters: std.ArrayListUnmanaged(*Coroutine) = .empty,
    state_buf: [STATE_SNAPSHOT_CAPACITY]u8 align(16) = undefined,
    exec_ctx: ExecutionContext = .{},
    timer_fired: bool = false,
    next_free: ?*Coroutine = null,

    pub fn init(allocator: Allocator, id: u64, func: *const fn (?*anyopaque) anyerror!void, ctx: ?*anyopaque) !*Coroutine {
        const coro = try allocator.create(Coroutine);
        coro.* = .{
            .id = id,
            .state = .ready,
            .func_ptr = func,
            .context = ctx,
            .result = null,
            .err = null,
            .allocator = allocator,
        };
        return coro;
    }

    pub fn deinit(self: *Coroutine) void {
        self.allocator.destroy(self);
    }
};

// ============================================================================
// Channel（Go 对齐阻塞语义：cap=0 无缓冲对接、满 send/空 recv 让出、close 语义）
// ============================================================================

pub fn Channel(comptime T: type) type {
    if (!enabled) return StubChannel(T);
    return struct {
        const Self = @This();

        /// send 阻塞时挂入的等待者（value 为待交接数据，随等待者驻留到被唤醒）。
        const SendWaiter = struct {
            coro: *Coroutine,
            value: T,
        };
        /// recv 阻塞时挂入的等待者；slot 指向阻塞帧上的收件槽，交接时直写。
        const RecvWaiter = struct {
            coro: *Coroutine,
            slot: *?T,
        };

        buffer: std.ArrayListUnmanaged(T) = .empty,
        capacity: usize,
        closed: bool = false,
        allocator: Allocator,
        send_waiters: std.ArrayListUnmanaged(SendWaiter) = .empty,
        recv_waiters: std.ArrayListUnmanaged(RecvWaiter) = .empty,

        pub fn init(allocator: Allocator, cap: usize) !*Self {
            const ch = try allocator.create(Self);
            ch.* = .{
                .capacity = cap, // cap=0：无缓冲（send 必等 recv 对接，Go 语义）
                .allocator = allocator,
            };
            return ch;
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
            self.send_waiters.deinit(self.allocator);
            self.recv_waiters.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        /// 阻塞式 send。closed ⇒ error.ChannelClosed（模板侧映射为可捕获 Error「send on closed channel」）。
        pub fn send(self: *Self, value: T) !void {
            if (self.closed) return error.ChannelClosed;
            // 有等待接收者：直接对接（无缓冲语义的核心路径，缓冲通道空转时也走此）。
            if (self.recv_waiters.items.len > 0) {
                const w = self.recv_waiters.orderedRemove(0);
                w.slot.* = value;
                wakeCoroutine(w.coro);
                return;
            }
            if (self.buffer.items.len < self.capacity) {
                try self.buffer.append(self.allocator, value);
                return;
            }
            // 满（或无缓冲无接收者）：挂起让出。
            const sched = try getSchedulerFromChannel(self.allocator);
            const me = sched.currentCoroutine();
            try self.send_waiters.append(self.allocator, .{ .coro = me, .value = value });
            sched.blockCurrent();
            // 唤醒后：close 可能先到，此时本 send 失败（值由调用方按错误路径释放）。
            if (self.closed) return error.ChannelClosed;
        }

        pub fn trySend(self: *Self, value: T) !bool {
            if (self.closed) return error.ChannelClosed;
            if (self.recv_waiters.items.len > 0) {
                const w = self.recv_waiters.orderedRemove(0);
                w.slot.* = value;
                wakeCoroutine(w.coro);
                return true;
            }
            if (self.buffer.items.len >= self.capacity) return false;
            try self.buffer.append(self.allocator, value);
            return true;
        }

        /// 阻塞式 recv。closed 且残余取尽 ⇒ error.ChannelClosed（模板侧映射为返回 null，Go ok=false 口径）。
        pub fn recv(self: *Self) !T {
            while (true) {
                if (self.buffer.items.len > 0) {
                    const value = self.buffer.orderedRemove(0);
                    self.pumpSendWaiters();
                    return value;
                }
                if (self.send_waiters.items.len > 0) {
                    // 无缓冲对接：直接取等待发送者的值。
                    const w = self.send_waiters.orderedRemove(0);
                    wakeCoroutine(w.coro);
                    return w.value;
                }
                if (self.closed) return error.ChannelClosed;
                var got: ?T = null;
                const sched = try getSchedulerFromChannel(self.allocator);
                const me = sched.currentCoroutine();
                try self.recv_waiters.append(self.allocator, .{ .coro = me, .slot = &got });
                sched.blockCurrent();
                // 唤醒路径：被 send 交接（got 有值）或被 close 唤醒（got 仍空）。
                if (got) |v| return v;
                // close 唤醒后仍可能有残余缓冲（close 前已入队），循环重检。
                if (self.buffer.items.len == 0 and self.send_waiters.items.len == 0 and self.closed) {
                    return error.ChannelClosed;
                }
            }
        }

        pub fn tryRecv(self: *Self) ?T {
            if (self.buffer.items.len > 0) {
                const value = self.buffer.orderedRemove(0);
                self.pumpSendWaiters();
                return value;
            }
            if (self.send_waiters.items.len > 0) {
                const w = self.send_waiters.orderedRemove(0);
                wakeCoroutine(w.coro);
                return w.value;
            }
            return null;
        }

        /// 非消费就绪查询（select 就绪集收集用；N:1 单线程，查询与随后消费间无竞态）。
        /// recv 就绪 ⟺ 有货可取（缓冲非空/发送等待者对接）或已关闭
        /// （Go 对齐：closed channel 的 recv 立即就绪，取残余后得零值——本实现 tryRecv 返 null 即 ok=false 口径）。
        pub fn canRecv(self: *Self) bool {
            return self.buffer.items.len > 0 or self.send_waiters.items.len > 0 or self.closed;
        }

        /// send 就绪 ⟺ 有接收等待者对接或缓冲未满；**已关闭也视为就绪**（D-2 裁决，2026-11-09）——
        /// select 选中 send-on-closed 后由 trySend 抛可捕获 Error（对齐 Go 的 panic），
        /// 杜绝 timeout=null 时「closed send case 永不就绪 ⇒ 忙等挂死」。
        pub fn canSend(self: *Self) bool {
            if (self.closed) return true;
            return self.recv_waiters.items.len > 0 or self.buffer.items.len < self.capacity;
        }

        pub fn close(self: *Self) void {
            if (self.closed) return;
            self.closed = true;
            // 唤醒全部接收等待者：缓冲有残余则其重检后取残余，否则得 ChannelClosed（→ null）。
            while (self.recv_waiters.items.len > 0) {
                const w = self.recv_waiters.orderedRemove(0);
                wakeCoroutine(w.coro);
            }
            // 唤醒全部发送等待者：其 send 以 error.ChannelClosed 失败（Go 的 panic 对应可捕获 Error）。
            while (self.send_waiters.items.len > 0) {
                const w = self.send_waiters.orderedRemove(0);
                wakeCoroutine(w.coro);
            }
        }

        pub fn isClosed(self: *Self) bool {
            return self.closed;
        }

        pub fn len(self: *Self) usize {
            return self.buffer.items.len;
        }

        pub fn getCapacity(self: *Self) usize {
            return self.capacity;
        }

        /// 缓冲腾出位置后，把等待发送者的值泵入缓冲（保持 FIFO 交接序）。
        fn pumpSendWaiters(self: *Self) void {
            while (self.buffer.items.len < self.capacity and self.send_waiters.items.len > 0) {
                const w = self.send_waiters.orderedRemove(0);
                self.buffer.append(self.allocator, w.value) catch {
                    // OOM：值塞不回去时把发送者唤醒，其 send 在唤醒后重检 closed 失败路径。
                    // 注意：该路径只在分配失败时到达；保持诚实，不静默成功。
                    wakeCoroutine(w.coro);
                    return;
                };
                wakeCoroutine(w.coro);
            }
        }
    };
}

/// Channel 阻塞路径需要调度器；channel 面传入的 allocator 与调度器一致（模板全程用 runtime_allocator）。
fn getSchedulerFromChannel(allocator: Allocator) !*Scheduler {
    const sched = try getScheduler(allocator);
    try sched.ensureStarted();
    return sched;
}

// ============================================================================
// 调度器（N:1 协作式；让出点：channel send满/recv空、go_join、go_wait_all、sleep/usleep、select）
// ============================================================================

const TimerEntry = struct {
    deadline_ns: i128,
    coro: *Coroutine,
};

/// ★M2-2 NetPoller 等待者：协程阻塞在 fd 就绪上（模板流族 read/write 的让出点）。
/// 所有权纪律：waiter 驻留在**阻塞协程栈帧**上；调度器 poll 后就绪摘下并置 linked=false，
/// 协程恢复后据 linked 判定是否需自行摘除（防悬挂指针驻留等待表）。
const IoWaiter = struct {
    coro: *Coroutine,
    fd: std.posix.fd_t,
    events: i16,
    /// 读超时截止（M2-2-b：stream_set_timeout 建模；null＝无限等）。与定时器共用 poll 超时。
    deadline_ns: ?i128 = null,
    /// 截止已到（调度器置位；协程侧据此返回 false）。
    timed_out: bool = false,
    linked: bool = true,
};

const WaitAllWaiter = struct {
    coro: *Coroutine,
    deadline_ns: ?i128,
    timed_out: bool,
};

pub const Scheduler = if (enabled) RealScheduler else StubScheduler;

const RealScheduler = struct {
    allocator: Allocator,
    /// ready FIFO：ArrayList + 头游标（读端 O(1) 弹出，游标过半且超阈时压实）。
    ready: std.ArrayListUnmanaged(*Coroutine) = .empty,
    ready_head: usize = 0,
    by_id: std.AutoHashMapUnmanaged(u64, *Coroutine) = .empty,
    all: std.ArrayListUnmanaged(*Coroutine) = .empty,
    free_list: ?*Coroutine = null,
    next_id: u64 = 1,
    current: ?*Coroutine = null,
    main_coro: ?*Coroutine = null,
    dispatcher_ctx: MachineContext = undefined,
    dispatcher_stack: ?StackAlloc = null,
    dispatcher_started: bool = false,
    pending_fresh: ?*Coroutine = null,
    timers: std.ArrayListUnmanaged(TimerEntry) = .empty,
    /// ★M2-2：NetPoller 等待表与 poll(2) 入参缓冲（容量随等待者增长复用）。
    io_waiters: std.ArrayListUnmanaged(*IoWaiter) = .empty,
    io_pollfds: std.ArrayListUnmanaged(std.posix.pollfd) = .empty,
    blocked_count: usize = 0,
    worker_alive: usize = 0,
    wait_all_waiters: std.ArrayListUnmanaged(*WaitAllWaiter) = .empty,
    running: bool = true,

    pub fn init(allocator: Allocator) !*Scheduler {
        const sched = try allocator.create(Scheduler);
        sched.* = .{
            .allocator = allocator,
        };
        return sched;
    }

    pub fn deinit(self: *Scheduler) void {
        self.running = false;
        for (self.all.items) |coro| {
            if (state_hooks) |h| h.deinit(&coro.state_buf);
            coro.join_waiters.deinit(self.allocator);
            if (coro.stack) |*st| st.deinit();
            coro.deinit();
        }
        self.all.deinit(self.allocator);
        self.by_id.deinit(self.allocator);
        self.timers.deinit(self.allocator);
        self.io_waiters.deinit(self.allocator);
        self.io_pollfds.deinit(self.allocator);
        self.wait_all_waiters.deinit(self.allocator);
        self.ready.deinit(self.allocator);
        if (self.dispatcher_stack) |*st| st.deinit();
        self.allocator.destroy(self);
    }

    // ---- ready FIFO 读写 ----

    fn readyPush(self: *Scheduler, coro: *Coroutine) !void {
        try self.ready.append(self.allocator, coro);
    }

    fn readyPop(self: *Scheduler) ?*Coroutine {
        if (self.ready_head >= self.ready.items.len) return null;
        const coro = self.ready.items[self.ready_head];
        self.ready_head += 1;
        // 游标压实：防 ArrayList 无界前移导致内存膨胀（阈值 64 槽，半数利用）。
        if (self.ready_head >= 64 and self.ready_head * 2 >= self.ready.items.len) {
            const remaining = self.ready.items.len - self.ready_head;
            std.mem.copyForwards(*Coroutine, self.ready.items[0..remaining], self.ready.items[self.ready_head..]);
            self.ready.items.len = remaining;
            self.ready_head = 0;
        }
        return coro;
    }

    /// 懒初始化：注册 main 协程（#0）并建立调度器上下文栈。首个 go/阻塞点到来时调用。
    pub fn ensureStarted(self: *Scheduler) !void {
        if (self.main_coro == null) {
            const main_coro = try Coroutine.init(self.allocator, 0, undefinedMainEntry, null);
            main_coro.is_main = true;
            main_coro.started = true;
            main_coro.state = .running;
            self.main_coro = main_coro;
            try self.all.append(self.allocator, main_coro);
            installGuardPageHandler();
        }
        if (!self.dispatcher_started) {
            self.dispatcher_stack = try StackAlloc.alloc(STACK_SIZE);
            initFreshMachineCtx(&self.dispatcher_ctx, self.dispatcher_stack.?, dispatcherEntry);
            self.dispatcher_started = true;
        }
    }

    fn undefinedMainEntry(_: ?*anyopaque) anyerror!void {
        unreachable; // main 协程从不经入口跳板启动
    }

    pub fn start(self: *Scheduler, num_workers: usize) !void {
        // N:1 单线程模型（设计 D3：M1 不建线程池），num_workers 恒忽略；做真实懒初始化。
        _ = num_workers;
        try self.ensureStarted();
    }

    fn currentCoroutine(self: *Scheduler) *Coroutine {
        if (self.current) |c| return c;
        return self.main_coro.?;
    }

    /// go() 内核：建立协程体（优先复用已结束协程的栈与结构），挂入 ready FIFO。协作式：不抢占当前协程。
    pub fn spawn(self: *Scheduler, func: *const fn (?*anyopaque) anyerror!void, ctx: ?*anyopaque) !u64 {
        try self.ensureStarted();
        const id = self.next_id;
        self.next_id += 1;

        var coro: *Coroutine = undefined;
        if (self.free_list) |reuse| {
            self.free_list = reuse.next_free;
            coro = reuse;
            coro.id = id;
            coro.func_ptr = func;
            coro.context = ctx;
            coro.result = null;
            coro.err = null;
            coro.state = .ready;
            coro.started = false;
            coro.timer_fired = false;
            std.debug.assert(coro.join_waiters.items.len == 0);
        } else {
            coro = try Coroutine.init(self.allocator, id, func, ctx);
            coro.stack = try StackAlloc.alloc(STACK_SIZE);
            try self.all.append(self.allocator, coro);
        }
        initFreshMachineCtx(&coro.ctx, coro.stack.?, coroutineEntry);
        if (state_hooks) |h| h.init(&coro.state_buf);
        coro.exec_ctx = .{};

        try self.by_id.put(self.allocator, id, coro);
        try self.readyPush(coro);
        self.worker_alive += 1;
        return id;
    }

    /// go_join：阻塞当前协程直到目标协程结束；目标未知/已结束 ⇒ 立即返回。
    pub fn join(self: *Scheduler, id: u64) anyerror!void {
        try self.ensureStarted();
        const target = self.by_id.get(id) orelse return;
        if (target.state == .finished) return;
        const me = self.currentCoroutine();
        if (me == target) return; // 自 join：Go 无此面，按立即返回处理（防自死锁）
        try target.join_waiters.append(self.allocator, me);
        self.blockCurrent();
    }

    /// go_wait_all 内核：阻塞直到「除自身外」的 worker 协程全部结束。返回是否全部等到（超时为 false）。
    pub fn waitAll(self: *Scheduler, timeout_ms: ?u64) bool {
        self.ensureStarted() catch return false;
        const me = self.currentCoroutine();
        const self_count: usize = if (me.is_main) 0 else 1;
        if (self.worker_alive - self_count == 0) return true;

        const deadline: ?i128 = if (timeout_ms) |ms| nanoNow() + @as(i128, ms) * std.time.ns_per_ms else null;
        var waiter: WaitAllWaiter = .{ .coro = me, .deadline_ns = deadline, .timed_out = false };
        self.wait_all_waiters.append(self.allocator, &waiter) catch return false;
        defer _ = self.removeWaitAllWaiter(&waiter);

        while (self.worker_alive - self_count > 0) {
            if (deadline) |dl| {
                const now = nanoNow();
                if (now >= dl) return false;
                self.armTimer(dl, me) catch return false;
            }
            self.blockCurrent();
            if (waiter.timed_out and self.worker_alive - self_count > 0) return false;
        }
        return true;
    }

    fn removeWaitAllWaiter(self: *Scheduler, waiter: *WaitAllWaiter) bool {
        for (self.wait_all_waiters.items, 0..) |w, i| {
            if (w == waiter) {
                _ = self.wait_all_waiters.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// 兼容面：drain = waitAll。
    pub fn drain(self: *Scheduler, timeout_ms: ?u64) bool {
        return self.waitAll(timeout_ms);
    }

    // ---- 阻塞/唤醒原语 ----

    /// 当前协程让出：保存全局态快照，切回调度器上下文；被唤醒返回时全局态已由调度器恢复。
    pub fn blockCurrent(self: *Scheduler) void {
        const me = self.currentCoroutine();
        me.state = .blocked;
        self.blocked_count += 1;
        self.parkToDispatcher(me);
    }

    /// 协作让出（Zig\Select 等多路等待的让出点）：不阻塞，排到 ready 队尾。
    pub fn yieldCurrent(self: *Scheduler) void {
        self.ensureStarted() catch return;
        const me = self.currentCoroutine();
        me.state = .ready;
        self.readyPush(me) catch return;
        self.parkToDispatcher(me);
    }

    fn parkToDispatcher(self: *Scheduler, me: *Coroutine) void {
        if (state_hooks) |h| h.save(&me.state_buf);
        me.exec_ctx = execution_context;
        machineCtxSwitch(&me.ctx, &self.dispatcher_ctx);
    }

    fn resumeCoroutine(self: *Scheduler, coro: *Coroutine) void {
        coro.state = .running;
        if (!coro.started) {
            coro.started = true;
            self.pending_fresh = coro;
        }
        if (state_hooks) |h| h.restore(&coro.state_buf);
        execution_context = coro.exec_ctx;
        self.current = coro;
        machineCtxSwitch(&self.dispatcher_ctx, &coro.ctx);
        self.current = null;
    }

    fn wakeFromDispatch(self: *Scheduler, coro: *Coroutine) void {
        std.debug.assert(coro.state == .blocked);
        coro.state = .ready;
        self.blocked_count -= 1;
        self.cancelTimersFor(coro);
        self.readyPush(coro) catch unreachable;
    }

    // ---- 定时器（sleep/usleep 让出与 waitAll 超时） ----

    fn armTimer(self: *Scheduler, deadline_ns: i128, coro: *Coroutine) !void {
        // 保持末尾为最早截止（栈式弹出）。
        var idx: usize = self.timers.items.len;
        while (idx > 0 and self.timers.items[idx - 1].deadline_ns < deadline_ns) : (idx -= 1) {}
        try self.timers.insert(self.allocator, idx, .{ .deadline_ns = deadline_ns, .coro = coro });
    }

    fn cancelTimersFor(self: *Scheduler, coro: *Coroutine) void {
        var i: usize = 0;
        while (i < self.timers.items.len) {
            if (self.timers.items[i].coro == coro) {
                _ = self.timers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn fireDueTimers(self: *Scheduler, now: i128) void {
        while (self.timers.items.len > 0) {
            const back = self.timers.items.len - 1;
            const entry = self.timers.items[back];
            if (entry.deadline_ns > now) break;
            _ = self.timers.pop();
            // 标记 waitAll 等待者超时（若其在该定时器下等待）。
            for (self.wait_all_waiters.items) |w| {
                if (w.coro == entry.coro) {
                    if (w.deadline_ns) |dl| {
                        if (now >= dl) w.timed_out = true;
                    }
                }
            }
            if (entry.coro.state == .blocked) {
                self.wakeFromDispatch(entry.coro);
            }
        }
    }

    // ---- NetPoller（M2-2：poll(2) 便携实现——darwin/linux 同一路径，无 kqueue/epoll 分叉） ----

    fn removeIoWaiter(self: *Scheduler, waiter: *IoWaiter) void {
        for (self.io_waiters.items, 0..) |w, i| {
            if (w == waiter) {
                _ = self.io_waiters.swapRemove(i);
                return;
            }
        }
    }

    /// poll 超时（ms）：取「最近定时器截止」与「最近 IO 读超时截止」的较小者；
    /// 两者皆无 ⇒ -1（无限等，Go 的阻塞 IO 语义）。
    fn pollTimeoutMs(self: *Scheduler) i32 {
        var deadline: ?i128 = null;
        if (self.timers.items.len > 0) deadline = self.timers.items[self.timers.items.len - 1].deadline_ns;
        for (self.io_waiters.items) |w| {
            const dl = w.deadline_ns orelse continue;
            if (deadline == null or dl < deadline.?) deadline = dl;
        }
        const dl = deadline orelse return -1;
        const now = nanoNow();
        const delta = dl - now;
        if (delta <= 0) return 0;
        const ms = @divTrunc(delta + std.time.ns_per_ms - 1, std.time.ns_per_ms);
        return @intCast(@min(ms, std.math.maxInt(i32)));
    }

    /// 空转等待：有 IO 等待者 ⇒ poll（定时器截止作超时）；否则按既有路径睡到定时器到期。
    fn waitForEvents(self: *Scheduler) void {
        if (self.io_waiters.items.len == 0) {
            if (self.timers.items.len > 0) {
                const deadline = self.timers.items[self.timers.items.len - 1].deadline_ns;
                const now = nanoNow();
                if (deadline > now) {
                    const delta = deadline - now;
                    sleepRaw(if (delta > std.math.maxInt(u64)) std.math.maxInt(u64) else @intCast(delta));
                }
            }
            return;
        }
        const timeout_ms = self.pollTimeoutMs();
        self.io_pollfds.clearRetainingCapacity();
        for (self.io_waiters.items) |w| {
            self.io_pollfds.append(self.allocator, .{ .fd = w.fd, .events = w.events, .revents = 0 }) catch {
                // 分配失败：退化为 1ms 睡眠（不挂死、不误报死锁）。
                sleepRaw(std.time.ns_per_ms);
                return;
            };
        }
        _ = std.posix.poll(self.io_pollfds.items, timeout_ms) catch {
            // poll 异常：退化为 1ms 睡眠防忙转；等待者留待下一轮（syscall 终会自报错误）。
            sleepRaw(std.time.ns_per_ms);
            return;
        };
        const now = nanoNow();
        self.fireDueTimers(now);
        self.wakeReadyIoWaiters(now);
    }

    /// poll 返回后按 revents/截止唤醒：HUP/ERR/NVAL 同样唤醒——让后续 read/write 自行返回 0/错误，
    /// 避免「对端已关闭却永久挂起」的假死（与 Go netpoller 的 HUP 即就绪口径一致）。
    /// 读超时截止已到且未就绪 ⇒ 置 timed_out 唤醒（M2-2-b）。
    fn wakeReadyIoWaiters(self: *Scheduler, now: i128) void {
        var any_ready = false;
        for (self.io_waiters.items, 0..) |w, i| {
            if (self.io_pollfds.items[i].revents != 0) {
                w.linked = false;
                any_ready = true;
            } else if (w.deadline_ns) |dl| {
                if (now >= dl) {
                    w.linked = false;
                    w.timed_out = true;
                    any_ready = true;
                }
            }
        }
        if (!any_ready) return;
        var keep: usize = 0;
        for (self.io_waiters.items) |w| {
            if (w.linked) {
                self.io_waiters.items[keep] = w;
                keep += 1;
            } else if (w.coro.state == .blocked) {
                self.wakeFromDispatch(w.coro);
            }
        }
        self.io_waiters.items.len = keep;
    }

    // ---- 协程收尾 ----

    fn onCoroutineFinished(self: *Scheduler, coro: *Coroutine) void {
        // 唤醒 join 等待者
        for (coro.join_waiters.items) |w| {
            if (w.state == .blocked) self.wakeFromDispatch(w);
        }
        coro.join_waiters.clearRetainingCapacity();
        if (!coro.is_main) self.worker_alive -= 1;
        // waitAll 等待者：各自「除自身外无存活 worker」即唤醒（main 需归零，worker 等到仅剩自身）。
        for (self.wait_all_waiters.items) |w| {
            const self_count: usize = if (w.coro.is_main) 0 else 1;
            if (self.worker_alive <= self_count and w.coro.state == .blocked) {
                self.wakeFromDispatch(w.coro);
            }
        }
        // 栈与结构入复用自由链（保留 mapping，避免 mmap/mprotect 抖动）
        coro.next_free = self.free_list;
        self.free_list = coro;
    }

    // ---- 调度主循环（运行于调度器私有栈） ----

    fn dispatchLoop(self: *Scheduler) void {
        while (true) {
            self.fireDueTimers(nanoNow());
            if (self.readyPop()) |coro| {
                self.resumeCoroutine(coro);
                if (coro.state == .finished) self.onCoroutineFinished(coro);
                continue;
            }
            // ready 空：有定时器或 IO 等待者 ⇒ 阻塞等待（poll 同时覆盖 fd 就绪与定时器截止；
            // N:1 下整个进程无可跑者，等待窗口不饿死任何人）。
            if (self.timers.items.len > 0 or self.io_waiters.items.len > 0) {
                self.waitForEvents();
                continue;
            }
            if (self.blocked_count > 0) {
                self.deadlockFatal();
            }
            // ready 空、无阻塞、无定时器：唯一可达路径是调度器初始化后尚无任务；
            // 直接返回主协程（其在 parkToDispatcher 中等待，main 永远可被恢复）。
            const main_coro = self.main_coro.?;
            std.debug.assert(main_coro.state == .blocked or main_coro.state == .ready);
            if (main_coro.state == .blocked) self.wakeFromDispatch(main_coro);
        }
    }

    /// 死锁检测（设计稿 §3.2）：ready 空 ∧ blocked 非空 ∧ 无定时器将醒 ⇒ 致命错，文案对齐 Go。
    fn deadlockFatal(self: *Scheduler) noreturn {
        var msg: FixedMsg = .{};
        msg.writeAll("Fatal error: all coroutines are asleep - deadlock!\n");
        msg.writeAll("blocked coroutine(s):");
        for (self.all.items) |coro| {
            if (coro.state == .blocked) {
                msg.printId(coro.id);
            }
        }
        msg.writeAll("\n");
        writeStderr(msg.out());
        std.process.exit(255);
    }
};

// ---- 调度器内核自由函数（ trampoline 与出入口） ----

/// 单调时钟（ns）。定时器截止与死锁判定的唯一时间源（CLOCK.MONOTONIC）。
fn nanoNow() i128 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) unreachable;
    return @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
}

/// 真阻塞睡眠（nanosleep，EINTR 续睡）。仅调度器空转等定时器与非协程回退路径使用。
fn sleepRaw(ns: u64) void {
    var req: std.c.timespec = .{
        .sec = @intCast(ns / std.time.ns_per_s),
        .nsec = @intCast(ns % std.time.ns_per_s),
    };
    while (std.c.nanosleep(&req, &req) != 0) {
        if (std.c._errno().* != @intFromEnum(std.c.E.INTR)) break;
    }
}

/// Channel 面唤醒入口（N:1 单线程，经全局调度器完成 blocked→ready）。
fn wakeCoroutine(coro: *Coroutine) void {
    const sched = global_scheduler.?;
    sched.wakeFromDispatch(coro);
}

extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;

fn writeStderr(bytes: []const u8) void {
    _ = write(2, bytes.ptr, bytes.len);
}



/// 简易定缓冲格式化输出器（无分配，供致命文案逐段拼接）。
const FixedMsg = struct {
    buf: [1024]u8 = undefined,
    len: usize = 0,

    fn writeAll(self: *FixedMsg, s: []const u8) void {
        const n = @min(s.len, self.buf.len - self.len);
        @memcpy(self.buf[self.len..][0..n], s[0..n]);
        self.len += n;
    }

    fn printId(self: *FixedMsg, id: u64) void {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, " #{d}", .{id}) catch return;
        self.writeAll(s);
    }

    fn printCount(self: *FixedMsg, n: usize) void {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch return;
        self.writeAll(s);
    }

    fn out(self: *const FixedMsg) []const u8 {
        return self.buf[0..self.len];
    }
};

/// go_ctx_trampoline：新协程入口跳板。从调度器取回协程体，执行 callable；
/// 返回时置 finished、唤醒 join 等待者、切回调度器——跳板自身永不返回。
fn coroutineEntry() callconv(.c) void {
    const sched = global_scheduler.?;
    const coro = sched.pending_fresh orelse unreachable;
    sched.pending_fresh = null;
    coro.func_ptr(coro.context) catch |err| {
        reportCoroutineError(coro.id, err);
    };
    // 全局态快照回收：save 捕获活态后 deinit（释放快照持有的堆缓冲，防泄漏）。
    if (state_hooks) |h| {
        h.save(&coro.state_buf);
        h.deinit(&coro.state_buf);
    }
    coro.state = .finished;
    machineCtxSwitch(&coro.ctx, &sched.dispatcher_ctx);
    unreachable; // 跳板永不返回：finished 协程不会再被调度
}

fn dispatcherEntry() callconv(.c) void {
    const sched = global_scheduler.?;
    sched.dispatchLoop();
    unreachable;
}

/// 初始化一个新机器上下文：sp 指向可用栈顶，pc 指向入口跳板。
/// x86_64 额外压一枚 0 伪返回地址槽（SysV 入口 rsp≡8 mod 16 约定）。
fn initFreshMachineCtx(ctx: *MachineContext, stack: StackAlloc, entry: *const fn () callconv(.c) void) void {
    switch (backend_effective) {
        .@"asm" => {
            const c: *Context = ctx;
            switch (native_arch) {
                .aarch64 => {
                    c.* = .{
                        .fp = 0,
                        .sp = stack.usable_top,
                        .pc = @intFromPtr(entry),
                    };
                },
                .x86_64 => {
                    const fake_ret: *u64 = @ptrFromInt(stack.usable_top - 8);
                    fake_ret.* = 0;
                    c.* = .{
                        .rbp = 0,
                        .rsp = stack.usable_top - 8,
                        .rip = @intFromPtr(entry),
                    };
                },
                else => unreachable,
            }
        },
        .ucontext => {
            const uc: *UContext = ctx;
            if (getcontext(uc) != 0) unreachable;
            uc.head.uc_link = null;
            uc.head.ss_sp = @ptrFromInt(stack.usable_base);
            uc.head.ss_size = stack.usable_top - stack.usable_base;
            uc.head.ss_flags = 0;
            makecontext(uc, entry, 0);
        },
    }
}

// ============================================================================
// 协程内未捕获异常（设计 D1=A：整程序致命，含协程 id，rc=255）
// ============================================================================

/// 模板侧注册：协程体内错误逃逸时的报告钩子（负责按 PHP 文案打印并 exit(255)）。
pub const CoroutineErrorHook = *const fn (coro_id: u64, err: anyerror) noreturn;

var coroutine_error_hook: ?CoroutineErrorHook = null;

pub fn registerCoroutineErrorHook(hook: CoroutineErrorHook) void {
    coroutine_error_hook = hook;
}

/// ★M2-1（D1=B 可选面）：协程体错误先经捕获钩子；返回 true ⇒ 已捕获（记录 Throwable，
///   由 go_join_error 收取），协程按 finished 正常收尾；返回 false ⇒ 走致命钩子（D1=A）。
pub const CoroutineErrorCapture = *const fn (coro_id: u64, err: anyerror) bool;

var coroutine_error_capture: ?CoroutineErrorCapture = null;

pub fn registerCoroutineErrorCapture(h: CoroutineErrorCapture) void {
    coroutine_error_capture = h;
}

/// 错误逃逸点：先尝试捕获（D1=B），未捕获再按 D1=A 致命。
/// 注意：本函数**可正常返回**——捕获成功时跳板继续做 finished 收尾。
pub fn reportCoroutineError(coro_id: u64, err: anyerror) void {
    if (coroutine_error_capture) |capture| {
        if (capture(coro_id, err)) return;
    }
    if (coroutine_error_hook) |hook| {
        hook(coro_id, err);
    }
    // 无钩子（纯 Zig 侧使用/单测）：默认整程序致命。
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "Fatal error: uncaught error {s} in coroutine #{d}\n", .{ @errorName(err), coro_id }) catch "Fatal error: uncaught error in coroutine\n";
    writeStderr(msg);
    std.process.exit(255);
}

// ============================================================================
// 栈保护页 SIGSEGV → 可读致命错（设计稿 §3.1/§7）
// ============================================================================

var guard_handler_installed: bool = false;
var alt_stack_mem: [64 * 1024]u8 align(16) = undefined;

fn installGuardPageHandler() void {
    if (guard_handler_installed) return;
    guard_handler_installed = true;
    // 备用信号栈：协程栈溢出时主栈已不可用，处理器须在 sigaltstack 上运行。
    var ss: std.posix.stack_t = .{
        .sp = &alt_stack_mem,
        .size = alt_stack_mem.len,
        .flags = 0,
    };
    std.posix.sigaltstack(&ss, null) catch {};
    var act = std.posix.Sigaction{
        .handler = .{ .sigaction = guardSegvHandler },
        .mask = std.posix.sigemptyset(),
        .flags = std.posix.SA.SIGINFO | std.posix.SA.ONSTACK,
    };
    std.posix.sigaction(std.posix.SIG.SEGV, &act, null);
    // ★AOT-CODEGEN-012 组9 验收：macOS 对 PROT_NONE 保护页的访问经 Mach
    // KERN_PROTECTION_FAILURE 映射为 SIGBUS（而非 SIGSEGV）——只装 SEGV 时栈溢出
    // 退化为无文案的 SIGBUS（实测协程栈 40 层递归即 rc=138）。darwin 族两路同装。
    switch (native_os) {
        .macos, .ios, .tvos, .watchos, .visionos, .maccatalyst, .driverkit => {
            std.posix.sigaction(std.posix.SIG.BUS, &act, null);
        },
        else => {},
    }
}

fn guardSegvHandler(sig: std.posix.SIG, info: *const std.posix.siginfo_t, _: ?*anyopaque) callconv(.c) void {
    const fault_addr: usize = switch (native_os) {
        .linux => @intFromPtr(info.fields.sigfault.addr),
        .macos, .ios, .tvos, .watchos, .visionos, .maccatalyst, .driverkit => @intFromPtr(info.addr),
        else => 0,
    };
    if (global_scheduler) |sched| {
        for (sched.all.items) |coro| {
            if (coro.stack) |st| {
                if (fault_addr >= st.guardStart() and fault_addr < st.guardEnd()) {
                    var buf: [160]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Fatal error: stack overflow in coroutine #{d} (guard page hit)\n", .{coro.id}) catch "Fatal error: coroutine stack overflow\n";
                    writeStderr(msg);
                    std.process.exit(255);
                }
            }
        }
    }
    // 非本运行时保护页：恢复默认处理器并按**收到的信号**重抛，保持原生崩溃语义（不掩盖真实 bug）。
    var dfl = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(sig, &dfl, null);
    std.posix.raise(sig) catch {};
    std.process.exit(134);
}

// ============================================================================
// 全局调度器单例与公共面
// ============================================================================

var global_scheduler: ?*Scheduler = null;
var scheduler_mutex: std.atomic.Mutex = .unlocked;

pub fn getScheduler(allocator: Allocator) !*Scheduler {
    while (!scheduler_mutex.tryLock()) std.atomic.spinLoopHint();
    defer scheduler_mutex.unlock();

    if (global_scheduler == null) {
        global_scheduler = try Scheduler.init(allocator);
    }
    return global_scheduler.?;
}

/// 进程退出收尾（deinitRuntime 调用）：仍有未结束协程 ⇒ 报错并列出协程 id（设计稿 §3.2）。
pub fn shutdownScheduler() void {
    while (!scheduler_mutex.tryLock()) std.atomic.spinLoopHint();
    defer scheduler_mutex.unlock();

    if (global_scheduler) |sched| {
        if (enabled) {
            if (sched.worker_alive > 0) {
                var msg: FixedMsg = .{};
                msg.writeAll("Fatal error: process exiting with ");
                msg.printCount(sched.worker_alive);
                msg.writeAll(" unfinished coroutine(s):");
                for (sched.all.items) |coro| {
                    if (!coro.is_main and coro.state != .finished) {
                        msg.printId(coro.id);
                    }
                }
                msg.writeAll("\n");
                writeStderr(msg.out());
                std.process.exit(255);
            }
        }
        sched.deinit();
        global_scheduler = null;
    }
}

pub fn drainScheduler(timeout_ms: ?u64) bool {
    while (!scheduler_mutex.tryLock()) std.atomic.spinLoopHint();
    const sched = global_scheduler;
    scheduler_mutex.unlock();
    if (sched) |s| {
        return s.drain(timeout_ms);
    }
    return true;
}

/// 当前是否在协程内（非 main）：sleep/usleep 让出分流与 GC 门使用。
pub fn inCoroutine() bool {
    if (enabled) {
        const sched = global_scheduler orelse return false;
        const cur = sched.current orelse return false;
        return !cur.is_main;
    }
    return false;
}

/// sleep/usleep 在协程内的让出睡眠（D5=A；main 内由模板侧走真阻塞）。
pub fn sleepNs(ns: u64) void {
    if (enabled) {
        const sched = global_scheduler orelse {
            sleepRaw(ns);
            return;
        };
        sched.ensureStarted() catch {
            sleepRaw(ns);
            return;
        };
        const me = sched.currentCoroutine();
        const deadline = nanoNow() + @as(i128, ns);
        sched.armTimer(deadline, me) catch {
            sleepRaw(ns);
            return;
        };
        sched.blockCurrent();
        return;
    }
    sleepRaw(ns);
}

/// 多协程活跃判定（D4=A：cycle-GC 在多协程活跃期禁用——worker 未全部结束即禁用窗口）。
pub fn multiActive() bool {
    if (enabled) {
        const sched = global_scheduler orelse return false;
        return sched.worker_alive > 0;
    }
    return false;
}

// ============================================================================
// NetPoller 公共面（M2-2：模板流族 IO 的让出入口）
// ============================================================================

/// poll(2) 事件位（模板侧以 `waitFd(fd, IO_READABLE/IO_WRITABLE)` 使用）。
pub const IO_READABLE: i16 = std.posix.POLL.IN;
pub const IO_WRITABLE: i16 = std.posix.POLL.OUT;

/// 协程体系是否处于「IO 需要让出」的活跃期：
/// 无协程（从未 go）/ 已全部结束 / 调度器收尾 ⇒ false，模板走原真阻塞路径（零额外 syscall）。
pub inline fn ioYieldActive() bool {
    if (enabled) {
        const sched = global_scheduler orelse return false;
        return sched.running and sched.worker_alive > 0;
    }
    return false;
}

/// 等待 fd 就绪（读/写事件）。返回 false ＝读超时截止已到（仅读侧使用；写侧传 null）。
///   - timeout_ms == 0 ⇒ 非阻塞快检（poll(0) 直返，**不进调度器、不置 timed_out**——
///     供 stream_set_blocking(false) 与 stream_set_timeout(0,0) 复用）；
///   - 协程体系活跃 ⇒ 挂 NetPoller 让出，调度器 poll 到就绪/挂断/读超时后唤醒；
///   - 否则 ⇒ 直接 poll 阻塞（等价原真阻塞语义——此时无其他协程可运行）。
/// HUP/ERR 亦按就绪返回，由调用方随后的 read/write 自报 0/错误。
pub fn waitFd(fd: std.posix.fd_t, events: i16, timeout_ms: ?u64) bool {
    if (timeout_ms) |ms| {
        if (ms == 0) {
            var pfd = [1]std.posix.pollfd{.{ .fd = fd, .events = events, .revents = 0 }};
            const n = std.posix.poll(&pfd, 0) catch return true;
            return n > 0;
        }
    }
    if (enabled) {
        if (global_scheduler) |sched| {
            if (sched.running and sched.worker_alive > 0) {
                // 快路径：已就绪 ⇒ 不挂起（省一次调度往返；常见于管道已有数据/有写空间）。
                var pfd = [1]std.posix.pollfd{.{ .fd = fd, .events = events, .revents = 0 }};
                const ready = std.posix.poll(&pfd, 0) catch 1;
                if (ready > 0) return true;
                sched.ensureStarted() catch return pollBlocking(fd, events, timeout_ms);
                const me = sched.currentCoroutine();
                var waiter: IoWaiter = .{
                    .coro = me,
                    .fd = fd,
                    .events = events,
                    .deadline_ns = if (timeout_ms) |ms| nanoNow() + @as(i128, ms) * std.time.ns_per_ms else null,
                };
                sched.io_waiters.append(sched.allocator, &waiter) catch return pollBlocking(fd, events, timeout_ms);
                sched.blockCurrent();
                // 调度器就绪/超时唤醒时已摘下（linked=false）；异常路径兜底摘除。
                if (waiter.linked) sched.removeIoWaiter(&waiter);
                return !waiter.timed_out;
            }
        }
    }
    return pollBlocking(fd, events, timeout_ms);
}

/// 无调度器参与的真阻塞 poll（单 fd；EINTR 由 std.posix.poll 内部续等）。
/// 返回 false ＝超时未就绪（timeout_ms 非 null 时）。
fn pollBlocking(fd: std.posix.fd_t, events: i16, timeout_ms: ?u64) bool {
    var pfd = [1]std.posix.pollfd{.{ .fd = fd, .events = events, .revents = 0 }};
    const timeout: i32 = if (timeout_ms) |ms| @intCast(@min(ms, @as(u64, std.math.maxInt(i32)))) else -1;
    const n = std.posix.poll(&pfd, timeout) catch return true;
    return n > 0;
}

/// Zig\Select 等多路等待的协作让出点。
pub fn yieldNow() void {
    if (enabled) {
        const sched = global_scheduler orelse return;
        sched.yieldCurrent();
    }
}

// ============================================================================
// Select（M2 面；M1 维持既有接线，不在本里程碑启用）
// ============================================================================

pub const SelectOp = enum { send, recv };

pub const SelectCase = struct {
    channel_ptr: usize,
    op: SelectOp,
    value: ?anyopaque,
};

pub fn selectChannels(cases: []const SelectCase, timeout_ms: ?u64) !usize {
    _ = timeout_ms;
    if (cases.len == 0) return error.NoCases;
    return 0;
}

// ============================================================================
// 存根实现（-Dcoroutine=off 回退：保持构建旗关闭时的既有行为，设计稿 §7）
// ============================================================================

const StubScheduler = struct {
    ready_queue: std.ArrayListUnmanaged(*Coroutine) = .empty,
    allocator: Allocator,
    next_id: u64 = 1,
    active_count: u64 = 0,
    running: bool = true,

    pub fn init(allocator: Allocator) !*Scheduler {
        const sched = try allocator.create(Scheduler);
        sched.* = .{ .allocator = allocator };
        return sched;
    }

    pub fn deinit(self: *Scheduler) void {
        self.running = false;
        for (self.ready_queue.items) |coro| coro.deinit();
        self.ready_queue.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn drain(self: *Scheduler, timeout_ms: ?u64) bool {
        _ = timeout_ms;
        return self.ready_queue.items.len == 0 and self.active_count == 0;
    }

    pub fn start(self: *Scheduler, num_workers: usize) !void {
        _ = self;
        _ = num_workers;
    }

    pub fn ensureStarted(self: *Scheduler) !void {
        _ = self;
    }

    pub fn spawn(self: *Scheduler, func: *const fn (?*anyopaque) anyerror!void, ctx: ?*anyopaque) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        const coro = try Coroutine.init(self.allocator, id, func, ctx);
        try self.ready_queue.append(self.allocator, coro);
        return id;
    }

    pub fn join(self: *Scheduler, id: u64) anyerror!void {
        _ = self;
        _ = id;
    }

    pub fn waitAll(self: *Scheduler) bool {
        return self.drain(null);
    }
};

fn StubChannel(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: std.ArrayListUnmanaged(T) = .empty,
        capacity: usize,
        closed: bool = false,
        allocator: Allocator,

        pub fn init(allocator: Allocator, cap: usize) !*Self {
            const ch = try allocator.create(Self);
            ch.* = .{
                .capacity = if (cap == 0) 1 else cap,
                .allocator = allocator,
            };
            return ch;
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
            self.allocator.destroy(self);
        }

        pub fn send(self: *Self, value: T) !void {
            if (self.closed) return error.ChannelClosed;
            try self.buffer.append(self.allocator, value);
        }

        pub fn trySend(self: *Self, value: T) !bool {
            if (self.closed) return error.ChannelClosed;
            if (self.buffer.items.len >= self.capacity) return false;
            try self.buffer.append(self.allocator, value);
            return true;
        }

        pub fn recv(self: *Self) !T {
            if (self.buffer.items.len == 0) return error.ChannelClosed;
            return self.buffer.orderedRemove(0);
        }

        pub fn close(self: *Self) void {
            self.closed = true;
        }

        pub fn tryRecv(self: *Self) ?T {
            if (self.buffer.items.len == 0) return null;
            return self.buffer.orderedRemove(0);
        }

        /// 存根态同名查询（与真 Channel 口径一致，无 waiters 概念）。
        pub fn canRecv(self: *Self) bool {
            return self.buffer.items.len > 0 or self.closed;
        }

        /// 存根态同名查询（与真 Channel 口径一致：closed 视为就绪，由 trySend 报 ChannelClosed）。
        pub fn canSend(self: *Self) bool {
            if (self.closed) return true;
            return self.buffer.items.len < self.capacity;
        }

        pub fn isClosed(self: *Self) bool {
            return self.closed;
        }

        pub fn len(self: *Self) usize {
            return self.buffer.items.len;
        }

        pub fn getCapacity(self: *Self) usize {
            return self.capacity;
        }
    };
}
