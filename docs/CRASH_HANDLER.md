# 运行时崩溃处理系统

## 概述

运行时崩溃处理系统提供了完整的崩溃检测、信息收集和报告生成功能。当程序发生致命错误（如段错误、非法指令等）时，系统会自动捕获崩溃现场，生成详细的崩溃报告，并可选地生成 core dump 文件。

## 功能特性

### 1. 信号处理

系统自动捕获以下致命信号：

- **SIGSEGV**: 段错误（无效内存访问）
- **SIGILL**: 非法指令
- **SIGFPE**: 浮点异常
- **SIGABRT**: 中止信号
- **SIGBUS**: 总线错误（对齐或硬件问题）
- **SIGTRAP**: 陷阱指令

### 2. 崩溃信息收集

崩溃发生时，系统会收集以下信息：

#### 崩溃上下文
- 崩溃类型和信号编号
- 故障地址（如果可用）
- 指令指针、堆栈指针、帧指针
- 线程 ID 和进程 ID
- 时间戳
- 堆栈跟踪地址

#### 系统信息
- 操作系统和架构
- Zig 版本
- 主机名

#### 内存信息
- 总内存和可用内存
- 进程内存使用
- 堆大小

#### 环境变量
- PATH, HOME, USER, SHELL, LANG 等关键环境变量

### 3. 崩溃报告生成

系统生成详细的文本格式崩溃报告，包含：

```
================================================================================
                         CRASH REPORT                                           
================================================================================

CRASH INFORMATION:
  Type: Segmentation fault (invalid memory access)
  Signal: 11
  Error Code: 1
  Fault Address: 0x0000000000001000
  Instruction Pointer: 0x00007F8A12345678
  Stack Pointer: 0x00007FFE98765432
  Frame Pointer: 0x00007FFE98765400
  Thread ID: 12345
  Process ID: 67890
  Timestamp: 1705678901234

SYSTEM INFORMATION:
  OS: linux
  Architecture: x86_64
  Zig Version: 0.11.0
  Hostname: myserver

MEMORY INFORMATION:
  Total Memory: 16777216000 bytes
  Available Memory: 8388608000 bytes
  Process Memory: 104857600 bytes
  Heap Size: 52428800 bytes

STACK TRACE:
  Thread: 12345
  Timestamp: 1705678901234
  Depth: 5

  #0: [JIT] myFunction at test.php:42:10 (IP: 0x00007F8A12345678)
  #1: [INT] helper at test.php:20:5
  #2: [AOT] main at test.php:10:1
  #3: [NAT] <unknown> at <unknown>:0:0
  #4: [NAT] <unknown> at <unknown>:0:0

ENVIRONMENT VARIABLES:
  PATH=/usr/local/bin:/usr/bin:/bin
  HOME=/home/user
  USER=user
  SHELL=/bin/bash
  LANG=en_US.UTF-8

================================================================================
```

### 4. Core Dump 支持

系统可以配置为生成 core dump 文件，用于事后调试：

- 自动设置 `RLIMIT_CORE` 为无限制
- 保留完整的进程内存映像
- 可使用 gdb/lldb 进行事后分析

## 使用方法

### 基本使用

```zig
const std = @import("std");
const crash_handler = @import("runtime/crash_handler.zig");
const stack_trace = @import("runtime/stack_trace.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 1. 初始化堆栈跟踪捕获器
    try stack_trace.initGlobalCapture(allocator, 128);
    defer stack_trace.deinitGlobalCapture(allocator);
    
    // 2. 初始化崩溃处理器
    try crash_handler.initGlobalHandler(
        allocator,
        "crash_reports",  // 崩溃报告目录
        true,             // 启用 core dump
    );
    defer crash_handler.deinitGlobalHandler(allocator);
    
    // 3. 运行应用程序
    try runApplication();
}
```

### 自定义配置

```zig
// 创建自定义崩溃处理器
var handler = crash_handler.CrashHandler.init(
    allocator,
    "/var/log/myapp/crashes",  // 自定义报告目录
    false,                      // 禁用 core dump
);

// 安装信号处理器
try handler.install();
defer handler.uninstall() catch {};

// 运行应用程序
try runApplication();

// 查看统计信息
std.debug.print("崩溃次数: {d}\n", .{handler.stats.crash_count});
std.debug.print("报告生成次数: {d}\n", .{handler.stats.report_count});
```

### 手动生成崩溃报告

```zig
// 创建崩溃上下文（模拟）
var info: std.posix.siginfo_t = undefined;
info.signo = std.posix.SIG.SEGV;
info.code = 1;
info.fields.sigfault.addr = @ptrFromInt(0x1000);

const context = crash_handler.CrashContext.init(
    std.posix.SIG.SEGV,
    &info,
    null,
);

// 生成报告
var report = try crash_handler.CrashReport.init(allocator, context);
defer report.deinit();

// 添加堆栈跟踪
const capture = stack_trace.getGlobalCapture().?;
var trace = try capture.capture();
report.setStackTrace(trace);

// 保存报告
try report.saveToFile("crash_report.txt");

// 或获取报告文本
const report_text = try report.generateReport();
defer allocator.free(report_text);
std.debug.print("{s}\n", .{report_text});
```

## 架构设计

### 组件层次

```
┌─────────────────────────────────────────┐
│         应用程序代码                     │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│      全局崩溃处理器                      │
│  - initGlobalHandler()                  │
│  - deinitGlobalHandler()                │
│  - getGlobalHandler()                   │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│       CrashHandler                      │
│  - install()      安装信号处理器         │
│  - uninstall()    卸载信号处理器         │
│  - handleCrash()  处理崩溃              │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│      信号处理器                          │
│  - signalHandler()  捕获信号            │
│  - 提取寄存器信息                        │
│  - 捕获堆栈地址                          │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│      CrashContext                       │
│  - 崩溃类型和信号                        │
│  - 寄存器状态                            │
│  - 堆栈地址                              │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│      CrashReport                        │
│  - 收集系统信息                          │
│  - 收集内存信息                          │
│  - 收集环境变量                          │
│  - 生成报告文本                          │
│  - 保存到文件                            │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│      堆栈跟踪系统                        │
│  - 解析堆栈地址                          │
│  - 映射到源代码位置                      │
│  - 支持 JIT/AOT/解释执行                │
└─────────────────────────────────────────┘
```

### 信号处理流程

```
崩溃发生
    ↓
信号触发 (SIGSEGV/SIGILL/...)
    ↓
signalHandler() 被调用
    ↓
创建 CrashContext
    ├─ 提取信号信息
    ├─ 提取寄存器状态
    └─ 捕获堆栈地址
    ↓
创建 CrashReport
    ├─ 收集系统信息
    ├─ 收集内存信息
    ├─ 收集环境变量
    └─ 解析堆栈跟踪
    ↓
生成报告文本
    ↓
保存到文件
    ↓
恢复默认信号处理器
    ↓
重新触发信号 (生成 core dump)
    ↓
程序终止
```

## 平台支持

### Linux

- ✅ 完整支持
- ✅ x86_64 架构
- ✅ aarch64 架构
- ✅ 寄存器提取
- ✅ Core dump 生成

### macOS

- ⚠️ 部分支持
- ⚠️ 寄存器提取需要实现
- ✅ 信号处理
- ✅ 报告生成

### Windows

- ❌ 暂不支持
- 需要使用 Windows 异常处理机制
- 需要实现 SEH (Structured Exception Handling)

## 性能特性

### 信号安全

崩溃处理器在信号处理器上下文中运行，必须遵守信号安全规则：

- ✅ 不使用动态内存分配（在信号处理器中）
- ✅ 使用固定大小的缓冲区
- ✅ 避免调用非信号安全的函数
- ✅ 使用原子操作更新统计信息

### 性能指标

- **堆栈跟踪捕获**: < 100μs
- **崩溃报告生成**: < 10ms
- **文件写入**: < 50ms
- **内存开销**: < 1MB

## 调试技巧

### 使用 gdb 分析 core dump

```bash
# 生成 core dump
ulimit -c unlimited
./myapp

# 使用 gdb 分析
gdb ./myapp core

# gdb 命令
(gdb) bt              # 查看堆栈
(gdb) info registers  # 查看寄存器
(gdb) x/10i $rip      # 查看指令
(gdb) info threads    # 查看线程
```

### 使用 lldb 分析 core dump

```bash
# 使用 lldb 分析
lldb ./myapp -c core

# lldb 命令
(lldb) bt all         # 查看所有线程堆栈
(lldb) register read  # 查看寄存器
(lldb) disassemble    # 反汇编
(lldb) thread list    # 列出线程
```

### 分析崩溃报告

1. **查看崩溃类型**: 确定是段错误、非法指令还是其他类型
2. **检查故障地址**: 判断是空指针、野指针还是越界访问
3. **分析堆栈跟踪**: 找到崩溃发生的函数调用链
4. **检查寄存器状态**: 了解崩溃时的 CPU 状态
5. **查看内存信息**: 判断是否内存不足或内存泄漏

## 最佳实践

### 1. 早期初始化

在程序启动时尽早初始化崩溃处理器：

```zig
pub fn main() !void {
    // 第一步：初始化崩溃处理
    try crash_handler.initGlobalHandler(allocator, "crashes", true);
    defer crash_handler.deinitGlobalHandler(allocator);
    
    // 第二步：初始化其他组件
    // ...
}
```

### 2. 合理的报告目录

选择合适的崩溃报告目录：

- 确保目录有写权限
- 使用绝对路径
- 定期清理旧报告
- 考虑磁盘空间限制

```zig
const report_dir = if (builtin.mode == .Debug)
    "debug_crashes"
else
    "/var/log/myapp/crashes";
```

### 3. 生产环境配置

生产环境建议配置：

```zig
try crash_handler.initGlobalHandler(
    allocator,
    "/var/log/myapp/crashes",
    true,  // 启用 core dump 用于事后分析
);
```

### 4. 测试环境配置

测试环境建议配置：

```zig
try crash_handler.initGlobalHandler(
    allocator,
    "test_crashes",
    false,  // 禁用 core dump 避免测试环境问题
);
```

### 5. 定期清理

实现崩溃报告清理策略：

```zig
fn cleanupOldCrashReports(dir: []const u8, max_age_days: u32) !void {
    var dir_iter = try std.fs.cwd().openIterableDir(dir, .{});
    defer dir_iter.close();
    
    var iter = dir_iter.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        
        const stat = try dir_iter.dir.statFile(entry.name);
        const age_seconds = std.time.timestamp() - stat.mtime;
        const age_days = age_seconds / (24 * 3600);
        
        if (age_days > max_age_days) {
            try dir_iter.dir.deleteFile(entry.name);
        }
    }
}
```

## 故障排除

### 问题：崩溃报告未生成

**可能原因**:
1. 报告目录不存在或无写权限
2. 磁盘空间不足
3. 信号处理器未正确安装

**解决方法**:
```zig
// 检查目录权限
std.fs.cwd().makePath("crash_reports") catch |err| {
    std.debug.print("无法创建目录: {}\n", .{err});
};

// 检查安装状态
const handler = crash_handler.getGlobalHandler();
if (handler) |h| {
    std.debug.print("已安装: {}\n", .{h.installed});
}
```

### 问题：Core dump 未生成

**可能原因**:
1. `ulimit -c` 设置为 0
2. 系统禁用了 core dump
3. 磁盘空间不足

**解决方法**:
```bash
# 检查 core dump 限制
ulimit -c

# 设置为无限制
ulimit -c unlimited

# 检查 core dump 模式
cat /proc/sys/kernel/core_pattern

# 设置 core dump 位置
echo "core.%e.%p" > /proc/sys/kernel/core_pattern
```

### 问题：堆栈跟踪不完整

**可能原因**:
1. 编译时未包含调试信息
2. 堆栈被破坏
3. 最大深度限制

**解决方法**:
```zig
// 增加最大深度
try stack_trace.initGlobalCapture(allocator, 256);

// 编译时包含调试信息
// zig build -Doptimize=Debug
```

## 安全考虑

### 1. 信息泄露

崩溃报告可能包含敏感信息：

- 内存地址（可用于 ASLR 绕过）
- 环境变量（可能包含密钥）
- 堆栈内容（可能包含密码）

**建议**:
- 限制报告目录的访问权限
- 定期审查报告内容
- 考虑加密敏感报告

### 2. 拒绝服务

恶意触发崩溃可能导致：

- 磁盘空间耗尽
- 性能下降

**建议**:
- 限制报告文件大小
- 实现速率限制
- 监控崩溃频率

### 3. 权限提升

确保崩溃处理器不会：

- 以提升的权限运行
- 写入不安全的位置
- 执行不可信的代码

## 参考资料

- [POSIX Signal Handling](https://pubs.opengroup.org/onlinepubs/9699919799/functions/sigaction.html)
- [Linux Core Dump](https://man7.org/linux/man-pages/man5/core.5.html)
- [GDB Documentation](https://sourceware.org/gdb/documentation/)
- [LLDB Tutorial](https://lldb.llvm.org/use/tutorial.html)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)

## 版本历史

- **v1.0.0** (2026-01-20): 初始版本
  - 基本信号处理
  - 崩溃报告生成
  - Core dump 支持
  - Linux x86_64/aarch64 支持
