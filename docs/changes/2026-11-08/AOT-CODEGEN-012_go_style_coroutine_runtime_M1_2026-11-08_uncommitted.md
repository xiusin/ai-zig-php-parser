# Go 式协程运行时 M1：真调度器内核替换（AOT-CODEGEN-012）

- 日期：2026-11-08
- 状态：uncommitted（本地工作树，提交需另行授权）
- 设计依据：[docs/design/2026-11-08-go-style-coroutine-design.md](../../design/2026-11-08-go-style-coroutine-design.md)（老铁已批准）
- 永久裁决：协程能力由 AOT 运行时自有的 Go 风格协程系统提供（AGENTS.md §七.1/§七.9；工单 §272），不实现 PHP Fiber/生成器语义

## 1. 高层摘要（TL;DR）

把 `src/aot/concurrency_runtime.zig` 的 217 行全存根**整体替换**为 Go 式协程真内核：手写汇编上下文切换（aarch64/x86_64，callee-saved 全集 + fp/sp/pc，全局 `.globl` 符号防 LLVM 内联）+ 每协程 64KB 栈（末尾 mprotect 保护页 + sigaltstack 上的 SIGSEGV 可读致命转换）+ N:1 单线程协作式调度（ready FIFO / blocked 集 / 定时器堆 / 死锁检测）+ Channel 真阻塞语义（cap=0 对接、满 send/空 recv 让出、close 语义）+ `go()/go_join()/go_wait_all()` 换真 + 每协程全局态快照（hooks 注册制，异常旗/@抑制/作用域/src 位置/实参链/q4 FIFO）+ 协程未捕获异常整程序致命（D1=A）+ cycle-GC 多协程活跃期禁用（D4=A）。PHP 面签名零变更；`-Dcoroutine=off` 构建旗保留存根回退（设计 §7）。

六枚断言探针全绿；ucontext 备份后端同绿；`zig build test` 全绿。过程中修复了切换原语的三轮迭代（clobber-list inline 法 → naked fn → 全局汇编），并**顺带定位两枚预存缺陷**（见 §7，均为 AOT 既有问题、非本批引入，已按纪律上报待裁决）。

## 2. 影响范围

| 面 | 影响 | 说明 |
|---|---|---|
| AOT 产物运行时 | **行为变更** | 使用 `go()/Channel` 的脚本：存根（spawn 永不执行、recv 空即错）⇒ 真调度语义。不用协程面的脚本零影响 |
| PHP 调用面 | 零变更 | `go()/go_join()/go_wait_all()/Channel` 签名不动；`sleep()/usleep()` 面不变（协程内自动让出、main 内真阻塞，D5=A） |
| 编译器（codegen） | 极小 | `writeBuiltinArgs` 公共点新增 go 族切片打包；builtin 表补 `go_join/go_wait_all` 两条登记；`native_linker` 产物构建期重写 `coroutine_config.zig` |
| cycle-GC | 行为变更（仅多协程窗口） | D4=A：worker 未全部结束时停用 cycle 收集，归零自动恢复 |
| 构建系统 | 新增两旗 | `-Dcoroutine=on\|off`、`-Dcoroutine_backend=asm\|ucontext` |
| 解释器/字节码/JIT | 零影响 | 全部改动在 AOT 运行时层与 AOT 发射层 |

## 3. 核心变更

| 文件 | 变更 | 描述 |
|---|---|---|
| [src/aot/concurrency_runtime.zig](../../../src/aot/concurrency_runtime.zig) | 重写（217→~1180 行） | 真调度器内核（详见 §5） |
| [src/aot/coroutine_config.zig](../../../src/aot/coroutine_config.zig) | 新增（21 行） | 树内默认配置（enabled=true/backend=asm）；产物构建期由 linker 按旗重写 |
| [build.zig](../../../build.zig) | +17 行 | `-Dcoroutine`（enum on/off）、`-Dcoroutine_backend`（enum asm/ucontext）两旗入 build_options |
| [src/aot/native_linker.zig](../../../src/aot/native_linker.zig) | +~55 行 | `writeCoroutineConfig`（产物构建期写配置）；builtin 表补 `go_join/go_wait_all`；`writeBuiltinArgs`/`isSliceArgsBuiltin`/零参站点 go 族切片打包 |
| [src/aot/runtime_lib_template.zig](../../../src/aot/runtime_lib_template.zig) | +~230 行 | 状态快照 hooks + 协程未捕获钩子（D1=A）+ 注册（initRuntime）；`php_coroutine_entry` 错误/异常旗上抛；channel send 可捕 Error「send on closed channel」；`php_sleep/php_usleep` 协程内让出；`gcMaybeCollect/gcCollectCycles` 多协程门；`Zig\Select` 让出点换 `yieldNow()` |
| co_pingpong.php / co_fanin.php / co_join_order.php / co_deadlock.php / co_uncaught.php / co_isolation.php | 新增探针 ×6 | 设计 §5 M1 验收探针（断言式自验） |

## 4. 可视化概览（Code & Logic Map）

### 4.1 分层架构

```mermaid
flowchart TD
    subgraph PHP面
        A["go(callable, args...)"] --> B["php_go → Scheduler.spawn"]
        C["ch->send/recv"] --> D["Channel(Value) 阻塞语义"]
        E["go_join / go_wait_all"] --> B
        F["sleep/usleep"] --> G["concurrency.sleepNs（协程内）/ libc（main 内）"]
    end
    subgraph 模板集成层["runtime_lib_template.zig"]
        H["状态快照 hooks<br/>异常旗/@抑制/src位置/实参链/q4 FIFO/last_throw"]
        I["phpCoroutineUncaught（D1=A 致命打印）"]
        J["GC 门 gcMaybeCollect/gcCollectCycles"]
    end
    subgraph 调度器["Scheduler（N:1 单 OS 线程）"]
        K["ready FIFO（游标队列）"] --> L["dispatchLoop（私有 64KB 栈）"]
        M["blocked 集（channel/join/timer/waitAll）"] -->|wake| K
        N["timer 堆（deadline 排序）"] -->|fireDue| K
        L -->|死锁检测| O["all coroutines are asleep - deadlock! rc=255"]
    end
    subgraph 切换原语["go_ctx_switch（.globl 全局汇编）"]
        P["Context：callee-saved 全集+fp/sp/pc"]
        Q["协程栈：mmap 64KB + 低址保护页"]
        R["trampoline：入口 → 体 → finished → 切回调度器（永不返回）"]
    end
    L <-->|machineCtxSwitch| P
```

### 4.2 切换时序（spawn → 往返 → 收尾）

```mermaid
sequenceDiagram
    participant M as main(#0)
    participant D as 调度器(私有栈)
    participant W as worker(#1)
    M->>D: go() spawn → ready 入队（协作式不抢占）
    M->>D: recv 空 → blockCurrent（save 快照 → 切 D）
    D->>W: resumeCoroutine（restore 快照 → 切入，pc=trampoline）
    W->>W: 执行协程体（PHP 函数）
    W->>M: send 对接 → 写 slot + wake(main)
    W->>D: send 满/recv 空 → blockCurrent（切 D）
    D->>M: resumeCoroutine（restore → main 从 recv 返回）
    W->>D: 体返回 → trampoline 置 finished → 切 D
    D->>M: onFinished：唤醒 join/waitAll 等待者 → main 就绪
    D->>M: resume → main 继续
```

### 4.3 Channel 阻塞语义状态机

```mermaid
stateDiagram-v2
    [*] --> Open
    Open --> SendHandoff: recv_waiters 非空 ⇒ 直写 slot+wake
    Open --> BufferAppend: buf.len<cap
    Open --> ParkSender: 满/无对接 ⇒ send_waiters 挂起
    ParkSender --> Pumped: recv 弹出后泵入 buf/wake
    ParkSender --> ClosedFail: close ⇒ error.ChannelClosed
    Open --> ParkReceiver: 空开 ⇒ recv_waiters 挂起（slot 驻帧）
    ParkReceiver --> Handed: send 交接 ⇒ got=value
    ParkReceiver --> DrainedNull: close 且无残余 ⇒ error.ChannelClosed→null
    Open --> Closed: close()
    Closed --> DrainedNull: 取尽后 recv ⇒ null
    Closed --> ClosedFail: send ⇒ 可捕获 Error「send on closed channel」
```

## 5. 详细变更分析

### 5.1 切换原语（三轮迭代定稿）

| 轮 | 方案 | 结果 | 失败根因 |
|---|---|---|---|
| ① | std.Io.Fiber 式 clobber-list inline asm（sp/fp/pc） | Debug 绿 / Release 崩 | clobber 仅在**内联进调用方**时驱动编译器溢出 callee-saved；独立函数调用 ⇒ 被切出协程的 x19-x28 被对端污染（Release 下调度器指针损毁，SIGBUS 写 text 段） |
| ② | Zig naked fn + `.c` 函数指针调用 | Release 仍崩 | LLVM 将 naked 体**内联克隆**到调用点并按自身寄存器分配传参，与裸体硬编码的 x0/x1 错位 |
| ③ | **全局汇编 `.globl` 符号**（libco/Boost.Context 同宗） | 全优化档绿 | LLVM 看不到函数体，无法内联/去虚拟化；ABI 调用边界下 caller-saved 由编译器保全、callee-saved 由汇编逐个存入 Context |

定稿（③）要点：
- aarch64：x19-x28 + d8-d15 + fp/sp/pc；pc 槽存 `lr`（本调用点返回地址），恢复以 `br` 跳达——执行流在调用方自然继续；x86_64：rbx/rbp/r12-r15/rsp/rip，pc 槽存栈顶返回地址。
- 入口跳板 `coroutineEntry`（普通 C ABI fn）：取 `pending_fresh` → 执行体 → 异常/错误上抛 `reportCoroutineError` → 快照回收（save+deinit）→ 置 finished → 切回调度器（永不返回）。
- 平台矩阵：aarch64-macos/linux、x86_64-linux 走 asm；其余（含 x86_64-macos）comptime 落 ucontext 备份后端（已验证同绿）。

### 5.2 栈与保护页

- 每协程 `mmap` 64KB + 低址 1 页 `mprotect(PROT_NONE)`；初始 sp=页对齐栈顶（x86_64 压 0 伪返回地址槽满足 SysV 入口对齐）。
- `sigaltstack`（静态 64KB）+ `SA_ONSTACK|SA_SIGINFO` 的 SIGSEGV 处理器：命中任一活协程保护页 ⇒ `Fatal error: stack overflow in coroutine #N` + exit 255；非本运行时段落 ⇒ 恢复 DFL 重抛（不掩盖真实 bug）。
- 已完成协程的栈与控制块入自由链复用（避免 mmap/mprotect 抖动）。

### 5.3 调度器（N:1 协作式）

- main 注册为 #0（首个 go/阻塞点懒注册）；调度器运行于私有栈，首个 park 时启动。
- 让出点：channel send（满）/recv（空）、go_join、go_wait_all、sleep/usleep（协程内自动分流）、`Zig\Select`（`yieldNow`）。
- 死锁检测：ready 空 ∧ blocked 非空 ∧ 无 timer 将醒 ⇒ `Fatal error: all coroutines are asleep - deadlock!`（Go 文案对齐）+ 列 blocked id + exit 255。
- 进程退出时未结束协程 ⇒ `Fatal error: process exiting with N unfinished coroutine(s): #ids` + exit 255（设计 §3.2，对 Go 隐杀语义的可读化升级）。
- 定时器：deadline 排序数组；`waitAll(?timeout)` 真超时语义（计时到点返回 false）。

### 5.4 Channel（Go 对齐）

- cap=0 无缓冲：send 必等 recv 对接（slot 直写阻塞帧）；cap>0：满则挂 `send_waiters`，recv 弹出后按 FIFO 泵入。
- close：唤醒全部 recv 等待者（取尽残余后返 null）与全部 send 等待者（其 send 以可捕获 Error「send on closed channel」失败——模板侧 throwThrowable，值引用按错误路径释放，无泄漏）。
- `getCapacity()` 修正存根期 cap=0→1 的谎报（现如实返 0，语义修正）。

### 5.5 每协程全局态快照（hooks 注册制）

- 注册制解耦：concurrency_runtime 不反向依赖模板；模板在 initRuntime 注册 init/save/restore/deinit 四钩子（容量校验 `@sizeOf ≤ 4096`）。
- 覆盖：has_exception/current_exception、@ 抑制深度与保存栈、ExecutionContext（called/scope class，concurrency 内部随动）、src_file/src_line、current_call_args 与 call_args_owned_stack（**所有权随快照搬迁**，restore 清快照侧标记防双重释放）、q4 未定义 FIFO、last_throw 帧（含静态缓冲内容）。
- 全局共享（不随快照）：堆与 RC、类表、分配器、对象 id 计数器（设计 §3.4 表）。

### 5.6 异常与 GC

- 协程内未捕获异常（D1=A）：整程序致命，文案 `uncaught {Class}: {msg} in coroutine #{id}` + 协程内栈帧（§七.5 行号豁免）+ shutdown functions + exit 255。throw 走「返值+旗」通道的由 `php_coroutine_entry` 尾检 `has_exception` 补抛特征错误。
- go_join **不**传播对端异常（与 Go 一致；M2 增设 go_join_error 可选面）。
- D4=A：cycle-GC 在 worker 未全部结束时停用（自动与显式两路），归零自动恢复。

### 5.7 构建旗与回退

- `-Dcoroutine=off`：产物回到存根语义（已验证：无阻塞、无死锁检测，行为与 M1 前一致）。
- `-Dcoroutine_backend=ucontext`：备份后端（makecontext/swapcontext，已验证六探针等价绿）。
- `coroutine_config.zig` 树内默认 on/asm；产物构建期由 `native_linker.writeCoroutineConfig` 按旗实体重写（不符号链接，防旗语漂移）。

## 6. 影响与风险评估

- 是否破坏式变更：**否**（PHP 面签名零变更；不用协程面的脚本行为零变化——720 语料零 go( 使用实证）。
- 需要特别注意的点：
  - 切换原语与优化档强相关：四档（Debug/ReleaseSmall/ReleaseFast/ReleaseSafe）全量验证是硬门槛，后续每次动切换汇编必须复跑。
  - 公平性：M1 为 FIFO 协作式，CPU 密集协程会饿死他者（设计 §3.2 已标注，M3 定时抢占治理）。
  - fiber 化 IO 未做：channel/timer 之外一律真阻塞（设计 §3.4 标注，M2 NetPoller）。
  - `by_id` 表随 spawn 单调增长（已结束 id 保留供 join 判完成；M2 评估回收窗口）。
- 复测路径：
  1. `zig build && zig build test`
  2. 六探针：`--compile co_*.php --output=aot_compile_co_*` 运行断言（deadlock/uncaught 验 rc=255 与文案）
  3. `-Dcoroutine=off` 变体编译运行 co_pingpong/co_deadlock 回存根语义
  4. 720 语料与探针面板全量回归（结果见 §9 追记）

## 7. 遗留问题（非本批引入，已按纪律上报待裁决）

| # | 缺陷 | 证据 | 定性 | 处置建议 |
|---|---|---|---|---|
| F-1 | 裸 `go(...)` 语句在 PHP 模式命中 Go 语法 go_stmt 解析：多实参被 comma-expression 折叠（`go('f',$a)` ⇒ callable=$a，静默丢参且不报错） | co_simple 复现；生成码 `php_go_builtin(&[_]Value{reg_ch})` | parser 层预存冲突（k_go 无条件关键字；赋值形 `$id = go(...)` 不受影响） | parseGo 前瞻 `l_paren` ⇒ 回落函数调用解析；或 go_stmt 限定 Go 语法模式。**待老铁裁决** |
| F-2 | `A && $obj->method()` 短路 + break 在 while 循环内 break 条件反转 | co_and_loop.php 复现（无协程参与）：`$v===null && $ch->isClosed()` 首轮即 break | ir_generator 标签驱动块合并族预存缺陷（与 f067/逻辑合并同族） | 按生成码指纹反推定位发射站点专项修复。**待老铁裁决** |
| L-1 | 多协程窗口 cycle-GC 停用期，长活多协程程序的循环垃圾只攒不收 | 设计 D4=A 原文 | 决策内取舍 | M3 root 集扩到各协程栈（D4=B 路线） |
| L-2 | x86_64-linux asm 路径未实机验证（开发机 aarch64-macos） | 平台矩阵设计 | 环境限制 | 建议 CI 增加 x86_64-linux 交叉验证探针 |

## 8. 后续开发/优化建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|---|---|---|---|
| P0 | 正确性 | 中 | 裁决并修复 F-1/F-2 两枚预存缺陷——它们会让「写法稍有不特」的协程脚本静默错行，且与协程无关、影响全体 AOT 用户 |
| P1 | 功能 | 中 | M2：timer 堆已就位，`go_select(array $cases, ?float $timeout)` 多路就绪 + `go_join_error($id)` 异常收取面；`select_` 算子启用在即 |
| P1 | 可靠性 | 低 | x86_64-linux asm 实机交叉验证（L-2） |
| P2 | 性能 | 低 | 栈复用自由链已有；可评估 Channel 唤醒批量化（一次 close 唤醒 N 等待者的链表重排成本） |
| P2 | 可维护 | 低 | by_id 回收窗口（完成 id 的惰性清理，防长跑进程表单调增长） |

## 9. 回归追记（完成后回填）

- 六探针：6/6 PASS（pingpong/fanin/join_order/deadlock/uncaught/isolation；deadlock rc=255 文案对齐 Go，uncaught rc=255 含协程 id）
- ucontext 备份后端：等价绿
- `-Dcoroutine=off`：存根语义回退验证通过
- `zig build test`：全绿
- 720 语料（pass/ 68 枚全量）：**67 Pass / 0 Compile Fail / 0 Runtime Fail / 0 Diff / 1 Skip**——唯一 Skip 为 f004_oop_deep_inheritance_magic.php（PHP 解释器侧 exit=255 的预存排除项，与基线逐字节一致）；`regression_failures.tsv` 与基线语义零漂移（脚本现版仅落 SKIP/FAIL 条目，基线含全量 PASS 行属旧版格式差异，非行为差异）。报告：[regression_report.md](../../../fuzzy_scripts_720/regression_report.md)（2026-11-08 22:43:32）
- 探针面板（31 枚 AOT 断言探针）：**54 SAME / 0 DIFF / 0 COMPILE_FAIL**，零漂移
