#!/bin/bash
# AOT 编译器综合测试套件

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
TEST_DIR="/tmp/aot_tests"
RESULTS_FILE="$TEST_DIR/results.txt"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

mkdir -p "$TEST_DIR"
echo "AOT 编译器测试结果" > "$RESULTS_FILE"
echo "==================" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

TOTAL=0
PASSED=0
FAILED=0

# 测试函数
run_test() {
    local name="$1"
    local php_code="$2"
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "测试 $TOTAL: $name ... "
    
    # 创建 PHP 文件
    echo "$php_code" > "$TEST_DIR/test_$TOTAL.php"
    
    # 运行 PHP 解释器
    php "$TEST_DIR/test_$TOTAL.php" > "$TEST_DIR/php_$TOTAL.txt" 2>&1 || true
    
    # AOT 编译
    cd "$PROJECT_ROOT"
    rm -rf .zigphp_aot_build
    ./zig-out/bin/php-interpreter --compile --output="$TEST_DIR/test_${TOTAL}_aot" "$TEST_DIR/test_$TOTAL.php" > "$TEST_DIR/compile_$TOTAL.txt" 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}编译失败${NC}"
        echo "测试 $TOTAL: $name - 编译失败" >> "$RESULTS_FILE"
        cat "$TEST_DIR/compile_$TOTAL.txt" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # 运行 AOT
    "$TEST_DIR/test_${TOTAL}_aot" > "$TEST_DIR/aot_$TOTAL.txt" 2>&1 || true
    
    # 比较输出
    if diff -q "$TEST_DIR/php_$TOTAL.txt" "$TEST_DIR/aot_$TOTAL.txt" > /dev/null 2>&1; then
        echo -e "${GREEN}通过${NC}"
        echo "测试 $TOTAL: $name - 通过 ✓" >> "$RESULTS_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}失败${NC}"
        echo "测试 $TOTAL: $name - 失败 ✗" >> "$RESULTS_FILE"
        echo "PHP 输出:" >> "$RESULTS_FILE"
        cat "$TEST_DIR/php_$TOTAL.txt" >> "$RESULTS_FILE"
        echo "AOT 输出:" >> "$RESULTS_FILE"
        cat "$TEST_DIR/aot_$TOTAL.txt" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
        FAILED=$((FAILED + 1))
    fi
}

echo "开始 AOT 编译器综合测试..."
echo ""

# ==================== 基础语法测试 ====================
echo "=== 基础语法测试 ==="

run_test "变量赋值和输出" '<?php
$x = 42;
echo $x . "\n";
?>'

run_test "字符串拼接" '<?php
$a = "Hello";
$b = "World";
echo $a . " " . $b . "\n";
?>'

run_test "算术运算" '<?php
echo (10 + 5) . "\n";
echo (10 - 5) . "\n";
echo (10 * 5) . "\n";
echo (10 / 5) . "\n";
echo (10 % 3) . "\n";
?>'

run_test "比较运算" '<?php
echo (5 > 3 ? "yes" : "no") . "\n";
echo (5 < 3 ? "yes" : "no") . "\n";
echo (5 == 5 ? "yes" : "no") . "\n";
echo (5 != 3 ? "yes" : "no") . "\n";
?>'

# ==================== 控制流测试 ====================
echo ""
echo "=== 控制流测试 ==="

run_test "if-else" '<?php
$x = 10;
if ($x > 5) {
    echo "大于5\n";
} else {
    echo "小于等于5\n";
}
?>'

run_test "if-elseif-else" '<?php
$x = 5;
if ($x > 10) {
    echo "大于10\n";
} elseif ($x > 5) {
    echo "大于5\n";
} else {
    echo "小于等于5\n";
}
?>'

run_test "while 循环" '<?php
$i = 0;
while ($i < 3) {
    echo $i . "\n";
    $i++;
}
?>'

run_test "do-while 循环" '<?php
$i = 0;
do {
    echo $i . "\n";
    $i++;
} while ($i < 3);
?>'

run_test "for 循环" '<?php
for ($i = 0; $i < 3; $i++) {
    echo $i . "\n";
}
?>'

run_test "break" '<?php
for ($i = 0; $i < 10; $i++) {
    if ($i == 3) break;
    echo $i . "\n";
}
?>'

run_test "continue" '<?php
for ($i = 0; $i < 5; $i++) {
    if ($i == 2) continue;
    echo $i . "\n";
}
?>'

# ==================== 函数测试 ====================
echo ""
echo "=== 函数测试 ==="

run_test "简单函数" '<?php
function greet($name) {
    return "Hello, " . $name;
}
echo greet("Alice") . "\n";
?>'

run_test "函数默认参数" '<?php
function greet($name = "World") {
    return "Hello, " . $name;
}
echo greet() . "\n";
echo greet("Alice") . "\n";
?>'

run_test "多个参数" '<?php
function add($a, $b) {
    return $a + $b;
}
echo add(3, 5) . "\n";
?>'

run_test "递归函数" '<?php
function factorial($n) {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}
echo factorial(5) . "\n";
?>'

run_test "全局变量" '<?php
$counter = 0;
function increment() {
    global $counter;
    $counter++;
}
increment();
increment();
echo $counter . "\n";
?>'

# ==================== 数组测试 ====================
echo ""
echo "=== 数组测试 ==='

run_test "数组创建和访问" '<?php
$arr = [1, 2, 3];
echo $arr[0] . "\n";
echo $arr[1] . "\n";
echo $arr[2] . "\n";
?>'

run_test "关联数组" '<?php
$arr = ["name" => "Alice", "age" => 30];
echo $arr["name"] . "\n";
echo $arr["age"] . "\n";
?>'

run_test "数组赋值" '<?php
$arr = [];
$arr[0] = 10;
$arr[1] = 20;
echo $arr[0] . "\n";
echo $arr[1] . "\n";
?>'

run_test "二维数组" '<?php
$matrix = [];
$matrix[0][0] = 1;
$matrix[0][1] = 2;
$matrix[1][0] = 3;
$matrix[1][1] = 4;
echo $matrix[0][0] . "\n";
echo $matrix[1][1] . "\n";
?>'

run_test "三维数组" '<?php
$cube = [];
$cube[0][0][0] = 100;
$cube[1][2][3] = 123;
echo $cube[0][0][0] . "\n";
echo $cube[1][2][3] . "\n";
?>'

run_test "数组 push" '<?php
$arr = [];
$arr[] = 1;
$arr[] = 2;
$arr[] = 3;
echo $arr[0] . "\n";
echo $arr[1] . "\n";
echo $arr[2] . "\n";
?>'

# ==================== 字符串测试 ====================
echo ""
echo "=== 字符串测试 ==="

run_test "字符串插值" '<?php
$name = "Alice";
$age = 30;
echo "Name: $name, Age: $age\n";
?>'

run_test "字符串拼接" '<?php
$a = "Hello";
$b = "World";
$c = $a . " " . $b;
echo $c . "\n";
?>'

# ==================== 逻辑运算测试 ====================
echo ""
echo "=== 逻辑运算测试 ==="

run_test "逻辑 AND" '<?php
echo (true && true ? "yes" : "no") . "\n";
echo (true && false ? "yes" : "no") . "\n";
?>'

run_test "逻辑 OR" '<?php
echo (true || false ? "yes" : "no") . "\n";
echo (false || false ? "yes" : "no") . "\n";
?>'

run_test "短路求值 AND" '<?php
$x = 0;
function test() {
    global $x;
    $x = 1;
    return true;
}
false && test();
echo $x . "\n";
?>'

run_test "短路求值 OR" '<?php
$x = 0;
function test() {
    global $x;
    $x = 1;
    return false;
}
true || test();
echo $x . "\n";
?>'

# ==================== 三元运算符测试 ====================
echo ""
echo "=== 三元运算符测试 ==="

run_test "三元运算符" '<?php
$x = 10;
echo ($x > 5 ? "big" : "small") . "\n";
?>'

run_test "嵌套三元运算符" '<?php
$x = 5;
echo ($x > 10 ? "big" : ($x > 5 ? "medium" : "small")) . "\n";
?>'

# ==================== 类型转换测试 ====================
echo ""
echo "=== 类型转换测试 ==="

run_test "整数转字符串" '<?php
$x = 42;
echo "Value: " . $x . "\n";
?>'

run_test "字符串转整数" '<?php
$x = "42";
echo ($x + 10) . "\n";
?>'

run_test "布尔转字符串" '<?php
$x = true;
$y = false;
echo ($x ? "true" : "false") . "\n";
echo ($y ? "true" : "false") . "\n";
?>'

# ==================== 边界条件测试 ====================
echo ""
echo "=== 边界条件测试 ==="

run_test "空数组" '<?php
$arr = [];
echo "empty\n";
?>'

run_test "空字符串" '<?php
$s = "";
echo "empty: " . $s . "end\n";
?>'

run_test "零值" '<?php
$x = 0;
echo $x . "\n";
?>'

run_test "负数" '<?php
$x = -42;
echo $x . "\n";
?>'

run_test "大数" '<?php
$x = 1000000;
echo $x . "\n";
?>'

# ==================== 复杂场景测试 ====================
echo ""
echo "=== 复杂场景测试 ==="

run_test "函数返回数组" '<?php
function getArray() {
    return [1, 2, 3];
}
$arr = getArray();
echo $arr[0] . "\n";
echo $arr[1] . "\n";
?>'

run_test "数组作为参数" '<?php
function sum($arr) {
    $total = 0;
    for ($i = 0; $i < 3; $i++) {
        $total = $total + $arr[$i];
    }
    return $total;
}
echo sum([1, 2, 3]) . "\n";
?>'

run_test "嵌套函数调用" '<?php
function double($x) {
    return $x * 2;
}
function triple($x) {
    return $x * 3;
}
echo double(triple(5)) . "\n";
?>'

run_test "多个全局变量" '<?php
$x = 10;
$y = 20;
function test() {
    global $x, $y;
    echo ($x + $y) . "\n";
}
test();
?>'

run_test "全局变量修改" '<?php
$counter = 0;
function inc() {
    global $counter;
    $counter++;
    return $counter;
}
echo inc() . "\n";
echo inc() . "\n";
echo inc() . "\n";
?>'

# ==================== 总结 ====================
echo ""
echo "===================="
echo "测试完成！"
echo "总计: $TOTAL"
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"
echo "成功率: $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}")%"
echo ""
echo "详细结果保存在: $RESULTS_FILE"

echo "" >> "$RESULTS_FILE"
echo "==================" >> "$RESULTS_FILE"
echo "总计: $TOTAL" >> "$RESULTS_FILE"
echo "通过: $PASSED" >> "$RESULTS_FILE"
echo "失败: $FAILED" >> "$RESULTS_FILE"
echo "成功率: $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}")%" >> "$RESULTS_FILE"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}所有测试通过！🎉${NC}"
    exit 0
else
    echo -e "${RED}有 $FAILED 个测试失败${NC}"
    exit 1
fi
