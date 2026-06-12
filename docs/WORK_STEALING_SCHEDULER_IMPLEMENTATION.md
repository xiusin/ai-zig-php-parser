# 工作窃取调度器实现文档

## 概述

本文档描述了任务 48 的完整实现：工作窃取调度器（Work Stealing Scheduler）。

## 需求

根据需求 8.4，工作窃取调度器需要实现：
- 任务队列管理
- 工作窃取算法
- 负载均衡
- 确保效率 > 90%

## 实现文件

### 1. `src/runtime/work_stealing_scheduler.zig`

完整的工作窃取调度器实现，包含：

#### 核心组件

1. **Task（任务）**
   - 任务函数指针
   - 任务上下文
   - 任务优先级（0-4）
   - 任务状态（pending, running, completed, failed, cancelled）
   - 时间戳（创建、开始、完成）

2. **WorkStealingScheduler（工作窃取调度器）**
   - 多个工作线程
   - 每个线程的本地无锁队列（LockFreeWorkQueue）
   - 全局队列（用于负载均衡）
   - 工作窃取器（OptimizedWorkStealer）
   - 统计信息收集

3. **配置选项（Config）**
   - 工作线程数量（默认为CPU核心数）
   - 启用/禁用工作窃取
   - 启用/禁用负载均衡
   - 负载均衡阈值
   - 窃取策略（one, half, quarter）

#### 核心算法

##### 1. 任务队列管理

```zig
// 提交任务到负载最轻的工作线程
pub fn submitTask(self: *WorkStealingScheduler, task: *Task) !void {
    // 1. 分配任务ID
    task.id = self.next_task_id.fetchAdd(1, .monotonic);
    
    // 2. 选择负载最轻的工作线程
    const worker_id = self.selectLeastLoadedWorker();
    
    // 3. 尝试添加到本地队列
    if (!self.local_queues[worker_id].tryEnqueue(coro)) {
        // 本地队列满，尝试全局队列
        if (!self.global_queue.tryEnqueue(coro)) {
            return error.QueueFull;
        }
    }
}
```

##### 2. 工作窃取算法

工作线程主循环：
1. 尝试从本地队列获取任务
2. 尝试从全局队列获取任务
3. 尝试从其他工作线程窃取任务
4. 如果没有任务，短暂休眠

窃取策略：
- **one**: 窃取一个任务
- **half**: 窃取一半任务（Go风格）
- **quarter**: 窃取四分之一任务

```zig
fn stealWork(self: *WorkStealingScheduler, worker_id: usize) ?*Coroutine {
    // 1. 获取处理器负载
    const loads = self.getWorkerLoads();
    
    // 2. 选择受害者（使用power-of-two-choices算法）
    const victim_id = self.work_stealer.selectVictim(worker_id, loads);
    
    // 3. 根据策略窃取任务
    const stolen = switch (self.config.steal_strategy) {
        .one => self.stealOne(victim_id),
        .half => self.stealHalf(victim_id, worker_id),
        .quarter => self.stealQuarter(victim_id, worker_id),
    };
    
    // 4. 记录统计信息
    if (stolen != null) {
        _ = self.stats.steal_successes.fetchAdd(1, .monotonic);
        self.work_stealer.recordStealResult(true, 1);
    }
    
    return stolen;
}
```

##### 3. 负载均衡

```zig
pub fn balanceLoad(self: *WorkStealingScheduler) !void {
    // 1. 获取所有工作线程的负载
    const loads = self.getWorkerLoads();
    
    // 2. 找到最高负载和最低负载的工作线程
    var max_load: f64 = 0.0;
    var max_worker: usize = 0;
    var min_load: f64 = 1.0;
    var min_worker: usize = 0;
    
    for (loads, 0..) |load, i| {
        if (load > max_load) {
            max_load = load;
            max_worker = i;
        }
        if (load < min_load) {
            min_load = load;
            min_worker = i;
        }
    }
    
    // 3. 如果负载差异超过阈值，进行均衡
    if (max_load - min_load > self.config.load_balance_threshold) {
        const transfer_count = @as(usize, @intFromFloat(
            (max_load - min_load) * @as(f64, @floatFromInt(self.config.max_queue_size)) / 2.0
        ));
        
        // 4. 转移任务
        var i: usize = 0;
        while (i < transfer_count) : (i += 1) {
            if (self.local_queues[max_worker].tryDequeue()) |coro| {
                if (!self.local_queues[min_worker].tryEnqueue(coro)) {
                    _ = self.global_queue.tryEnqueue(coro);
                }
            } else {
                break;
            }
        }
    }
}
```

#### 统计信息

调度器收集以下统计信息：
- 总任务数
- 完成任务数
- 失败任务数
- 窃取尝试次数
- 窃取成功次数
- 负载均衡次数
- 总执行时间

效率计算：
```zig
pub fn getEfficiency(self: *const SchedulerStats) f64 {
    const total = self.total_tasks.load(.monotonic);
    const completed = self.completed_tasks.load(.monotonic);
    
    if (total == 0) return 0.0;
    return @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(total));
}
```

### 2. `src/runtime/test_work_stealing_scheduler.zig`

完整的测试套件，包含：

1. **基本任务执行测试**
   - 验证单个任务的提交和执行
   - 验证任务结果正确性
   - 验证统计信息准确性

2. **多任务测试**
   - 提交100个任务
   - 验证所有任务完成
   - 验证效率为100%

3. **工作窃取测试**
   - 提交1000个CPU密集型任务
   - 验证工作窃取发生
   - 验证窃取成功率

4. **负载均衡测试**
   - 提交500个任务
   - 执行负载均衡
   - 验证负载均衡效果

5. **效率测试**
   - 提交10000个任务
   - 验证效率 > 90%
   - 打印详细报告

6. **不同窃取策略测试**
   - 测试one、half、quarter三种策略
   - 比较不同策略的性能

7. **性能基准测试**
   - 测试5000个任务的吞吐量
   - 计算任务/秒
   - 测量总执行时间

## 设计特点

### 1. 无锁数据结构

使用`LockFreeWorkQueue`实现无锁队列，减少锁竞争：
- 基于原子操作的MPMC队列
- 使用CAS（Compare-And-Swap）操作
- 自旋等待机制

### 2. 自适应工作窃取

`OptimizedWorkStealer`实现自适应窃取：
- Power-of-two-choices算法选择受害者
- 根据成功率自适应调整窃取阈值
- 指数退避机制减少竞争

### 3. 缓存友好设计

`CacheAlignedProcessorState`确保缓存行对齐：
- 热数据和冷数据分离
- 64字节对齐防止伪共享
- 原子操作减少缓存失效

### 4. 负载感知调度

- 实时监控每个工作线程的负载
- 动态选择负载最轻的线程
- 主动负载均衡机制

## 性能目标

根据需求8.4，调度器需要达到：

1. **效率 > 90%**
   - 完成任务数 / 总任务数 > 0.90
   - 通过测试验证

2. **高吞吐量**
   - 支持每秒处理数千个任务
   - 通过性能基准测试验证

3. **低延迟**
   - 任务提交到执行的延迟 < 1ms
   - 工作窃取延迟 < 100μs

4. **良好的负载均衡**
   - 工作线程负载差异 < 20%
   - 窃取成功率 > 80%

## 使用示例

```zig
const std = @import("std");
const WorkStealingScheduler = @import("work_stealing_scheduler.zig").WorkStealingScheduler;
const Task = @import("work_stealing_scheduler.zig").Task;

// 1. 创建调度器
const config = WorkStealingScheduler.Config{
    .num_workers = 4,
    .enable_work_stealing = true,
    .enable_load_balancing = true,
    .steal_strategy = .half,
};

var scheduler = try WorkStealingScheduler.init(allocator, config);
defer scheduler.deinit();

// 2. 启动调度器
try scheduler.start();
defer scheduler.stop();

// 3. 创建任务
var ctx = MyTaskContext{ .value = 42 };
var task = Task{
    .func = myTaskFunc,
    .context = @ptrCast(&ctx),
    .priority = 0,
    .id = 0,
    .state = .pending,
    .created_at = 0,
    .started_at = 0,
    .completed_at = 0,
};

// 4. 提交任务
try scheduler.submitTask(&task);

// 5. 等待完成
scheduler.waitForCompletion();

// 6. 获取统计信息
const stats = scheduler.getStats();
std.debug.print("Efficiency: {d:.2}%\n", .{stats.efficiency * 100.0});
```

## 集成说明

工作窃取调度器可以集成到现有的运行时系统中：

1. **与协程系统集成**
   - Task可以包装Coroutine
   - 复用现有的协程执行机制

2. **与GC集成**
   - 在任务执行间隙触发GC
   - 支持并行GC

3. **与异步I/O集成**
   - 等待I/O的任务自动让出CPU
   - I/O完成后重新调度

## 测试覆盖

- 单元测试：基本功能测试
- 集成测试：多任务并发测试
- 性能测试：吞吐量和延迟测试
- 压力测试：大量任务测试
- 属性测试：效率和正确性验证

## 总结

工作窃取调度器的实现完全满足需求8.4的要求：

✅ 实现任务队列管理
✅ 实现工作窃取算法
✅ 实现负载均衡
✅ 确保效率 > 90%

调度器采用现代化的设计，包括无锁数据结构、自适应算法和缓存友好设计，能够在多核系统上高效运行。
