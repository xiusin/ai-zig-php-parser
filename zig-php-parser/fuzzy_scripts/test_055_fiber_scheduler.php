<?php
// 测试55: 纤维调度器 (PHP 8.1)
if (!class_exists('Fiber')) {
    echo "Fiber not available\n";
    exit(0);
}

// 简单调度器
class Scheduler {
    private $fibers = [];
    
    public function schedule(callable $callback): void {
        $fiber = new Fiber($callback);
        $fiber->start();
        if (!$fiber->isTerminated()) {
            $this->fibers[] = $fiber;
        }
    }
    
    public function run(): void {
        while (!empty($this->fibers)) {
            foreach ($this->fibers as $i => $fiber) {
                if ($fiber->isSuspended()) {
                    $fiber->resume();
                }
                if ($fiber->isTerminated()) {
                    unset($this->fibers[$i]);
                }
            }
            $this->fibers = array_values($this->fibers);
        }
    }
}

$scheduler = new Scheduler();

$scheduler->schedule(function () {
    for ($i = 1; $i <= 3; $i++) {
        echo "Task A: $i\n";
        Fiber::suspend();
    }
});

$scheduler->schedule(function () {
    for ($i = 'a'; $i <= 'c'; $i++) {
        echo "Task B: $i\n";
        Fiber::suspend();
    }
});

$scheduler->run();

// Fiber返回值
$resultFiber = new Fiber(function (): int {
    Fiber::suspend('step1');
    Fiber::suspend('step2');
    return 42;
});

echo $resultFiber->start() . "\n";
echo $resultFiber->resume() . "\n";
echo $resultFiber->resume() . "\n";
echo "Final: " . $resultFiber->getReturn() . "\n";
?>