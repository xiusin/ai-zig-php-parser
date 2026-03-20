<?php
// Test 025: First-class callable, callable expressions, and first-class callables
class CallableLab {
    public function add(int $a, int $b): int {
        return $a + $b;
    }

    public function multiply(int $a, int $b): int {
        return $a * $b;
    }

    public function process(callable $fn, array $args): mixed {
        return $fn(...$args);
    }

    public function getOperation(string $op): callable {
        return match($op) {
            'add' => CallableLab::add(...),
            'multiply' => CallableLab::multiply(...),
            default => fn($a, $b) => $a - $b,
        };
    }
}

echo "=== First-class callable syntax ===\n";
$lab = new CallableLab();

// Using ... (callable extraction)
$add = CallableLab::add(...);
$multiply = CallableLab::multiply(...);

echo "add(5, 3): " . $add(5, 3) . "\n";
echo "multiply(5, 3): " . $multiply(5, 3) . "\n";

echo "\n=== Callable in array ===\n";
$operations = [
    'add' => CallableLab::add(...),
    'multiply' => CallableLab::multiply(...),
    'subtract' => fn(int $a, int $b) => $a - $b,
];

foreach ($operations as $name => $op) {
    echo "$name(10, 4): " . $op(10, 4) . "\n";
}

echo "\n=== Callable extraction from instance ===\n";
$process = CallableLab::process(...);
echo "process(add, [5, 3]): " . $process($lab->add(...), [5, 3]) . "\n";
echo "process(multiply, [5, 3]): " . $process($lab->multiply(...), [5, 3]) . "\n";

echo "\n=== Dynamic callable selection ===\n";
$addFn = $lab->getOperation('add');
$multiplyFn = $lab->getOperation('multiply');
$subtractFn = $lab->getOperation('subtract');

echo "add(100, 200): " . $addFn(100, 200) . "\n";
echo "multiply(100, 200): " . $multiplyFn(100, 200) . "\n";
echo "subtract(100, 200): " . $subtractFn(100, 200) . "\n";

echo "\n=== Callable stored in variable ===\n";
$fn = match (true) {
    true => CallableLab::add(...),
    false => CallableLab::multiply(...),
};
echo "fn(7, 8): " . $fn(7, 8) . "\n";

echo "\n=== Callable in array_map with first-class ===\n";
$numbers = [1, 2, 3, 4, 5];
$doubled = array_map(fn($x) => $x * 2, $numbers);
echo "Doubled: " . implode(',', $doubled) . "\n";

$objects = array_map(fn($x) => (object)['value' => $x], $numbers);
echo "Objects created: " . count($objects) . "\n";

echo "\n=== Closure with callable extraction ===\n";
function createMultiplier(int $factor): callable {
    return fn(int $x) => $x * $factor;
}

$double = createMultiplier(2);
$triple = createMultiplier(3);

echo "double(10): " . $double(10) . "\n";
echo "triple(10): " . $triple(10) . "\n";

echo "\n=== Callable type hints ===\n";
function execute(callable $fn, int $a, int $b): int {
    return $fn($a, $b);
}

echo "execute(add, 6, 9): " . execute(CallableLab::add(...), 6, 9) . "\n";
echo "execute(multiply, 6, 9): " . execute(CallableLab::multiply(...), 6, 9) . "\n";

echo "\n=== Testing with nullsafe and dynamic methods ===\n";
class MethodHolder {
    public function one(): string { return "one"; }
    public function two(int $x): int { return $x * 2; }
}

$holder = new MethodHolder();
$method1 = MethodHolder::one(...);
echo "MethodHolder::one()(holder): " . $method1($holder) . "\n";

$method2 = MethodHolder::two(...);
echo "MethodHolder::two()(holder, 21): " . $method2($holder, 21) . "\n";