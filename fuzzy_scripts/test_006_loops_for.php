<?php
// for循环测试

// 基础for循环
echo "基础循环:\n";
for ($i = 0; $i < 5; $i++) {
    echo $i . " ";
}
echo "\n";

// 多变量for循环
echo "多变量:\n";
for ($i = 0, $j = 10; $i < 5 && $j > 5; $i++, $j--) {
    echo "i=$i, j=$j\n";
}

// 无限循环+break
echo "break测试:\n";
$count = 0;
for (;;) {
    echo $count . " ";
    $count++;
    if ($count >= 5) break;
}
echo "\n";

// continue测试
echo "continue测试:\n";
for ($i = 0; $i < 10; $i++) {
    if ($i % 2 === 0) continue;
    echo $i . " ";
}
echo "\n";

// 嵌套for循环
echo "嵌套循环:\n";
for ($i = 1; $i <= 3; $i++) {
    for ($j = 1; $j <= 3; $j++) {
        echo ($i * $j) . " ";
    }
    echo "\n";
}

// 替代语法
echo "替代语法:\n";
for ($i = 0; $i < 3; $i++):
    echo "item$i\n";
endfor;

// 复杂表达式
echo "复杂表达式:\n";
$arr = [10, 20, 30, 40, 50];
for ($i = 0, $len = count($arr); $i < $len; $i++):
    echo "arr[$i]=" . $arr[$i] . "\n";
endfor;

// for循环中的函数调用
function getLimit() { return 3; }
echo "函数调用:\n";
for ($i = 0; $i < getLimit(); $i++) {
    echo "iteration $i\n";
}

// 省略部分表达式
echo "省略初始化:\n";
$k = 0;
for (; $k < 3; $k++) {
    echo $k . " ";
}
echo "\n";

echo "省略条件:\n";
for ($m = 0;; $m++) {
    if ($m >= 3) break;
    echo $m . " ";
}
echo "\n";

echo "省略递增:\n";
for ($n = 3; $n > 0;) {
    echo $n . " ";
    $n--;
}
echo "\n";

// 空for
echo "空for体:\n";
for ($i = 0; $i < 3; $i++);
echo "done\n";

// 双重break
echo "双重break:\n";
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j === 2) break 2;
        echo "($i,$j) ";
    }
}
echo "\n";
