<?php
// Test 032: Type declarations, union types, and intersection types
class TypeLab {
    public function unionTypes(int|string|float $value): string {
        return match(true) {
            is_int($value) => "int: $value",
            is_string($value) => "string: $value",
            is_float($value) => "float: $value",
        };
    }

    public function intersectionTypes(Countable&Traversable $value): int {
        return count($value);
    }

    public function nullableTypes(?string $value): string {
        return $value ?? 'was null';
    }

    public function mixedTypes(mixed $value): string {
        return gettype($value) . ": " . var_export($value, true);
    }

    public function staticType(): static {
        return new static();
    }

    public function selfType(): self {
        return new self();
    }

    public function returnTypeUnion(): int|string {
        return (random_int(0, 1) === 0) ? 42 : 'forty-two';
    }

    public function voidMethod(): void {
        echo "Void method called\n";
    }

    public function neverMethod(): void {
        throw new RuntimeException("This method never returns");
    }

    public function nullableReturn(): ?string {
        return random_int(0, 1) === 0 ? null : 'returned';
    }
}

interface Countable {
    public function count(): int;
}

interface Traversable {
    public function getIterator(): Iterator;
}

class CountableTraversableImpl implements Countable, Traversable {
    private array $data;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function count(): int {
        return count($this->data);
    }

    public function getIterator(): Iterator {
        return new ArrayIterator($this->data);
    }
}

echo "=== Union types ===\n";
$lab = new TypeLab();
echo $lab->unionTypes(42) . "\n";
echo $lab->unionTypes('hello') . "\n";
echo $lab->unionTypes(3.14) . "\n";

echo "\n=== Intersection types ===\n";
$ct = new CountableTraversableImpl([1, 2, 3, 4, 5]);
try {
    $count = $lab->intersectionTypes($ct);
    echo "Intersection type count: $count\n";
} catch (TypeError $e) {
    echo "TypeError: " . $e->getMessage() . "\n";
}

echo "\n=== Nullable types ===\n";
echo "With value: " . $lab->nullableTypes('test') . "\n";
echo "With null: " . $lab->nullableTypes(null) . "\n";

echo "\n=== Mixed types ===\n";
echo $lab->mixedTypes(123) . "\n";
echo $lab->mixedTypes('string') . "\n";
echo $lab->mixedTypes([1, 2, 3]) . "\n";
echo $lab->mixedTypes(null) . "\n";

echo "\n=== Static and self types ===\n";
$static = $lab->staticType();
echo "Static type class: " . get_class($static) . "\n";
$self = $lab->selfType();
echo "Self type class: " . get_class($self) . "\n";

echo "\n=== Return type union ===\n";
$result = $lab->returnTypeUnion();
echo "Return type: " . gettype($result) . ", value: $result\n";

echo "\n=== Void method ===\n";
$lab->voidMethod();

echo "\n=== Nullable return ===\n";
for ($i = 0; $i < 3; $i++) {
    $result = $lab->nullableReturn();
    echo "Nullable return: " . ($result ?? 'null') . "\n";
}