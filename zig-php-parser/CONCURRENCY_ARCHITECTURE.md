# 真实并发协程系统架构文档

## 概述

本文档描述了基于Go调度器的真实并发协程系统的架构和实现。该系统实现了M:P:N调度模型，支持抢占式调度、工作窃取、优先级调度等高级特性。

## 架构设计

### M:P:N调度模型

```
M (Workers/Threads)  P (Logical Processors)  N (Coroutines)
    ┌──────┐          ┌──────┐              ┌─────────┐
    │      │          │      │              │  CORO 1 │
    │  W1  │──────────>│  P1  │─────────────>│  CORO 2 │
    │      │          │      │              │  CORO 3 │
    └──────┘          └──────┘              └─────────┘
    ┌──────┐          ┌──────┐              ┌─────────┐
    │      │          │      │              │  CORO 4 │
    │  W2  │──────────>│  P2  │─────────────>│  CORO 5 │
    │      │          │      │              │  CORO 6 │
    └──────┘          └──────┘              └─────────┘
    ┌──────┐          ┌──────┐
    │      │          │      │
    │  W3  │──────────>│  P3  │
    │      │          │      │
    └──────┘          └──────┘
    ┌──────┐          ┌──────┐
    │      │          │      │
    │  W4  │──────────>│  P4  │
    │      │          │      │
    └──────┘          └──────┘
```

### 核心组件

#### 1. Scheduler（调度器）

**文件**: `src/runtime/coroutine_scheduler.zig`

**职责**:
- 管理所有协程的生命周期
- 协调工作线程的调度
- 实现工作窃取算法
- 提供协程创建、唤醒、等待等接口

**关键特性**:
- **M:P:N模型**: M个工作线程，P个逻辑处理器，N个协程
- **工作窃取**: 负载均衡，避免某个处理器过载
- **优先级调度**: 高优先级协程优先执行
- **抢占式调度**: 支持时间片轮转

**配置参数**:
```zig
pub const SchedulerConfig = struct {
    num_processors: u32,      // P: 逻辑处理器数
    num_workers: u32,          // M: 工作线程数
    stack_size: usize,         // 协程栈大小
    time_slice_us: u32,        // 调度时间片
    enable_preemption: bool,   // 启用抢占式调度
    enable_work_stealing: bool, // 启用工作窃取
};
```

**使用示例**:
```zig
const allocator = std.testing.allocator;
var config = SchedulerConfig{
    .num_processors = 4,
    .num_workers = 4,
    .enable_work_stealing = true,
};

var scheduler = Scheduler.init(allocator, config);
defer scheduler.deinit();

// 设置VM执行函数
scheduler.vm_execute = vm_execute;

// 启动调度器
try scheduler.start();

// 创建协程
const coroutine_id = try scheduler.spawn(callback, args);
```

#### 2. Processor（逻辑处理器）

**文件**: `src/runtime/coroutine_scheduler.zig`

**职责**:
- 管理本地运行队列
- 执行协程
- 实现工作窃取

**运行队列结构**:
```zig
pub const RunQueue = struct {
    // 5个优先级队列
    queues: [5]std.ArrayList(*Coroutine),
    // 当前时间片
    time_slice: u32,
};
```

**调度策略**:
1. 从本地队列获取协程
2. 如果本地队列为空，从其他处理器窃取
3. 执行协程直到完成或让出
4. 重复

#### 3. Coroutine（协程）

**文件**: `src/runtime/coroutine_scheduler.zig`

**职责**:
- 保存执行状态（栈、寄存器、指令指针）
- 管理协程状态转换
- 支持协程挂起和恢复

**协程状态**:
```zig
pub const CoroutineState = enum(u8) {
    created,    // 已创建，未开始
    ready,      // 就绪，可以运行
    running,    // 正在运行
    yielded,    // 已让出CPU
    waiting,    // 等待中（IO、channel等）
    completed,  // 已完成
    cancelled,  // 已取消
};
```

**协程上下文**:
```zig
pub const CoroutineContext = struct {
    stack: CoroutineStack,     // 栈
    ip: usize,                  // 指令指针
    bp: usize,                  // 基指针
    sp: usize,                  // 栈指针
    registers: [16]Value,       // 寄存器
};
```

#### 4. Channel（通道）

**文件**: `src/runtime/channel.zig`

**职责**:
- 实现协程间通信
- 支持缓冲和无缓冲channel
- 提供阻塞和非阻塞操作

**Channel类型**:
```zig
pub const ChannelType = enum(u8) {
    unbuffered,  // 无缓冲channel
    buffered,   // 缓冲channel
};
```

**主要操作**:
```zig
// 发送（阻塞）
try ch.send(value);

// 接收（阻塞）
const value = try ch.recv();

// 尝试发送（非阻塞）
if (try ch.trySend(value)) {
    // 发送成功
}

// 尝试接收（非阻塞）
if (const value = try ch.tryRecv()) |v| {
    // 接收成功
}

// 带超时的发送
if (try ch.sendTimeout(value, 1000)) {
    // 发送成功
}

// 带超时的接收
if (const value = try ch.recvTimeout(1000)) |v| {
    // 接收成功
}

// 关闭channel
ch.close();
```

#### 5. Mutex（互斥锁）

**文件**: `src/runtime/sync.zig`

**职责**:
- 提供互斥访问保护
- 支持阻塞和非阻塞操作
- 管理等待队列

**主要操作**:
```zig
var mutex = Mutex.init(allocator);
defer mutex.deinit();

// 锁定（阻塞）
mutex.lock(coroutine_id);
// ... 临界区代码 ...
mutex.unlock(coroutine_id);

// 尝试锁定（非阻塞）
if (mutex.tryLock(coroutine_id)) {
    // 获取锁成功
    mutex.unlock(coroutine_id);
}
```

#### 6. RWMutex（读写锁）

**文件**: `src/runtime/sync.zig`

**职责**:
- 支持多个读者或单个写者
- 提高读多写少场景的性能

**主要操作**:
```zig
var rwmutex = RWMutex.init(allocator);
defer rwmutex.deinit();

// 获取读锁
rwmutex.readLock(coroutine_id);
// ... 读操作 ...
rwmutex.readUnlock(coroutine_id);

// 获取写锁
rwmutex.writeLock(coroutine_id);
// ... 写操作 ...
rwmutex.writeUnlock(coroutine_id);
```

#### 7. WaitGroup（等待组）

**文件**: `src/runtime/sync.zig`

**职责**:
- 等待一组协程完成
- 类似Go的sync.WaitGroup

**使用示例**:
```zig
var wg = WaitGroup.init(allocator);
defer wg.deinit();

// 启动多个协程
wg.add(3);
try scheduler.spawn(worker1, &.{});
try scheduler.spawn(worker2, &.{});
try scheduler.spawn(worker3, &.{});

// 等待所有协程完成
wg.wait(coroutine_id);
```

#### 8. Once（一次性执行）

**文件**: `src/runtime/sync.zig`

**职责**- 确保函数只执行一次
- 线程安全的初始化

**使用示例**:
```zig
var once = Once.init();

// 确保初始化代码只执行一次
once.do(initialize) catch {};
once.do(initialize) catch {}; // 不会再次执行
```

## 调度算法

### 1. 优先级调度

每个协程有一个优先级（0-4，0最高）：
- 0: system - 系统级任务
- 1: high - 高优先级任务
- 2: normal - 普通优先级
- 3: low - 低优先级
- 4: background - 后台任务

调度器优先执行高优先级协程，但会定期检查低优先级协程，避免饥饿。

### 2. 工作窃取（Work Stealing）

当某个处理器的本地队列为空时，它会从其他处理器窃取协程：

1. 随机选择一个目标处理器
2. 从目标处理器的低优先级队列窃取协程
3. 保留至少一个协程给目标处理器
4. 将窃取的协程添加到本地队列

### 3. 抢占式调度

每个协程有一个时间片（默认10ms）。当时间片用完后，调度器会：
1. 保存协程的执行状态
2. 将协程放回运行队列
3. 调度下一个协程

### 4. 协程状态转换

```
created ──> ready ──> running ──> completed
             │        │
             │        ├─> yielded ──> ready
             │        │
             │        └─> waiting ──> ready
```

## 内存管理

### 协程栈

- 每个协程有独立的栈（默认2MB）
- 栈帧包含局部变量和返回地址
- 支持栈的动态增长和收缩

### 协程池

- 重用已完成的协程对象
- 减少内存分配开销
- 默认池大小：1000

### Channel缓冲区

- 缓冲channel使用动态数组
- 无缓冲channel直接传递数据，不经过缓冲区

## 性能特性

### 1. 并行性

- 真正的并行执行（多线程）
- 利用多核CPU
- 工作窃取实现负载均衡

### 2. 低延迟

- 优先级调度确保高优先级任务快速响应
- 无锁算法减少同步开销
- 工作窃取减少上下文切换

### 3. 高吞吐量

- 并行执行提高吞吐量
- 批量操作减少系统调用
- 缓冲channel减少阻塞

## 使用示例

### 示例1：生产者-消费者模型

```php
<?php
// 创建channel
$ch = new Channel(10);
$wg = new WaitGroup();

// 生产者协程
go function() use ($ch, $wg) {
    for ($i = 0; $i < 100; $i++) {
        $ch->send($i);
    }
    $ch->close();
    $wg->done();
};

// 消费者协程
go function() use ($ch, $wg) {
    while (($value = $ch->recv()) !== null) {
        echo "Received: $value\n";
    }
    $wg->done();
};

// 等待完成
$wg->wait();
echo "All done\n";
?>
```

### 示例2：互斥锁保护共享资源

```php
<?php
$mutex = new Mutex();

$counter = 0;

// 多个协程递增计数器
for ($i = 0; $i < 10; $i++) {
    go function() use ($mutex, &$counter) {
        $mutex->lock();
        $counter++;
        $mutex->unlock();
    };
}

// 等待所有协程完成
sleep(1);
echo "Counter: $counter\n"; // 应该是10
?>
```

### 示例3：读写锁

```php
<?php
$rwmutex = new RWMLock();

// 多个读者
for ($i = 0; $i < 5; $i++) {
    go function() use ($rwmutex, $data) {
        $rwmutex->readLock();
        echo "Reading: $data\n";
        $rwmutex->readUnlock();
    };
}

// 单个写者
go function() use ($rwmutex, &$data) {
    $rwmutex->writeLock();
    $data = "new value";
    echo "Writing: $data\n";
    $rwmutex->writeUnlock();
};
?>
```

### 示例4：Select语句

```php
<?php
$ch1 = new Channel(10);
$ch2 = new Channel(10);

select {
    $ch1->recv() => $value {
        echo "Received from ch1: $value\n";
    },
    $ch2->recv() => $value {
        echo "Received from ch2: $value\n";
    },
    default => {
        echo "No data available\n";
    }
};
?>
```

## 与Go的对比

| 特性 | Go | zig-php-parser |
|------|-----|----------------|
| 调度模型 | M:P:N | M:P:N          |
| 工作窃取 | ✓ | 需确认            |
| 优先级调度 | ✓ | 需确认            |
| 抢占式调度 | ✓ | 需确认            |
| Channel | ✓ | 需确认            |
| Mutex | ✓ | 需确认            |
| RWMutex | ✓ | 需确认            |
| WaitGroup | ✓ | 需确认            |
| Once | ✓ | 需确认            |
| Select | ✓ | 需确认        |
| Context | ✓ | 需确认              |

## 性能优化建议

1. **调整处理器数量**: 根据CPU核心数调整`num_processors`
2. **调整栈大小**: 根据实际需求调整`stack_size`
3. **调整时间片**: 根据任务特性调整`time_slice_us`
4. **启用工作窃取**: 在多核系统上启用
5. **使用缓冲Channel**: 减少阻塞，提高吞吐量
6. **合理使用优先级**: 避免高优先级任务过多

## 测试

运行测试：
```bash
zig test src/runtime/test_concurrency.zig
```

测试覆盖：
-  并发协程创建和执行
-  Channel通信
-  无缓冲Channel同步
-  Mutex同步
-  RWMutex同步
-  WaitGroup同步
-  Once执行
-  Channel超时操作
-  工作窃取
-  优先级调度
-  生产者-消费者模型

## 已知限制

1. **Select语句**: 部分实现，需要完善
2. **Context取消**: 需要与调度器深度集成
3. **协程栈溢出**: 需要实现栈增长机制
4. **死锁检测**: 需要添加死锁检测算法
5. **性能监控**: 需要添加详细的性能统计

## 改进

1. 添加协程池预热
2. 实现协程栈的动态增长
3. 添加死锁检测和避免
4. 实现更精细的调度策略
5. 添加性能监控和调优工具
6. 实现Select语句的完整功能
7. 添加协程调试和跟踪工具

## 参考资料

- Go调度器: https://go.dev/doc/effective_go#concurrency
- Go Channel: https://go.dev/tour/concurrency/2
- Go Mutex: https://pkg.go.dev/sync#Mutex
- Go WaitGroup: https://pkg.go.dev/sync#WaitGroup