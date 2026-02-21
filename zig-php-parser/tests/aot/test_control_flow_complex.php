<?php
// 测试：控制流 + 异常处理 + 复杂逻辑
function divide($a, $b) {
    if ($b == 0) {
        return null;
    }
    return $a / $b;
}

function process_numbers($numbers) {
    $results = [];
    foreach ($numbers as $num) {
        if ($num < 0) {
            continue;
        }
        if ($num > 100) {
            break;
        }
        
        $result = 0;
        if ($num % 2 == 0) {
            $result = $num * 2;
        } else {
            $result = $num * 3 + 1;
        }
        $results[] = $result;
    }
    return $results;
}

$input = [5, 10, -3, 15, 20, 25, 30, 150, 35];
echo "Input: ";
foreach ($input as $n) {
    echo $n . " ";
}
echo "\n";

$output = process_numbers($input);
echo "Output: ";
foreach ($output as $n) {
    echo $n . " ";
}
echo "\n";

// 测试除法
echo "\nDivision tests:\n";
$pairs = [[10, 2], [15, 3], [20, 0], [7, 2]];
foreach ($pairs as $pair) {
    $a = $pair[0];
    $b = $pair[1];
    $result = divide($a, $b);
    if ($result === null) {
        echo "$a / $b = ERROR (division by zero)\n";
    } else {
        echo "$a / $b = $result\n";
    }
}
