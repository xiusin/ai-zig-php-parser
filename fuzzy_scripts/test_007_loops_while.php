<?php
// while和do-while循环测试

// 基础while
echo "基础while:\n";
$i = 0;
while ($i < 5) {
    echo $i . " ";
    $i++;
}
echo "\n";

// while替代语法
echo "while替代语法:\n";
$j = 0;
while ($j < 3):
    echo "item$j\n";
    $j++;
endwhile;

// 带break的while
echo "while+break:\n";
$k = 0;
while (true) {
    echo $k . " ";
    $k++;
    if ($k >= 4) break;
}
echo "\n";

// 带continue的while
echo "while+continue:\n";
$m = 0;
while ($m < 10) {
    $m++;
    if ($m % 2 === 0) continue;
    echo $m . " ";
}
echo "\n";

// 嵌套while
echo "嵌套while:\n";
$row = 1;
while ($row <= 3) {
    $col = 1;
    while ($col <= 3) {
        echo ($row * $col) . " ";
        $col++;
    }
    echo "\n";
    $row++;
}

// do-while基础
echo "do-while:\n";
$n = 0;
do {
    echo $n . " ";
    $n++;
} while ($n < 5);
echo "\n";

// do-while至少执行一次
echo "do-while至少执行一次:\n";
$x = 100;
do {
    echo "executed once\n";
} while ($x < 10);

// 复杂条件while
echo "复杂条件:\n";
$sum = 0;
$count = 1;
while ($sum < 50 && $count <= 20) {
    $sum += $count;
    echo "count=$count, sum=$sum\n";
    $count++;
}

// while中的函数调用
function isDone($val) { return $val >= 3; }
echo "函数条件:\n";
$val = 0;
while (!isDone($val)) {
    echo "val=$val\n";
    $val++;
}

// 空while
echo "空while:\n";
$empty = 0;
while ($empty < 3):
    $empty++;
endwhile;
echo "done\n";

// break嵌套层级
echo "break层级:\n";
$a = 0;
while ($a < 3) {
    $b = 0;
    while ($b < 3) {
        if ($a === 1 && $b === 1) {
            break 2;
        }
        echo "($a,$b) ";
        $b++;
    }
    $a++;
}
echo "\n";
