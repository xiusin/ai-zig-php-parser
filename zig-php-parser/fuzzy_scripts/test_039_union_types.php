<?php
// 联合类型测试 (PHP 8.0+)

// 基础联合类型
function process(int|float $number): int|float {
    return $number * 2;
}

echo "int result: " . process(5) . "\n";
echo "float result: " . process(3.14) . "\n";

// 多类型联合
function format(int|float|string $value): string {
    return match(true) {
        is_int($value) => "Integer: $value",
        is_float($value) => "Float: $value",
        is_string($value) => "String: $value"
    };
}

echo format(42) . "\n";
echo format(3.14) . "\n";
echo format("hello") . "\n";

// 可空联合类型
function find(?int $id): ?string {
    if ($id === null) return null;
    return "Item $id";
}

echo "found: " . var_export(find(1), true) . "\n";
echo "null: " . var_export(find(null), true) . "\n";

// 类类型联合
class A { public function getName(): string { return 'A'; } }
class B { public function getName(): string { return 'B'; } }

function handle(A|B $obj): string {
    return $obj->getName();
}

echo "handle A: " . handle(new A()) . "\n";
echo "handle B: " . handle(new B()) . "\n";

// 接口联合
interface Writer { public function write(string $data): void; }
interface Reader { public function read(): string; }

class FileHandler implements Writer, Reader {
    private string $data = '';
    public function write(string $data): void { $this->data = $data; }
    public function read(): string { return $this->data; }
}

class MemoryHandler implements Writer, Reader {
    private string $buffer = '';
    public function write(string $data): void { $this->buffer = $data; }
    public function read(): string { return $this->buffer; }
}

function processHandler(Writer&Reader $handler): string {
    $handler->write('test data');
    return $handler->read();
}

echo "process FileHandler: " . processHandler(new FileHandler()) . "\n";
echo "process MemoryHandler: " . processHandler(new MemoryHandler()) . "\n";

// 返回联合类型
function getValue(bool $asString): int|string {
    return $asString ? '42' : 42;
}

echo "int return: " . gettype(getValue(false)) . "\n";
echo "string return: " . gettype(getValue(true)) . "\n";

// 属性联合类型
class Container {
    public int|string $id;

    public function __construct(int|string $id) {
        $this->id = $id;
    }
}

$c1 = new Container(1);
$c2 = new Container('abc');
echo "int id: " . $c1->id . "\n";
echo "string id: " . $c2->id . "\n";

// 复杂联合类型
function complex(
    array|bool|float|int|string|null $value
): string {
    return match(true) {
        is_array($value) => 'array',
        is_bool($value) => 'bool',
        is_float($value) => 'float',
        is_int($value) => 'int',
        is_string($value) => 'string',
        is_null($value) => 'null'
    };
}

echo "complex array: " . complex([1, 2]) . "\n";
echo "complex bool: " . complex(true) . "\n";
echo "complex null: " . complex(null) . "\n";

// static返回类型
abstract class BaseFactory {
    public static function create(): static {
        return new static();
    }
}

class ConcreteFactory extends BaseFactory {
    public function getType(): string {
        return 'Concrete';
    }
}

$factory = ConcreteFactory::create();
echo "Factory type: " . $factory->getType() . "\n";

// 混合类型
function mixedParam(mixed $value): mixed {
    return $value;
}

echo "mixed int: " . mixedParam(42) . "\n";
echo "mixed array: " . var_export(mixedParam([1, 2, 3]), true) . "\n";

echo "Union types tests completed\n";
