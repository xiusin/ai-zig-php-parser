<?php
// Advanced closures and higher-order functions
class ArrayUtils {
    public static function map(array $array, callable $callback): array {
        return array_map($callback, $array);
    }
    
    public static function filter(array $array, callable $callback): array {
        return array_filter($array, $callback);
    }
    
    public static function reduce(array $array, callable $callback, $initial = null) {
        return array_reduce($array, $callback, $initial);
    }
    
    public static function each(array $array, callable $callback): void {
        foreach ($array as $key => $value) {
            $callback($value, $key);
        }
    }
    
    public static function find(array $array, callable $callback) {
        foreach ($array as $value) {
            if ($callback($value)) {
                return $value;
            }
        }
        return null;
    }
    
    public static function every(array $array, callable $callback): bool {
        foreach ($array as $value) {
            if (!$callback($value)) {
                return false;
            }
        }
        return true;
    }
    
    public static function some(array $array, callable $callback): bool {
        foreach ($array as $value) {
            if ($callback($value)) {
                return true;
            }
        }
        return false;
    }
    
    public static function partition(array $array, callable $callback): array {
        $true = [];
        $false = [];
        
        foreach ($array as $value) {
            if ($callback($value)) {
                $true[] = $value;
            } else {
                $false[] = $value;
            }
        }
        
        return [$true, $false];
    }
}

class Pipeline {
    private $stages = [];
    
    public function pipe(callable $stage): self {
        $this->stages[] = $stage;
        return $this;
    }
    
    public function process($data) {
        foreach ($this->stages as $stage) {
            $data = $stage($data);
        }
        return $data;
    }
    
    public function reset(): self {
        $this->stages = [];
        return $this;
    }
}

class Memoizer {
    private $cache = [];
    
    public function memoize(callable $func): callable {
        return function(...$args) use ($func) {
            $key = serialize($args);
            
            if (!isset($this->cache[$key])) {
                $this->cache[$key] = $func(...$args);
            }
            
            return $this->cache[$key];
        };
    }
    
    public function clear(): void {
        $this->cache = [];
    }
}

class Curry {
    public static function curry(callable $func): callable {
        return function(...$args) use ($func) {
            $required = (new ReflectionFunction($func))->getNumberOfRequiredParameters();
            
            if (count($args) >= $required) {
                return $func(...$args);
            }
            
            return fn(...$more) => $func(...$args, ...$more);
        };
    }
}

// Test advanced closures
echo "=== Advanced Closures Testing ===\n";

$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

echo "Original: " . implode(', ', $numbers) . "\n";

// Map
$squared = ArrayUtils::map($numbers, fn($n) => $n * $n);
echo "Squared: " . implode(', ', $squared) . "\n";

// Filter
$evens = ArrayUtils::filter($numbers, fn($n) => $n % 2 == 0);
echo "Evens: " . implode(', ', $evens) . "\n";

// Reduce
$sum = ArrayUtils::reduce($numbers, fn($carry, $n) => $carry + $n, 0);
echo "Sum: {$sum}\n";

// Find
$found = ArrayUtils::find($numbers, fn($n) => $n > 5);
echo "First > 5: {$found}\n";

// Every
$allPositive = ArrayUtils::every($numbers, fn($n) => $n > 0);
echo "All positive? " . ($allPositive ? "Yes" : "No") . "\n";

// Some
$hasEven = ArrayUtils::some($numbers, fn($n) => $n % 2 == 0);
echo "Has even? " . ($hasEven ? "yes" : "no") . "\n";

// Partition
[$positives, $negatives] = ArrayUtils::partition($numbers, fn($n) => $n > 0);
echo "Positives: " . implode(', ', $positives) . "\n";

// Pipeline
$result = (new Pipeline())
    ->pipe(fn($text) => trim($text))
    ->pipe(fn($text) => strtoupper($text))
    ->pipe(fn($text) => str_replace(' ', '_', $text))
    ->process("  hello world  ");

echo "Pipeline result: {$result}\n";

// Memoizer
$memoizer = new Memoizer();
$fibonacci = $memoizer->memoize(function($n) use (&$fibonacci) {
    if ($n <= 1) return $n;
    return $fibonacci($n - 1) + $fibonacci($n - 2);
});

echo "Fibonacci(10): {$fibonacci(10)}\n";
echo "Fibonacci(10) again: {$fibonacci(10)}\n";

// Currying
$add = fn($a, $b, $c) => $a + $b + $c;
$curriedAdd = Curry::curry($add);

$add5 = $curriedAdd(5);
$add5and3 = $add5(3);
echo "5 + 3 + 2 = {$add5and3(2)}\n";

echo "\nDone\n";