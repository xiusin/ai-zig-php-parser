<?php
// 测试：类型判断和转换
$values = [42, 3.14, "hello", true, null, [1, 2, 3]];

echo "Type checking:\n";
$i = 0;
while ($i < count($values)) {
    $val = $values[$i];
    echo "Value $i: ";
    
    if (is_int($val)) {
        echo "int($val)";
    } else if (is_float($val)) {
        echo "float($val)";
    } else if (is_string($val)) {
        echo "string('$val')";
    } else if (is_bool($val)) {
        echo "bool(" . ($val ? "true" : "false") . ")";
    } else if (is_null($val)) {
        echo "null";
    } else if (is_array($val)) {
        echo "array[" . count($val) . "]";
    }
    echo "\n";
    $i++;
}

// 类型转换
echo "\nType casting:\n";
$num = 42;
$str = (string)$num;
echo "int $num -> string '$str'\n";

$str = "123";
$num = (int)$str;
echo "string '$str' -> int $num\n";

$float = 3.14;
$int = (int)$float;
echo "float $float -> int $int\n";

// 布尔转换
$truthy = 1;
$falsy = 0;
echo "bool(1): " . ($truthy ? "true" : "false") . "\n";
echo "bool(0): " . ($falsy ? "true" : "false") . "\n";
