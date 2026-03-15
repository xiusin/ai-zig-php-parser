<?php
// 测试3: 高级OOP特性混搭
abstract class BaseEntity {
    protected static $instanceCount = 0;
    private $id;
    
    public function __construct() {
        self::$instanceCount++;
        $this->id = uniqid();
    }
    
    abstract public function calculate(): float;
    
    public static function getCount(): int {
        return self::$instanceCount;
    }
}

interface Calculable {
    public function add($value): self;
    public function multiply($factor): self;
}

trait LoggerTrait {
    private $logs = [];
    
    protected function log(string $msg): void {
        $this->logs[] = date('Y-m-d H:i:s') . ": " . $msg;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
}

final class Calculator extends BaseEntity implements Calculable {
    use LoggerTrait;
    
    private $value = 0;
    
    public function __construct(float $initial = 0) {
        parent::__construct();
        $this->value = $initial;
        $this->log("Calculator created with value: " . $initial);
    }
    
    public function calculate(): float {
        return $this->value * 2 + sqrt(abs($this->value));
    }
    
    public function add($value): self {
        $this->value += is_numeric($value) ? $value : 0;
        $this->log("Added: " . $value);
        return $this;
    }
    
    public function multiply($factor): self {
        $this->value *= is_numeric($factor) ? $factor : 1;
        $this->log("Multiplied by: " . $factor);
        return $this;
    }
    
    public function __toString(): string {
        return "Calculator[value=" . $this->value . "]";
    }
}

class MathHelper {
    public static function factorial(int $n): int {
        return $n <= 1 ? 1 : $n * self::factorial($n - 1);
    }
}

$calc = new Calculator(10);
$result = $calc->add(5)->multiply(2)->add("invalid")->calculate();
echo "Result: " . $result . "\n";
echo $calc . "\n";
echo "Instance count: " . BaseEntity::getCount() . "\n";
echo "Factorial of 5: " . MathHelper::factorial(5) . "\n";
print_r($calc->getLogs());
?>