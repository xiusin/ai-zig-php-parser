<?php
// Test 039: Variable functions, func_get_args, callable invocations
class VariableFuncLab {
    public function sum(int ...$args): int {
        return array_sum($args);
    }

    public function concat(string ...$args): string {
        return implode('', $args);
    }

    public function process(): string {
        $out = "";

        $fn = 'strlen';
        $out .= "$fn('hello'): " . $fn('hello') . "\n";

        $fn = 'strtoupper';
        $out .= "$fn('hello'): " . $fn('hello') . "\n";

        $fn = 'array_sum';
        $out .= "$fn([1,2,3,4,5]): " . $fn([1, 2, 3, 4, 5]) . "\n";

        return $out;
    }

    public function dynamicMethodCall(string $method, ...$args): mixed {
        return $this->$method(...$args);
    }
}

function add(int $a, int $b): int {
    return $a + $b;
}

function multiply(int $a, int $b): int {
    return $a * $b;
}

function greet(string $name, string $greeting = 'Hello'): string {
    return "$greeting, $name!";
}

echo "=== Variable functions ===\n";
$lab = new VariableFuncLab();
echo $lab->process();

echo "\n=== Dynamic method calls ===\n";
echo "sum(1,2,3,4,5): " . $lab->dynamicMethodCall('sum', 1, 2, 3, 4, 5) . "\n";
echo "concat('a','b','c'): " . $lab->dynamicMethodCall('concat', 'a', 'b', 'c') . "\n";

echo "\n=== Callable variable assignment ===\n";
$func = 'add';
echo "add(5, 3) via \$func: " . $func(5, 3) . "\n";

$func = 'multiply';
echo "multiply(5, 3) via \$func: " . $func(5, 3) . "\n";

echo "\n=== is_callable checks ===\n";
echo "is_callable('strlen'): " . (is_callable('strlen') ? 'yes' : 'no') . "\n";
echo "is_callable('non_existent'): " . (is_callable('non_existent') ? 'yes' : 'no') . "\n";

class CallableClass {
    public function __invoke(int $x): int {
        return $x * 2;
    }
}

$obj = new CallableClass();
echo "is_callable(\$obj): " . (is_callable($obj) ? 'yes' : 'no') . "\n";
echo "\$obj(21): " . $obj(21) . "\n";

echo "\n=== Call user func array ===\n";
echo "call_user_func('strtoupper', 'hello'): " . call_user_func('strtoupper', 'hello') . "\n";
echo "call_user_func_array('add', [10, 20]): " . call_user_func_array('add', [10, 20]) . "\n";
echo "call_user_func_array(\$lab->dynamicMethodCall('sum'), [1,2,3]): " . call_user_func_array([$lab, 'dynamicMethodCall'], ['sum', 1, 2, 3]) . "\n";

echo "\n=== ReflectionFunction ===\n";
$rf = new ReflectionFunction('greet');
echo "Function name: " . $rf->getName() . "\n";
echo "Number of parameters: " . $rf->getNumberOfParameters() . "\n";
echo "Is closure: " . ($rf->isClosure() ? 'yes' : 'no') . "\n";
echo "Invoke greet: " . $rf->invoke('World') . "\n";