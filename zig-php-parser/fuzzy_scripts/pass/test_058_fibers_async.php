<?php
// 测试58: Fiber协程与异步模式模拟 - PHP 8.1协程深度测试
// 测试目的：验证Fiber的suspend/resume机制和状态管理

if (!class_exists('Fiber')) {
    echo "Fiber not available (PHP 8.1+ required)\n";
    exit(0);
}

class AsyncTask {
    private Fiber $fiber;
    private mixed $result = null;
    private bool $completed = false;
    
    public function __construct(callable $callback) {
        $this->fiber = new Fiber(function() use ($callback) {
            $this->result = $callback();
            $this->completed = true;
            return $this->result;
        });
    }
    
    public function start(): void {
        if ($this->fiber->isStarted()) return;
        $this->fiber->start();
    }
    
    public function resume(): void {
        if ($this->fiber->isSuspended()) {
            $this->fiber->resume();
        }
    }
    
    public function isCompleted(): bool {
        return $this->completed || $this->fiber->isTerminated();
    }
    
    public function getResult(): mixed {
        if ($this->fiber->isTerminated()) {
            return $this->fiber->getReturn();
        }
        return $this->result;
    }
}

class Scheduler {
    private array $tasks = [];
    
    public function add(AsyncTask $task): void {
        $this->tasks[] = $task;
    }
    
    public function run(): void {
        // 启动所有任务
        foreach ($this->tasks as $task) {
            $task->start();
        }
        
        // 循环直到所有任务完成
        $running = true;
        while ($running) {
            $running = false;
            foreach ($this->tasks as $task) {
                if (!$task->isCompleted()) {
                    $task->resume();
                    $running = true;
                }
            }
            if ($running) {
                // 模拟异步等待
                usleep(1000);
            }
        }
    }
    
    public function getResults(): array {
        return array_map(fn($t) => $t->getResult(), $this->tasks);
    }
}

// 模拟异步IO任务
function asyncFetch(string $url, int $delay): callable {
    return function() use ($url, $delay) {
        echo "Starting fetch: $url\n";
        Fiber::suspend("fetching $url");
        
        // 模拟延迟
        $remaining = $delay;
        while ($remaining > 0) {
            Fiber::suspend("waiting... ($remaining ms remaining)");
            $remaining -= 100;
        }
        
        echo "Completed fetch: $url\n";
        return "Data from $url";
    };
}

// 创建任务
$task1 = new AsyncTask(asyncFetch('https://api1.example.com', 200));
$task2 = new AsyncTask(asyncFetch('https://api2.example.com', 100));
$task3 = new AsyncTask(asyncFetch('https://api3.example.com', 300));

$scheduler = new Scheduler();
$scheduler->add($task1);
$scheduler->add($task2);
$scheduler->add($task3);

echo "Running async tasks...\n";
$scheduler->run();

echo "\nAll tasks completed. Results:\n";
foreach ($scheduler->getResults() as $i => $result) {
    echo "  Task $i: $result\n";
}

// Fiber异常处理
echo "\n--- Exception Handling ---\n";
$errorFiber = new Fiber(function() {
    echo "Fiber starting\n";
    Fiber::suspend("checkpoint 1");
    
    try {
        echo "About to throw\n";
        throw new RuntimeException("Fiber error!");
    } catch (RuntimeException $e) {
        echo "Caught inside fiber: " . $e->getMessage() . "\n";
        Fiber::suspend("recovered");
    }
    
    return "success";
});

echo $errorFiber->start() . "\n";
echo $errorFiber->resume() . "\n";
echo "Final: " . $errorFiber->getReturn() . "\n";

// 嵌套Fiber
echo "\n--- Nested Fibers ---\n";
$outerFiber = new Fiber(function() {
    echo "Outer fiber starts\n";
    
    $innerResult = null;
    $innerFiber = new Fiber(function() use (&$innerResult) {
        echo "  Inner fiber starts\n";
        Fiber::suspend("inner suspended");
        $innerResult = "inner completed";
        echo "  Inner fiber ends\n";
        return $innerResult;
    });
    
    echo $innerFiber->start() . "\n";
    echo "Outer: inner is " . ($innerFiber->isSuspended() ? "suspended" : "running") . "\n";
    echo $innerFiber->resume() . "\n";
    
    Fiber::suspend("outer suspended");
    echo "Outer fiber ends\n";
    return "outer completed";
});

echo $outerFiber->start() . "\n";
echo "Outer resumed: " . ($outerFiber->isSuspended() ? "yes" : "no") . "\n";
if ($outerFiber->isSuspended()) {
    echo $outerFiber->resume() . "\n";
}
echo "Return: " . $outerFiber->getReturn() . "\n";
?>
