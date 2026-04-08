<?php
// Fiber协程基础测试 (PHP 8.1+)

// 基础Fiber
$fiber = new Fiber(function (): void {
    echo "Fiber started\n";

    $value = Fiber::suspend('suspended value');
    echo "Resumed with: $value\n";

    Fiber::suspend('second suspension');
    echo "Fiber ending\n";
});

// 启动fiber
echo "Starting fiber\n";
$result = $fiber->start();
echo "After start: " . var_export($result, true) . "\n";

// 恢复fiber
echo "Resuming fiber\n";
$result = $fiber->resume('resumed value');
echo "After resume: " . var_export($result, true) . "\n";

// 再次恢复
echo "Final resume\n";
$fiber->resume('final value');
echo "Fiber terminated: " . var_export($fiber->isTerminated(), true) . "\n";

// Fiber状态检查
$fiber2 = new Fiber(function (): void {
    Fiber::suspend('test');
});

echo "Before start - started: " . var_export($fiber2->isStarted(), true) . "\n";
$fiber2->start();
echo "After start - started: " . var_export($fiber2->isStarted(), true) . "\n";
echo "Suspended: " . var_export($fiber2->isSuspended(), true) . "\n";
$fiber2->resume();
echo "After resume - terminated: " . var_export($fiber2->isTerminated(), true) . "\n";

// Fiber返回值
$fiber3 = new Fiber(function (): string {
    return 'fiber return value';
});

$fiber3->start();
$returned = $fiber3->getReturn();
echo "Fiber returned: $returned\n";

// 嵌套Fiber
$outerFiber = new Fiber(function (): void {
    echo "Outer fiber start\n";

    $innerFiber = new Fiber(function (): void {
        echo "Inner fiber start\n";
        Fiber::suspend('inner suspended');
        echo "Inner fiber end\n";
    });

    $innerFiber->start();
    echo "Inner suspended, resuming\n";
    $innerFiber->resume();

    echo "Outer fiber end\n";
});

echo "Starting outer fiber\n";
$outerFiber->start();
echo "Outer fiber completed\n";

// Fiber异常处理
$fiberException = new Fiber(function (): void {
    throw new Exception('Fiber exception');
});

try {
    $fiberException->start();
} catch (Throwable $e) {
    echo "Caught exception: " . $e->getMessage() . "\n";
}

// Fiber抛入异常
$fiberThrow = new Fiber(function (): void {
    try {
        Fiber::suspend('waiting');
    } catch (Exception $e) {
        echo "Caught thrown exception: " . $e->getMessage() . "\n";
    }
});

$fiberThrow->start();
$fiberThrow->throw(new Exception('thrown into fiber'));

// 获取当前Fiber
$fiberCurrent = new Fiber(function (): void {
    $current = Fiber::getCurrent();
    echo "Current fiber is self: " . var_export($current === $fiberCurrent, true) . "\n";
    Fiber::suspend('check');
});

$fiberCurrent->start();
$fiberCurrent->resume();

echo "Fiber tests completed\n";
