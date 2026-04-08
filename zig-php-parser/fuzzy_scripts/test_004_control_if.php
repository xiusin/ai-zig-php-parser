<?php
// if/elseif/else 控制结构测试

// 基础if
$a = 10;
if ($a > 5) {
    echo "a大于5\n";
}

// if-else
$b = 3;
if ($b > 5) {
    echo "b大于5\n";
} else {
    echo "b不大于5\n";
}

// if-elseif-else
$c = 5;
if ($c > 5) {
    echo "c大于5\n";
} elseif ($c < 5) {
    echo "c小于5\n";
} else {
    echo "c等于5\n";
}

// 嵌套if
$x = 10;
$y = 20;
if ($x > 5) {
    if ($y > 15) {
        echo "x>5且y>15\n";
    } else {
        echo "x>5但y<=15\n";
    }
} else {
    echo "x<=5\n";
}

// 替代语法
$d = 100;
if ($d > 50):
    echo "d大于50\n";
elseif ($d > 25):
    echo "d大于25\n";
else:
    echo "d不大于25\n";
endif;

// 三元运算符
$e = 15;
echo $e > 10 ? "e大于10" : "e不大于10";
echo "\n";

// 嵌套三元
$f = 5;
echo $f > 10 ? "big" : ($f > 5 ? "medium" : "small");
echo "\n";

// 空合并运算符
$g = null;
$h = "default";
echo $g ?? "null值";
echo "\n";
echo $h ?? "不会用这个";
echo "\n";

// 链式空合并
$i = null;
$j = null;
$k = "found";
echo $i ?? $j ?? $k ?? "未找到";
echo "\n";

// Elvis运算符
$l = 0;
$m = "value";
echo $l ?: "falsy值";
echo "\n";
echo $m ?: "不会用这个";
echo "\n";

// 复杂条件表达式
$val = 42;
if ($val >= 0 && $val <= 100 && $val % 2 === 0):
    echo "val是0-100之间的偶数\n";
endif;

// 短路求值
function returnsTrue() { echo "called\n"; return true; }
function returnsFalse() { echo "never called\n"; return false; }

if (true || returnsFalse()) {
    echo "短路OR测试\n";
}

if (false && returnsFalse()) {
    echo "不会执行\n";
} else {
    echo "短路AND测试\n";
}
