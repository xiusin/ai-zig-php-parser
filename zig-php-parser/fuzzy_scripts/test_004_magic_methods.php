<?php
// 测试4: 魔法方法全测试
class MagicTester {
    private $data = [];
    private static $calls = [];
    
    public function __construct(array $initial = []) {
        $this->data = $initial;
    }
    
    public function __get(string $name) {
        self::$calls[] = "__get: $name";
        return $this->data[$name] ?? null;
    }
    
    public function __set(string $name, $value): void {
        self::$calls[] = "__set: $name";
        $this->data[$name] = $value;
    }
    
    public function __isset(string $name): bool {
        self::$calls[] = "__isset: $name";
        return isset($this->data[$name]);
    }
    
    public function __unset(string $name): void {
        self::$calls[] = "__unset: $name";
        unset($this->data[$name]);
    }
    
    public function __call(string $name, array $arguments) {
        self::$calls[] = "__call: $name";
        return "Called $name with " . count($arguments) . " args";
    }
    
    public static function __callStatic(string $name, array $arguments) {
        self::$calls[] = "__callStatic: $name";
        return "Static called $name";
    }
    
    public function __toString(): string {
        return "MagicTester[" . json_encode($this->data) . "]";
    }
    
    public function __invoke(...$args) {
        self::$calls[] = "__invoke";
        return array_sum($args);
    }
    
    public static function getCalls(): array {
        return self::$calls;
    }
}

$magic = new MagicTester(['x' => 10]);
$magic->y = 20;
$magic->z = 30;
echo $magic->x . "\n";
echo $magic->nonexistent . "\n";
echo isset($magic->y) ? "y exists\n" : "y not exists\n";
unset($magic->z);
echo $magic->customMethod(1, 2, 3) . "\n";
echo MagicTester::staticMethod() . "\n";
echo $magic . "\n";
echo $magic(1, 2, 3, 4, 5) . "\n";
print_r(MagicTester::getCalls());
?>