<?php
// 测试50: throw表达式 - PHP 8.0特性，throw作为表达式而非语句
// 测试目的：验证throw可以在表达式上下文中使用

class ValidationError extends Exception {}
class BusinessLogicError extends Exception {}

// throw在三元运算符中
function divideOrThrow(float $a, float $b): float {
    return $b !== 0.0 
        ? $a / $b 
        : throw new DivisionByZeroError("Cannot divide $a by zero");
}

try {
    echo "10 / 2 = " . divideOrThrow(10, 2) . "\n";
    echo "10 / 0 = " . divideOrThrow(10, 0) . "\n";
} catch (DivisionByZeroError $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// throw在null合并运算符中
$config = ['timeout' => 30];
$timeout = $config['timeout'] ?? throw new RuntimeException("Timeout not configured");
echo "Timeout: $timeout\n";

// throw在箭头函数中
$validate = fn($value) => $value > 0 
    ? $value 
    : throw new ValidationError("Value must be positive, got: $value");

try {
    echo "Valid: " . $validate(42) . "\n";
    echo "Invalid: " . $validate(-5) . "\n";
} catch (ValidationError $e) {
    echo "Validation failed: " . $e->getMessage() . "\n";
}

// throw在match表达式中
function getHttpStatus(int $code): string {
    return match($code) {
        200 => "OK",
        404 => "Not Found",
        500 => "Server Error",
        default => throw new InvalidArgumentException("Unknown HTTP code: $code"),
    };
}

try {
    echo "Status 200: " . getHttpStatus(200) . "\n";
    echo "Status 999: " . getHttpStatus(999) . "\n";
} catch (InvalidArgumentException $e) {
    echo "Invalid code: " . $e->getMessage() . "\n";
}

// throw在数组字面量中
class Item {
    public function __construct(public string $name, public float $price) {
        if ($price < 0) {
            throw new InvalidArgumentException("Price cannot be negative: $price");
        }
    }
}

try {
    $items = [
        new Item("Apple", 1.50),
        new Item("Banana", 0.75),
        // new Item("Invalid", -5.00), // 会抛出异常
    ];
    echo "Created " . count($items) . " items\n";
} catch (InvalidArgumentException $e) {
    echo "Item creation failed: " . $e->getMessage() . "\n";
}

// throw在默认值中（函数参数）
function requireEnv(string $key, string $default = throw new RuntimeException("Environment variable required")): string {
    return $_ENV[$key] ?? $default;
}

// throw在属性访问中
class SafeAccessor {
    private array $data = [];
    public function get(string $key): mixed {
        return $this->data[$key] ?? throw new OutOfBoundsException("Key not found: $key");
    }
    public function set(string $key, mixed $value): void {
        $this->data[$key] = $value;
    }
}

$safe = new SafeAccessor();
$safe->set("name", "Alice");
try {
    echo "Name: " . $safe->get("name") . "\n";
    echo "Age: " . $safe->get("age") . "\n";
} catch (OutOfBoundsException $e) {
    echo "Access error: " . $e->getMessage() . "\n";
}

// throw链式调用
function processOrFail(?string $input): string {
    return trim($input) !== ''
        ? strtoupper(trim($input))
        : throw new BusinessLogicError("Empty input provided");
}

try {
    echo processOrFail("  hello  ") . "\n";
    echo processOrFail("") . "\n";
} catch (BusinessLogicError $e) {
    echo "Processing failed: " . $e->getMessage() . "\n";
}
?>
