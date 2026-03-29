<?php
// Test 003: Closure, callback, and first-class callable tests
class CallbackTest {
    public array $triggers = [];

    public function register(string $event, callable $callback): void {
        $this->triggers[$event] = $callback;
    }

    public function trigger(string $event, mixed ...$args): mixed {
        if (isset($this->triggers[$event])) {
            return ($this->triggers[$event])(...$args);
        }
        return null;
    }
}

function outer(int $x): Closure {
    $captured = $x * 2;
    return function(int $y) use ($captured): int {
        return $captured + $y + 1;
    };
}

$cb = new CallbackTest;

// Test closures
$double = fn(int $x): int => $x * 2;
$add_ten = function(int $x): int { return $x + 10; };

$cb->register('numeric', $double);
$cb->register('add', $add_ten);
$cb->register('closure_factory', outer(...)); // First-class callable

echo "Double(5): " . $cb->trigger('numeric', 5) . "\n";
echo "Add(5): " . $cb->trigger('add', 5) . "\n";
echo "Outer(3)(7): " . $cb->trigger('closure_factory', 3, 7) . "\n";

// Test arrow functions
$arr = [1, 2, 3, 4, 5];
$doubled = array_map(fn($x) => $x * 2, $arr);
echo "Doubled: " . implode(',', $doubled) . "\n";

// Test array_filter with closure
$evens = array_filter($arr, fn($x) => $x % 2 === 0);
echo "Evens: " . implode(',', $evens) . "\n";

// Test array_reduce with closure
$sum = array_reduce($arr, fn($carry, $item) => $carry + $item, 0);
echo "Sum: $sum\n";

// Test usort with closure
$sorted = [3, 1, 4, 1, 5, 9, 2, 6];
usort($sorted, fn($a, $b) => $a <=> $b);
echo "Sorted: " . implode(',', $sorted) . "\n";

// Test anonymous class
$processor = new class {
    public function process(): string {
        return "Processed by anonymous";
    }
};
echo "Anonymous: " . $processor->process() . "\n";

// Test callable types
class TypeChecker {
    public function callWithCallback(callable $cb, mixed ...$args): mixed {
        return $cb(...$args);
    }
}

$tc = new TypeChecker;
echo "Callback result: " . $tc->callWithCallback(fn($x, $y) => $x + $y, 3, 4) . "\n";