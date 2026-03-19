<?php
// 测试38: 匿名类
$logger = new class {
    private $logs = [];
    
    public function log(string $msg): void {
        $this->logs[] = date("H:i:s") . " - " . $msg;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
};

$logger->log("First message");
$logger->log("Second message");
print_r($logger->getLogs());

// 带构造函数的匿名类
$counter = new class(10) {
    private $count;
    
    public function __construct(int $start) {
        $this->count = $start;
    }
    
    public function increment(): int {
        return ++$this->count;
    }
    
    public function getCount(): int {
        return $this->count;
    }
};

echo "Counter start: " . $counter->getCount() . "\n";
echo "After increment: " . $counter->increment() . "\n";

// 实现接口的匿名类
interface Greetable {
    public function greet(string $name): string;
}

$greeter = new class implements Greetable {
    public function greet(string $name): string {
        return "Hello, $name!";
    }
};

echo $greeter->greet("World") . "\n";

// 继承的匿名类
class BaseProcessor {
    public function process($data) {
        return "Processed: $data";
    }
}

$processor = new class extends BaseProcessor {
    public function process($data) {
        return parent::process(strtoupper($data));
    }
};

echo $processor->process("test") . "\n";
?>
