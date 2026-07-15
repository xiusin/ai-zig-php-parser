<?php
// 极度混搭: OOP魔法方法 + 类型自动转换 + match表达式 + 闭包 + 异常处理
echo "=== c001: OOP Magic + Type Juggle + Match + Closure ===\n\n";

class TypedContainer {
    private array $store = [];
    private array $types = [];
    private static int $instanceCount = 0;
    public readonly string $id;

    public function __construct() {
        $cnt = ++self::$instanceCount;
        $num = (string)$cnt;
        $this->id = "TC-" . str_pad($num, 4, "0", STR_PAD_LEFT);
    }

    public function __set(string $key, mixed $value): void {
        $this->store[$key] = $value;
        $this->types[$key] = match(true) {
            is_int($value) => 'int',
            is_float($value) => 'float',
            is_string($value) => 'string',
            is_bool($value) => 'bool',
            is_array($value) => 'array',
            is_object($value) => get_class($value),
            is_null($value) => 'null',
            default => 'unknown',
        };
    }

    public function __get(string $key): mixed {
        if (!array_key_exists($key, $this->store)) {
            throw new OutOfBoundsException("Key '$key' not found in {$this->id}");
        }
        return $this->store[$key];
    }

    public function __isset(string $key): bool {
        return isset($this->store[$key]);
    }

    public function __unset(string $key): void {
        unset($this->store[$key], $this->types[$key]);
    }

    public function __toString(): string {
        $pairs = [];
        foreach ($this->store as $k => $v) {
            $pairs[] = "$k:{$this->types[$k]}";
        }
        return $this->id . "[" . implode(",", $pairs) . "]";
    }

    public function __invoke(mixed $arg): mixed {
        if (is_string($arg)) {
            return $this->__get($arg);
        }
        if (is_array($arg)) {
            foreach ($arg as $k => $v) {
                $this->__set((string)$k, $v);
            }
            return $this;
        }
        throw new InvalidArgumentException("Invalid invocation argument");
    }

    public function __clone(): void {
        $this->store = array_map(fn($v) => is_object($v) ? clone $v : $v, $this->store);
    }

    public function getType(string $key): ?string {
        return $this->types[$key] ?? null;
    }

    public function coerce(string $key, string $targetType): mixed {
        $val = $this->__get($key);
        return match($targetType) {
            'int' => (int)$val,
            'float' => (float)$val,
            'string' => (string)$val,
            'bool' => (bool)$val,
            'array' => (array)$val,
            default => $val,
        };
    }

    public static function count(): int {
        return self::$instanceCount;
    }
}

// === 测试 ===

$tc = new TypedContainer();

// 自动类型转换存储
$tc->intVal = 42;
$tc->floatVal = 3.14;
$tc->strVal = "hello";
$tc->boolVal = true;
$tc->nullVal = null;
$tc->arrVal = [1, 2, 3];

echo $tc . "\n";

// 类型强制转换
echo "int as string: " . $tc->coerce('intVal', 'string') . "\n";
echo "string as int: " . $tc->coerce('strVal', 'int') . "\n";
echo "bool as int: " . $tc->coerce('boolVal', 'int') . "\n";
echo "float as int: " . $tc->coerce('floatVal', 'int') . "\n";

// __invoke 模式
echo "Invoke string key: " . $tc('intVal') . "\n";
$tc(['x' => 100, 'y' => 200]);
echo "After array invoke: $tc\n";

// 异常处理
try {
    $val = $tc->nonExistent;
} catch (OutOfBoundsException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 克隆
$tc2 = clone $tc;
echo "Cloned: $tc2\n";
echo "Instance count: " . TypedContainer::count() . "\n";

// 类型自动转换运算
$mixed1 = "10" + 20;
$mixed2 = "10" . 20;
$mixed3 = true + true;
$mixed4 = "3.14" * 2;
$mixed5 = 0 == "0";
$mixed6 = "" == 0;

echo "Mixed1 (string+int): $mixed1 type=" . gettype($mixed1) . "\n";
echo "Mixed2 (string.int): $mixed2 type=" . gettype($mixed2) . "\n";
echo "Mixed3 (bool+bool): $mixed3 type=" . gettype($mixed3) . "\n";
echo "Mixed4 (string*int): $mixed4 type=" . gettype($mixed4) . "\n";
echo "Mixed5 (==): " . var_export($mixed5, true) . "\n";
echo "Mixed6 (empty==0): " . var_export($mixed6, true) . "\n";

// 闭包捕获与类型
$counter = 0;
$inc = function() use (&$counter) {
    $counter++;
    return match(gettype($counter)) {
        'integer' => "int:$counter",
        'double' => "float:$counter",
        default => "other:$counter",
    };
};

echo $inc() . "\n";
echo $inc() . "\n";
echo $inc() . "\n";
echo "Final counter: $counter\n";

echo "\n=== c001 Done ===\n";
