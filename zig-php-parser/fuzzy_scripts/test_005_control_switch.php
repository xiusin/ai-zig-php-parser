<?php
// switch控制结构测试

// 基础switch
$x = 2;
switch ($x) {
    case 1:
        echo "one\n";
        break;
    case 2:
        echo "two\n";
        break;
    case 3:
        echo "three\n";
        break;
    default:
        echo "other\n";
}

// 无break的fallthrough
$y = 1;
switch ($y) {
    case 1:
        echo "case1\n";
    case 2:
        echo "case2\n";
    case 3:
        echo "case3\n";
        break;
    default:
        echo "default\n";
}

// 多个case共享代码块
$z = 5;
switch ($z) {
    case 1:
    case 2:
    case 3:
        echo "1-3\n";
        break;
    case 4:
    case 5:
    case 6:
        echo "4-6\n";
        break;
    default:
        echo "other\n";
}

// 替代语法
$a = 10;
switch ($a):
    case 5:
        echo "five\n";
        break;
    case 10:
        echo "ten\n";
        break;
    default:
        echo "other\n";
endswitch;

// 字符串switch
$str = "apple";
switch ($str) {
    case "banana":
        echo "yellow\n";
        break;
    case "apple":
        echo "red\n";
        break;
    case "orange":
        echo "orange\n";
        break;
    default:
        echo "unknown\n";
}

// 松散比较switch
$val = "2";
switch ($val) {
    case 2:
        echo "匹配数字2（松散比较）\n";
        break;
    case "2":
        echo "匹配字符串'2'\n";
        break;
    default:
        echo "no match\n";
}

// 嵌套switch
$outer = 'A';
$inner = 1;
switch ($outer) {
    case 'A':
        echo "outer A\n";
        switch ($inner) {
            case 1:
                echo "inner 1\n";
                break;
            case 2:
                echo "inner 2\n";
                break;
        }
        break;
    case 'B':
        echo "outer B\n";
        break;
}

// switch表达式中的函数调用
function getValue() { return 10; }
switch (getValue()) {
    case 5:
        echo "five\n";
        break;
    case 10:
        echo "ten from function\n";
        break;
}

// 空case
$empty = 1;
switch ($empty) {
    case 1:
    case 2:
    case 3:
        echo "1 or 2 or 3\n";
        break;
}

// 使用continue
for ($i = 0; $i < 3; $i++) {
    switch ($i) {
        case 0:
            echo "i=0\n";
            continue 2; // 跳出switch继续for循环
        case 1:
            echo "i=1\n";
            break;
        case 2:
            echo "i=2\n";
            break;
    }
    echo "after switch i=$i\n";
}
