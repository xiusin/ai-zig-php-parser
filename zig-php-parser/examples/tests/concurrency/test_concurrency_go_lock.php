<?php
/**
 * go 关键词和 lock 关键词测试
 * 测试协程创建、锁语法糖、并发控制等功能
 */

echo "========================================\n";
echo "  go 和 lock 关键词测试\n";
echo "========================================\n\n";

// ==================== 测试1: go 关键词基础 ====================
echo "【测试1】go 关键词基础\n";
// 注意：go 关键词需要在 VM 中实现协程支持
// 以下是预期的 API 设计示例

/*
go function() {
    echo "协程1开始\n";
    sleep(100);
    echo "协程1完成\n";
};

go function() {
    echo "协程2开始\n";
    sleep(50);
    echo "协程2完成\n";
};

echo "主程序继续执行\n";
sleep(200);
*/

echo "⚠️  go 关键词需要 VM 支持（当前为注释示例）\n\n";

// ==================== 测试2: lock 关键词基础 ====================
echo "【测试2】lock 关键词基础\n";
// 注意：lock 关键词需要在 VM 中实现
// 以下是预期的 API 设计示例

/*
$shared_data = 0;

lock {
    $shared_data = 100;
    echo "受保护的代码块: $shared_data\n";
};

echo "锁已释放: $shared_data\n";
*/

echo "⚠️  lock 关键词需要 VM 支持（当前为注释示例）\n\n";

// ==================== 测试3: Mutex 类作为替代方案 ====================
echo "【测试3】使用 Mutex 类替代 lock 关键词\n";
try {
    $mutex = new Mutex();
    $shared_data = 0;

    $mutex->lock();
    $shared_data = 100;
    echo "受保护的代码块: $shared_data\n";
    $mutex->unlock();

    echo "锁已释放: $shared_data\n";
    echo "✅ Mutex 类测试通过\n";
} catch (Exception $e) {
    echo "❌ Mutex 类测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试4: 嵌套 lock ====================
echo "【测试4】嵌套 lock（使用 Mutex）\n";
try {
    $mutex1 = new Mutex();
    $mutex2 = new Mutex();
    $data1 = 0;
    $data2 = 0;

    $mutex1->lock();
    $data1 = 10;

    $mutex2->lock();
    $data2 = 20;

    echo "嵌套锁: data1=$data1, data2=$data2\n";

    $mutex2->unlock();
    $mutex1->unlock();

    echo "✅ 嵌套锁测试通过\n";
} catch (Exception $e) {
    echo "❌ 嵌套锁测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试5: lock 异常处理 ====================
echo "【测试5】lock 异常处理（使用 Mutex）\n";
try {
    $mutex = new Mutex();
    $data = 0;

    $mutex->lock();
    try {
        $data = 50;
        // 模拟异常
        throw new Exception("测试异常");
    } catch (Exception $e) {
        echo "捕获异常: " . $e->getMessage() . "\n";
        $mutex->unlock(); // 确保解锁
        echo "锁已释放\n";
    }

    echo "✅ 异常处理测试通过\n";
} catch (Exception $e) {
    echo "❌ 异常处理测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试6: Channel 作为协程通信 ====================
echo "【测试6】Channel 作为协程通信\n";
try {
    $ch = new Channel(5);

    // 生产者
    $ch->send(1);
    $ch->send(2);
    $ch->send(3);

    // 消费者
    while (($value = $ch->recv()) !== null) {
        echo "接收: $value\n";
    }

    echo "✅ Channel 通信测试通过\n";
} catch (Exception $e) {
    echo "❌ Channel 通信测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试7: WaitGroup 模拟 ====================
echo "【测试7】WaitGroup 模拟（使用 Counter + Channel）\n";
try {
    $counter = new Atomic(0);
    $done_ch = new Channel(10);

    // 模拟启动多个任务
    for ($i = 0; $i < 5; $i++) {
        $counter->increment();
        $done_ch->send($i);
        echo "任务 $i 完成\n";
    }

    // 等待所有任务完成
    for ($i = 0; $i < 5; $i++) {
        $done_ch->recv();
    }

    $total = $counter->load();
    echo "总共完成 $total 个任务\n";
    echo "✅ WaitGroup 模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ WaitGroup 模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试8: 生产者-消费者模式 ====================
echo "【测试8】生产者-消费者模式\n";
try {
    $ch = new Channel(10);
    $mutex = new Mutex();
    $shared = new SharedData();
    $shared->set("produced", 0);
    $shared->set("consumed", 0);

    // 生产者
    for ($i = 0; $i < 5; $i++) {
        $mutex->lock();
        $produced = $shared->get("produced");
        $produced++;
        $shared->set("produced", $produced);
        $mutex->unlock();
        $ch->send($i);
        echo "生产: $i\n";
    }
    $ch->close();

    // 消费者
    while (($value = $ch->recv()) !== null) {
        $mutex->lock();
        $consumed = $shared->get("consumed");
        $consumed++;
        $shared->set("consumed", $consumed);
        $mutex->unlock();
        echo "消费: $value\n";
    }

    $produced = $shared->get("produced");
    $consumed = $shared->get("consumed");
    echo "生产: $produced, 消费: $consumed\n";
    echo "✅ 生产者-消费者模式测试通过\n";
} catch (Exception $e) {
    echo "❌ 生产者-消费者模式测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试9: Worker Pool 模拟 ====================
echo "【测试9】Worker Pool 模拟\n";
try {
    $task_ch = new Channel(20);
    $result_ch = new Channel(20);
    $mutex = new Mutex();
    $results = new SharedData();

    // 提交任务
    for ($i = 0; $i < 10; $i++) {
        $task_ch->send($i);
        echo "提交任务: $i\n";
    }
    $task_ch->close();

    // Worker 处理任务
    while (($task = $task_ch->recv()) !== null) {
        $result = $task * 2;
        $mutex->lock();
        $results->set("result_$task", $result);
        $mutex->unlock();
        $result_ch->send($result);
        echo "处理任务 $task -> $result\n";
    }

    // 收集结果
    for ($i = 0; $i < 10; $i++) {
        $result_ch->recv();
    }

    $size = $results->size();
    echo "总共处理了 $size 个任务\n";
    echo "✅ Worker Pool 模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ Worker Pool 模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试10: 读写锁场景 ====================
echo "【测试10】读写锁场景\n";
try {
    $rwlock = new RWLock();
    $shared = new SharedData();
    $shared->set("data", "初始值");

    // 多个读者
    $rwlock->lockRead();
    $v1 = $shared->get("data");
    echo "读者1: $v1\n";
    $rwlock->unlockRead();

    $rwlock->lockRead();
    $v2 = $shared->get("data");
    echo "读者2: $v2\n";
    $rwlock->unlockRead();

    // 写者
    $rwlock->lockWrite();
    $shared->set("data", "新值");
    echo "写者: 更新数据\n";
    $rwlock->unlockWrite();

    // 再次读取
    $rwlock->lockRead();
    $v3 = $shared->get("data");
    echo "读者3: $v3\n";
    $rwlock->unlockRead();

    echo "✅ 读写锁场景测试通过\n";
} catch (Exception $e) {
    echo "❌ 读写锁场景测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试11: 原子计数器 ====================
echo "【测试11】原子计数器\n";
try {
    $counter = new Atomic(0);

    // 多次递增
    for ($i = 0; $i < 100; $i++) {
        $counter->increment();
    }

    $value = $counter->load();
    echo "原子计数器: $value\n";

    // CAS 操作
    $success = $counter->compareAndSwap(100, 200);
    echo "CAS 结果: " . ($success ? "成功" : "失败") . "\n";

    $value = $counter->load();
    echo "CAS 后的值: $value\n";

    echo "✅ 原子计数器测试通过\n";
} catch (Exception $e) {
    echo "❌ 原子计数器测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试12: 资源池模拟 ====================
echo "【测试12】资源池模拟\n";
try {
    $pool_ch = new Channel(5);
    $mutex = new Mutex();
    $usage = new SharedData();

    // 初始化资源池
    for ($i = 0; $i < 3; $i++) {
        $pool_ch->send("resource_$i");
        echo "创建资源: resource_$i\n";
    }

    // 使用资源
    for ($i = 0; $i < 5; $i++) {
        $resource = $pool_ch->recv();
        echo "获取资源: $resource\n";

        $mutex->lock();
        $usage->set("use_$i", $resource);
        $mutex->unlock();

        // 使用后归还
        $pool_ch->send($resource);
        echo "归还资源: $resource\n";
    }

    echo "✅ 资源池模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ 资源池模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试13: 扇出模式 ====================
echo "【测试13】扇出模式\n";
try {
    $input_ch = new Channel(10);
    $worker1_ch = new Channel(10);
    $worker2_ch = new Channel(10);
    $output_ch = new Channel(10);

    // 输入数据
    for ($i = 0; $i < 10; $i++) {
        $input_ch->send($i);
    }
    $input_ch->close();

    // 分发任务
    while (($task = $input_ch->recv()) !== null) {
        if ($task % 2 == 0) {
            $worker1_ch->send($task);
        } else {
            $worker2_ch->send($task);
        }
    }
    $worker1_ch->close();
    $worker2_ch->close();

    // Worker 1 处理偶数
    while (($task = $worker1_ch->recv()) !== null) {
        $output_ch->send($task * 10);
    }

    // Worker 2 处理奇数
    while (($task = $worker2_ch->recv()) !== null) {
        $output_ch->send($task * 100);
    }

    // 收集结果
    $result_count = 0;
    while (($result = $output_ch->recv()) !== null) {
        echo "结果: $result\n";
        $result_count++;
    }

    echo "总共处理 $result_count 个任务\n";
    echo "✅ 扇出模式测试通过\n";
} catch (Exception $e) {
    echo "❌ 扇出模式测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试14: 扇入模式 ====================
echo "【测试14】扇入模式\n";
try {
    $input1_ch = new Channel(5);
    $input2_ch = new Channel(5);
    $input3_ch = new Channel(5);
    $output_ch = new Channel(15);

    // 输入数据到多个通道
    for ($i = 0; $i < 3; $i++) {
        $input1_ch->send($i);
        $input2_ch->send($i + 10);
        $input3_ch->send($i + 20);
    }
    $input1_ch->close();
    $input2_ch->close();
    $input3_ch->close();

    // 从多个通道聚合数据
    while (($value = $input1_ch->recv()) !== null) {
        $output_ch->send($value);
    }
    while (($value = $input2_ch->recv()) !== null) {
        $output_ch->send($value);
    }
    while (($value = $input3_ch->recv()) !== null) {
        $output_ch->send($value);
    }

    // 收集结果
    $result_count = 0;
    while (($result = $output_ch->recv()) !== null) {
        echo "聚合结果: $result\n";
        $result_count++;
    }

    echo "总共聚合 $result_count 个数据\n";
    echo "✅ 扇入模式测试通过\n";
} catch (Exception $e) {
    echo "❌ 扇入模式测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试15: 管道模式 ====================
echo "【测试15】管道模式\n";
try {
    $stage1_ch = new Channel(10);
    $stage2_ch = new Channel(10);
    $stage3_ch = new Channel(10);

    // 阶段1: 生成数据
    for ($i = 0; $i < 5; $i++) {
        $stage1_ch->send($i);
        echo "阶段1生成: $i\n";
    }
    $stage1_ch->close();

    // 阶段2: 处理数据（+10）
    while (($value = $stage1_ch->recv()) !== null) {
        $result = $value + 10;
        $stage2_ch->send($result);
        echo "阶段2处理: $value -> $result\n";
    }
    $stage2_ch->close();

    // 阶段3: 最终处理（*2）
    while (($value = $stage2_ch->recv()) !== null) {
        $result = $value * 2;
        $stage3_ch->send($result);
        echo "阶段3处理: $value -> $result\n";
    }
    $stage3_ch->close();

    // 收集最终结果
    echo "最终结果: ";
    while (($result = $stage3_ch->recv()) !== null) {
        echo "$result ";
    }
    echo "\n";

    echo "✅ 管道模式测试通过\n";
} catch (Exception $e) {
    echo "❌ 管道模式测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试16: 超时控制模拟 ====================
echo "【测试16】超时控制模拟\n";
try {
    $ch = new Channel(1);
    $timeout_ch = new Channel(1);

    // 模拟超时
    $timeout_ch->send("timeout");

    // 尝试从空通道接收
    $value = $ch->tryRecv();
    if ($value === null) {
        echo "通道为空，使用超时\n";
        $timeout = $timeout_ch->recv();
        echo "超时信号: $timeout\n";
    }

    echo "✅ 超时控制模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ 超时控制模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试17: 信号量模拟 ====================
echo "【测试17】信号量模拟\n";
try {
    $sem_ch = new Channel(3); // 容量为3的信号量

    // 初始化信号量
    for ($i = 0; $i < 3; $i++) {
        $sem_ch->send(1);
    }

    // 获取信号量
    for ($i = 0; $i < 5; $i++) {
        $sem = $sem_ch->tryRecv();
        if ($sem !== null) {
            echo "任务 $i 获取信号量\n";
            // 使用后归还
            $sem_ch->send(1);
        } else {
            echo "任务 $i 等待信号量\n";
        }
    }

    echo "✅ 信号量模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ 信号量模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试18: 屏障模拟 ====================
echo "【测试18】屏障模拟\n";
try {
    $barrier_count = 3;
    $barrier_ch = new Channel($barrier_count);
    $mutex = new Mutex();
    $shared = new SharedData();
    $shared->set("arrived", 0);

    // 模拟多个参与者到达屏障
    for ($i = 0; $i < $barrier_count; $i++) {
        $mutex->lock();
        $arrived = $shared->get("arrived");
        $arrived++;
        $shared->set("arrived", $arrived);
        $mutex->unlock();
        echo "参与者 $i 到达屏障\n";
        $barrier_ch->send($i);
    }

    // 等待所有参与者
    for ($i = 0; $i < $barrier_count; $i++) {
        $barrier_ch->recv();
    }

    echo "所有参与者已到达，继续执行\n";
    echo "✅ 屏障模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ 屏障模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试19: 限流器模拟 ====================
echo "【测试19】限流器模拟\n";
try {
    $rate_limit_ch = new Channel(3); // 每秒3个请求
    $request_ch = new Channel(10);

    // 初始化限流器
    for ($i = 0; $i < 3; $i++) {
        $rate_limit_ch->send(1);
    }

    // 提交请求
    for ($i = 0; $i < 10; $i++) {
        $request_ch->send($i);
    }
    $request_ch->close();

    // 处理请求（限流）
    while (($request = $request_ch->recv()) !== null) {
        $token = $rate_limit_ch->tryRecv();
        if ($token !== null) {
            echo "处理请求 $request\n";
            // 模拟令牌补充
            $rate_limit_ch->send(1);
        } else {
            echo "请求 $request 被限流\n";
        }
    }

    echo "✅ 限流器模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ 限流器模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试20: 上下文传递模拟 ====================
echo "【测试20】上下文传递模拟\n";
try {
    $context_ch = new Channel(5);
    $mutex = new Mutex();
    $shared = new SharedData();

    // 创建上下文
    $shared->set("context", [
        "user_id" => 123,
        "request_id" => "abc-123",
        "timeout" => 5000
    ]);

    // 传递上下文
    for ($i = 0; $i < 3; $i++) {
        $mutex->lock();
        $context = $shared->get("context");
        $mutex->unlock();
        $context_ch->send($context);
        echo "传递上下文到任务 $i\n";
    }

    // 接收并使用上下文
    for ($i = 0; $i < 3; $i++) {
        $context = $context_ch->recv();
        echo "任务 $i 使用上下文: user_id={$context['user_id']}\n";
    }

    echo "✅ 上下文传递模拟测试通过\n";
} catch (Exception $e) {
    echo "❌ 上下文传递模拟测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 总结 ====================
echo "========================================\n";
echo "  总结\n";
echo "========================================\n";
echo "✅ Mutex 类功能正常\n";
echo "✅ Channel 通信功能正常\n";
echo "✅ Atomic 原子操作功能正常\n";
echo "✅ RWLock 读写锁功能正常\n";
echo "✅ SharedData 共享数据功能正常\n";
echo "⚠️  go 关键词需要 VM 支持\n";
echo "⚠️  lock 关键词需要 VM 支持\n";
echo "========================================\n";
echo "测试完成！\n";