<?php
// 控制流边界测试

// 嵌套循环中的break和continue
echo "=== Nested break/continue ===\n";
for ($i = 1; $i <= 3; $i++) {
    for ($j = 1; $j <= 3; $j++) {
        if ($i === 2 && $j === 2) {
            continue 2; // 跳到外层循环的下一次迭代
        }
        echo "($i,$j) ";
    }
    echo "\n";
}

// goto测试
echo "\n=== goto test ===\n";
$x = 1;
start:
echo "x=$x\n";
$x++;
if ($x <= 3) {
    goto start;
}
echo "After goto\n";

// 标签和goto向前跳
echo "\n=== forward goto ===\n";
$y = 10;
if ($y > 5) {
    goto skip;
}
echo "This will be skipped\n";
skip:
echo "Skipped to here, y=$y\n";

// 复杂嵌套
echo "\n=== Complex nesting ===\n";
$result = [];
for ($i = 0; $i < 5; $i++) {
    switch ($i) {
        case 0:
            $result[] = "zero";
            break;
        case 1:
            $result[] = "one";
            continue 2; // 继续for循环
        case 2:
            $result[] = "two";
            break;
        default:
            $result[] = "other";
    }
    $result[] = "after switch $i";
}
echo "Result: " . implode(', ', $result) . "\n";

// 匹配表达式在循环中
echo "\n=== match in loop ===\n";
for ($i = 0; $i < 5; $i++) {
    $status = match($i % 3) {
        0 => 'divisible by 3',
        1 => 'remainder 1',
        2 => 'remainder 2'
    };
    echo "$i: $status\n";
}

// 异常控制流
echo "\n=== Exception control flow ===\n";
function exceptionLoop(): int {
    for ($i = 0; $i < 10; $i++) {
        try {
            if ($i === 5) {
                throw new Exception("Five!");
            }
        } catch (Exception $e) {
            return $i;
        }
    }
    return -1;
}
echo "Exception loop result: " . exceptionLoop() . "\n";

// yield控制流
echo "\n=== Yield control ===\n";
function yieldingRange(int $start, int $end) {
    for ($i = $start; $i <= $end; $i++) {
        if ($i % 2 === 0) {
            yield $i;
        }
    }
}
$evens = iterator_to_array(yieldingRange(1, 10));
echo "Even numbers: " . implode(', ', $evens) . "\n";

// 条件中的短路
echo "\n=== Short circuit ===\n";
$called = false;
$result = false && ($called = true);
echo "Called in false &&: " . var_export($called, true) . "\n";

$called = false;
$result = true || ($called = true);
echo "Called in true ||: " . var_export($called, true) . "\n";

// 三元运算符链
echo "\n=== Ternary chain ===\n";
$value = 85;
$category = $value >= 90 ? 'A' :
            ($value >= 80 ? 'B' :
            ($value >= 70 ? 'C' :
            ($value >= 60 ? 'D' : 'F')));
echo "Category for $value: $category\n";

// 空合并链
echo "\n=== Null coalesce chain ===\n";
$a = null;
$b = null;
$c = 'found';
$d = 'backup';
echo "Coalesce result: " . ($a ?? $b ?? $c ?? $d) . "\n";

echo "\nControl flow tests completed\n";
