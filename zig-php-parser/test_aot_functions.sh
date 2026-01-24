#!/bin/bash

# AOT编译器函数功能测试套件
# 测试所有函数相关功能

set -e

echo "=== AOT编译器函数功能测试套件 ==="
echo ""

PASSED=0
FAILED=0
TOTAL=0

# 测试函数
test_case() {
    local name="$1"
    local file="$2"
    local expected="$3"
    
    TOTAL=$((TOTAL + 1))
    echo -n "测试 $TOTAL: $name ... "
    
    # 编译
    ./zig-out/bin/php-interpreter --compile "$file" > /dev/null 2>&1
    
    # 运行并捕获输出（只检查开头部分，忽略内存泄漏警告）
    output=$(./hello 2>&1 | tr -d '%' | head -c 100)
    
    # 比较输出（只比较expected长度的部分）
    output_trimmed="${output:0:${#expected}}"
    
    if [ "$output_trimmed" = "$expected" ]; then
        echo "✓ 通过"
        PASSED=$((PASSED + 1))
    else
        echo "✗ 失败"
        echo "  期望: $expected"
        echo "  实际: $output_trimmed"
        FAILED=$((FAILED + 1))
    fi
}

echo "--- 基本函数测试 ---"

# 测试1: void函数
cat > test_temp.php << 'EOF'
<?php
function greet() {
    echo "Hello";
}

greet();
EOF
test_case "void函数" "test_temp.php" "Hello"

# 测试2: 带参数和返回值
cat > test_temp.php << 'EOF'
<?php
function add($a, $b) {
    return $a + $b;
}

$result = add(10, 20);
echo $result;
EOF
test_case "带参数和返回值" "test_temp.php" "30"

echo ""
echo "--- 递归函数测试 ---"

# 测试3: factorial递归
test_case "factorial(5)" "test_factorial.php" "120"

# 测试4: fibonacci递归
test_case "fibonacci(10)" "test_fibonacci.php" "55"

echo ""
echo "--- 多函数调用测试 ---"

# 测试5: 多个函数相互调用
test_case "多函数调用" "test_multiple_functions.php" "19"

# 测试6: 字符串函数
test_case "字符串函数" "test_string_function.php" "Hello, World!"

echo ""
echo "--- 高级测试 ---"

# 测试7: 嵌套函数调用
cat > test_temp.php << 'EOF'
<?php
function double($x) {
    return $x * 2;
}

function triple($x) {
    return $x * 3;
}

function process($x) {
    return double($x) + triple($x);
}

$result = process(5);
echo $result;
EOF
test_case "嵌套函数调用" "test_temp.php" "25"

# 测试8: 条件返回
cat > test_temp.php << 'EOF'
<?php
function max($a, $b) {
    if ($a > $b) {
        return $a;
    } else {
        return $b;
    }
}

$result = max(15, 10);
echo $result;
EOF
test_case "条件返回" "test_temp.php" "15"

# 测试9: 多层递归
cat > test_temp.php << 'EOF'
<?php
function sum($n) {
    if ($n <= 0) {
        return 0;
    }
    return $n + sum($n - 1);
}

$result = sum(10);
echo $result;
EOF
test_case "多层递归(sum)" "test_temp.php" "55"

# 测试10: 函数返回值作为if条件
cat > test_temp.php << 'EOF'
<?php
function test() {
    $x = 5;
    if ($x > 0) {
        return 1;
    } else {
        return 0;
    }
}

$result = test();
if ($result) {
    echo "yes";
} else {
    echo "no";
}
EOF
test_case "返回值作为if条件" "test_temp.php" "yes"

# 清理临时文件
rm -f test_temp.php

echo ""
echo "================================"
echo "总计: $TOTAL | 通过: $PASSED | 失败: $FAILED"
echo "================================"

if [ $FAILED -eq 0 ]; then
    echo "✓ 所有测试通过！"
    exit 0
else
    echo "✗ 有测试失败"
    exit 1
fi
