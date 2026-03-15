<?php
// 测试24: Fiber协程测试 (PHP 8.1+)
if (!class_exists('Fiber')) {
    echo "Fiber not available\n";
    exit(0);
}

// 基本Fiber
$fiber = new Fiber(function (): int {
    echo "Fiber started\n";
    $value = Fiber::suspend('suspended');
    echo "Fiber resumed with: $value\n";
    return 42;
});

$result = $fiber->start();
echo "Start returned: $result\n";
$fiberResult = $fiber->resume('test value');
echo "Resume returned: $fiberResult\n";

// 多Fiber协作
$fiber1 = new Fiber(function (): void {
    for ($i = 1; $i <= 3; $i++) {
        echo "Fiber1: $i\n";
        Fiber::suspend();
    }
});

$fiber2 = new Fiber(function (): void {
    for ($i = 'a'; $i <= 'c'; $i++) {
        echo "Fiber2: $i\n";
        Fiber::suspend();
    }
});

$fiber1->start();
$fiber2->start();
$fiber1->resume();
$fiber2->resume();
$fiber1->resume();
$fiber2->resume();

// 嵌套Fiber
function nestedFiberTest(): void {
    $inner = new Fiber(function (): string {
        echo "Inner fiber\n";
        return Fiber::suspend('inner suspended');
    });
    
    $result = $inner->start();
    echo "Inner result: $result\n";
    $inner->resume('inner value');
}

$outer = new Fiber('nestedFiberTest');
$outer->start();

// Fiber异常处理
$errorFiber = new Fiber(function (): void {
    try {
        echo "Fiber with error\n";
        throw new RuntimeException("Fiber error");
    } catch (Exception $e) {
        echo "Caught in fiber: " . $e->getMessage() . "\n";
        Fiber::suspend('handled');
    }
});

$errorFiber->start();
echo "Error fiber status: " . ($errorFiber->isTerminated() ? "terminated" : "running") . "\n";

// 从Fiber外部获取返回值
$returnFiber = new Fiber(function (): int {
    Fiber::suspend('working');
    return 100;
});

$returnFiber->start();
$returnFiber->resume();
echo "Fiber return value: " . $returnFiber->getReturn() . "\n";
?>
