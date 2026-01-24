<?php
// 测试简单if-else优化

// 场景1：简单if-else（应该优化）
function simple_if_else($x) {
    if ($x > 10) {
        return "大于10";
    } else {
        return "小于等于10";
    }
}

// 场景2：只有if没有else（应该优化）
function only_if($x) {
    if ($x > 0) {
        return "正数";
    }
    return "非正数";
}

// 场景3：嵌套if（应该使用状态机）
function nested_if($x, $y) {
    if ($x > 0) {
        if ($y > 0) {
            return "都是正数";
        } else {
            return "x正y非正";
        }
    } else {
        return "x非正";
    }
}

// 测试
echo "测试1: ";
echo simple_if_else(15);
echo "\n";

echo "测试2: ";
echo simple_if_else(5);
echo "\n";

echo "测试3: ";
echo only_if(10);
echo "\n";

echo "测试4: ";
echo only_if(-5);
echo "\n";

echo "测试5: ";
echo nested_if(5, 10);
echo "\n";

echo "测试6: ";
echo nested_if(5, -10);
echo "\n";

echo "测试7: ";
echo nested_if(-5, 10);
echo "\n";
