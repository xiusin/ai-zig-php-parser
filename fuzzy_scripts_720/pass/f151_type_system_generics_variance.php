<?php
// 类型系统深入：泛型模拟、协变逆变、类型推断、联合类型、交集类型
echo "=== f151: Type System + Generics + Variance + Inference ===\n";

// 协变返回类型
interface Animal { public function speak(): string; }
class Dog implements Animal { public function speak(): string { return 'Woof'; } }
class Cat implements Animal { public function speak(): string { return 'Meow'; } }

abstract class AnimalShelter {
    abstract public function adopt(): Animal;
}
class DogShelter extends AnimalShelter {
    public function adopt(): Animal { return new Dog(); } // 协变返回
}
class CatShelter extends AnimalShelter {
    public function adopt(): Animal { return new Cat(); }
}

// 逆变参数类型
interface Handler {
    public function handle(Animal $animal): string;
}
class SpecificHandler implements Handler {
    public function handle(Animal $animal): string {
        return 'Handled: ' . $animal->speak();
    }
}

// 泛型容器模拟
class Container {
    private array $items = [];
    private string $type;

    public function __construct(string $type) { $this->type = $type; }

    public function add(mixed $item): self {
        $actualType = match(true) {
            is_int($item) => 'int',
            is_float($item) => 'float',
            is_string($item) => 'string',
            is_bool($item) => 'bool',
            is_array($item) => 'array',
            is_object($item) => get_class($item),
            default => gettype($item),
        };
        if ($actualType !== $this->type && !($item instanceof $this->type)) {
            throw new InvalidArgumentException("Expected {$this->type}, got $actualType");
        }
        $this->items[] = $item;
        return $this;
    }

    public function map(callable $fn): array {
        return array_map($fn, $this->items);
    }

    public function filter(callable $fn): array {
        return array_filter($this->items, $fn);
    }

    public function reduce(callable $fn, mixed $initial = null): mixed {
        return array_reduce($this->items, $fn, $initial);
    }

    public function first(): mixed { return $this->items[0] ?? null; }
    public function last(): mixed { return end($this->items) ?: null; }
    public function count(): int { return count($this->items); }
    public function toArray(): array { return $this->items; }
}

// 联合类型处理
function processValue(int|float|string $value): string {
    return match(true) {
        is_int($value) => "int: $value (hex: " . dechex($value) . ")",
        is_float($value) => "float: $value (rounded: " . round($value) . ")",
        is_string($value) => "string: '$value' (len: " . strlen($value) . ")",
    };
}

// 测试
echo "--- Covariant Return ---\n";
$dogShelter = new DogShelter();
$catShelter = new CatShelter();
echo "  Dog shelter: " . $dogShelter->adopt()->speak() . "\n";
echo "  Cat shelter: " . $catShelter->adopt()->speak() . "\n";

echo "\n--- Contravariant Parameter ---\n";
$handler = new SpecificHandler();
echo "  " . $handler->handle(new Dog()) . "\n";
echo "  " . $handler->handle(new Cat()) . "\n";

echo "\n--- Generic Container ---\n";
$intContainer = new Container('int');
$intContainer->add(1)->add(2)->add(3)->add(4)->add(5);
echo "  Count: " . $intContainer->count() . "\n";
echo "  First: " . $intContainer->first() . "\n";
echo "  Last: " . $intContainer->last() . "\n";
echo "  Sum: " . $intContainer->reduce(fn($c, $i) => $c + $i, 0) . "\n";
echo "  Doubled: " . implode(', ', $intContainer->map(fn($i) => $i * 2)) . "\n";
echo "  Evens: " . implode(', ', $intContainer->filter(fn($i) => $i % 2 === 0)) . "\n";

$stringContainer = new Container('string');
$stringContainer->add('hello')->add('world')->add('foo')->add('bar');
echo "  Joined: " . $stringContainer->reduce(fn($c, $s) => $c . ' ' . $s, '') . "\n";
echo "  Upper: " . implode(', ', $stringContainer->map(fn($s) => strtoupper($s))) . "\n";
echo "  Long: " . implode(', ', $stringContainer->filter(fn($s) => strlen($s) > 3)) . "\n";

echo "\n--- Union Type Processing ---\n";
echo "  " . processValue(42) . "\n";
echo "  " . processValue(3.14159) . "\n";
echo "  " . processValue('hello') . "\n";
echo "  " . processValue(255) . "\n";

echo "\n--- Type Inference ---\n";
$data = [1, 2, 3, 4, 5];
$sum = array_reduce($data, fn($c, $i) => $c + $i, 0);
$avg = $sum / count($data);
echo "  Sum: $sum, Avg: $avg\n";

$strings = ['apple', 'banana', 'cherry'];
$lengths = array_map(fn($s) => strlen($s), $strings);
echo "  Lengths: " . implode(', ', $lengths) . "\n";
$total = array_sum($lengths);
echo "  Total chars: $total\n";

echo "=== f151 Done ===\n";
