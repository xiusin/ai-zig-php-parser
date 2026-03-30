<?php
// 测试60: PHP 8.0 mixed类型 - 接受任意类型的类型声明
// 测试目的：验证mixed类型的行为和与其他类型的关系

class UniversalContainer {
    private array $items = [];
    
    public function add(mixed $item): void {
        $this->items[] = $item;
    }
    
    public function get(int $index): mixed {
        return $this->items[$index] ?? null;
    }
    
    public function all(): array {
        return $this->items;
    }
    
    public function process(mixed $input): string {
        return match(true) {
            is_null($input) => "null value",
            is_bool($input) => "boolean: " . ($input ? 'true' : 'false'),
            is_int($input) => "integer: $input",
            is_float($input) => "float: $input",
            is_string($input) => "string: '$input'",
            is_array($input) => "array with " . count($input) . " elements",
            is_object($input) => "object of class " . get_class($input),
            is_callable($input) => "callable",
            default => "unknown type",
        };
    }
}

$container = new UniversalContainer();

// 存储各种类型的数据
$container->add(null);
$container->add(true);
$container->add(42);
$container->add(3.14);
$container->add("hello");
$container->add([1, 2, 3]);
$container->add(new stdClass());
$container->add(fn($x) => $x * 2);

echo "Stored items:\n";
foreach ($container->all() as $i => $item) {
    echo "  $i: " . $container->process($item) . "\n";
}

// mixed作为返回类型
function fetchData(string $source): mixed {
    return match($source) {
        'config' => ['debug' => true, 'env' => 'prod'],
        'count' => 42,
        'name' => 'Application',
        'active' => true,
        default => null,
    };
}

echo "\nFetched data:\n";
echo "config: " . gettype(fetchData('config')) . "\n";
echo "count: " . gettype(fetchData('count')) . "\n";
echo "name: " . gettype(fetchData('name')) . "\n";
echo "active: " . gettype(fetchData('active')) . "\n";

// 可空mixed
function maybeTransform(?mixed $input, callable $transform): mixed {
    if ($input === null) {
        return null;
    }
    return $transform($input);
}

$result1 = maybeTransform(5, fn($x) => $x * 2);
$result2 = maybeTransform(null, fn($x) => $x * 2);
echo "\nTransform 5: $result1\n";
echo "Transform null: " . ($result2 === null ? 'null' : $result2) . "\n";

// mixed vs union类型
class TypeComparator {
    public function acceptsMixed(mixed $value): void {
        echo "Mixed accepts: " . gettype($value) . "\n";
    }
    
    public function acceptsUnion(string|int|float $value): void {
        echo "Union accepts: $value\n";
    }
}

$comparator = new TypeComparator();
$comparator->acceptsMixed([1, 2, 3]);
$comparator->acceptsMixed(new stdClass());
$comparator->acceptsUnion(42);
// $comparator->acceptsUnion([1, 2, 3]); // TypeError

// 使用mixed实现通用比较器
function compareMixed(mixed $a, mixed $b): int {
    if (gettype($a) !== gettype($b)) {
        return strcmp(gettype($a), gettype($b));
    }
    return match(true) {
        is_int($a) || is_float($a) => $a <=> $b,
        is_string($a) => strcmp($a, $b),
        is_array($a) => count($a) <=> count($b),
        default => 0,
    };
}

echo "\nComparisons:\n";
echo "5 <=> 10: " . compareMixed(5, 10) . "\n";
echo "'a' <=> 'b': " . compareMixed('a', 'b') . "\n";
echo "[1,2] <=> [1,2,3]: " . compareMixed([1, 2], [1, 2, 3]) . "\n";
?>
