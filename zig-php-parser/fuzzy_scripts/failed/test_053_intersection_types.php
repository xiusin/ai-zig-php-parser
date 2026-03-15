<?php
// 测试53: PHP 8.1 交集类型 - 同时实现多个接口的类型声明
// 测试目的：验证(Counter&Logger)这种交集类型语法

interface Logger {
    public function log(string $message): void;
}

interface Counter {
    public function increment(): int;
    public function getCount(): int;
}

interface Resettable {
    public function reset(): void;
}

// 实现单个接口
class SimpleLogger implements Logger {
    private array $logs = [];
    public function log(string $message): void {
        $this->logs[] = date('H:i:s') . ' ' . $message;
    }
    public function getLogs(): array {
        return $this->logs;
    }
}

// 实现两个接口（可用于交集类型）
class CountingLogger implements Counter, Logger {
    private int $count = 0;
    private array $logs = [];
    
    public function increment(): int {
        $this->count++;
        return $this->count;
    }
    
    public function getCount(): int {
        return $this->count;
    }
    
    public function log(string $message): void {
        $this->logs[] = $message;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
}

// 实现三个接口
class AdvancedCounter implements Counter, Logger, Resettable {
    private int $count = 0;
    private array $logs = [];
    
    public function increment(): int {
        $this->count++;
        $this->log("Incremented to {$this->count}");
        return $this->count;
    }
    
    public function getCount(): int {
        return $this->count;
    }
    
    public function log(string $message): void {
        $this->logs[] = date('Y-m-d H:i:s') . ': ' . $message;
    }
    
    public function reset(): void {
        $this->count = 0;
        $this->logs = [];
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
}

// 使用交集类型的函数
function processWithCounterAndLogger(Counter&Logger $service): void {
    for ($i = 0; $i < 3; $i++) {
        $service->increment();
    }
    $service->log("Processing complete");
    echo "Count: " . $service->getCount() . "\n";
}

// 测试CountingLogger
$countingLogger = new CountingLogger();
echo "Testing CountingLogger:\n";
processWithCounterAndLogger($countingLogger);

// 测试AdvancedCounter
$advanced = new AdvancedCounter();
echo "\nTesting AdvancedCounter:\n";
processWithCounterAndLogger($advanced);
echo "Logs:\n";
foreach ($advanced->getLogs() as $log) {
    echo "  $log\n";
}

// 返回交集类型
function createFullService(): Counter&Logger&Resettable {
    return new AdvancedCounter();
}

$service = createFullService();
$service->increment();
$service->increment();
echo "\nBefore reset: " . $service->getCount() . "\n";
$service->reset();
echo "After reset: " . $service->getCount() . "\n";

// 在数组中使用
$services = [
    new CountingLogger(),
    new AdvancedCounter(),
];

echo "\nProcessing all services:\n";
foreach ($services as $i => $svc) {
    echo "Service $i:\n";
    processWithCounterAndLogger($svc);
}

// 简单logger不能用于交集类型函数
// processWithCounterAndLogger(new SimpleLogger()); // 类型错误

// 检查类型
$obj = new AdvancedCounter();
echo "\nType checks:\n";
echo "instanceof Counter: " . ($obj instanceof Counter ? 'yes' : 'no') . "\n";
echo "instanceof Logger: " . ($obj instanceof Logger ? 'yes' : 'no') . "\n";
echo "instanceof Resettable: " . ($obj instanceof Resettable ? 'yes' : 'no') . "\n";
?>
