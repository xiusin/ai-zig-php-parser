<?php
// 测试77: 函数重载模拟（PHP不支持真正的函数重载）
// 使用func_get_args和类型检查模拟

function overloaded() {
    $args = func_get_args();
    $count = count($args);
    
    if ($count === 0) {
        return "No arguments";
    } elseif ($count === 1 && is_int($args[0])) {
        return "Single int: " . $args[0];
    } elseif ($count === 1 && is_string($args[0])) {
        return "Single string: " . $args[0];
    } elseif ($count === 2) {
        return "Two arguments: " . implode(", ", $args);
    } else {
        return "Multiple arguments ($count): " . json_encode($args);
    }
}

echo overloaded() . "
";
echo overloaded(42) . "
";
echo overloaded("hello") . "
";
echo overloaded(1, 2) . "
";
echo overloaded(1, 2, 3, 4) . "
";

// 使用可变参数模拟重载
class Calculator {
    public function add(...$numbers): int|float {
        return array_sum($numbers);
    }
    
    public function multiply(...$numbers): int|float {
        return array_reduce($numbers, fn($a, $b) => $a * $b, 1);
    }
}

$calc = new Calculator();
echo "Add: " . $calc->add(1, 2, 3, 4, 5) . "
";
echo "Multiply: " . $calc->multiply(2, 3, 4) . "
";

// 类型重载模拟
function process($input) {
    return match(true) {
        is_int($input) => $input * 2,
        is_string($input) => strtoupper($input),
        is_array($input) => array_map('process', $input),
        is_object($input) => get_class($input),
        default => "unknown",
    };
}

echo process(10) . "
";
echo process("test") . "
";
echo process([1, 2, 3]) . "
";
echo process(new stdClass()) . "
";
?>