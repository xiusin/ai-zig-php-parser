#!/bin/bash

# AOT 模糊测试脚本生成器 v2
# 使用 gtimeout 替代 timeout

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1

# 创建报告文件
REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"
echo "# AOT 模糊测试报告" > "$REPORT_FILE"
echo "生成时间: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| # | 脚本路径 | 类别 | PHP结果 | 解释器结果 | AOT结果 | 状态 | 错误信息 |" >> "$REPORT_FILE"
echo "|---|-----------|------|---------|-----------|---------|------|----------|" >> "$REPORT_FILE"

# 测试函数
test_script() {
    local php_code="$1"
    local desc="$2"
    local category="$3"
    
    local script_path="$SCRIPT_DIR/test_${COUNTER}.php"
    local php_out="$SCRIPT_DIR/test_${COUNTER}_php.out"
    local interp_out="$SCRIPT_DIR/test_${COUNTER}_interp.out"
    local aot_out="$SCRIPT_DIR/test_${COUNTER}_aot.out"
    local aot_binary="$SCRIPT_DIR/test_${COUNTER}_aot"
    
    # 写入测试脚本
    echo "<?php" > "$script_path"
    echo "$php_code" >> "$script_path"
    echo "?>" >> "$script_path"
    
    # 获取 PHP 标准输出 (30s 超时)
    $TIMEOUT 30s $PHP "$script_path" > "$php_out" 2>&1
    PHP_EXIT=$?
    PHP_RESULT=$(cat "$php_out")
    
    # 获取解释器输出 (30s 超时)
    $TIMEOUT 30s "$INTERPRETER" "$script_path" > "$interp_out" 2>&1
    INTERP_EXIT=$?
    INTERP_RESULT=$(cat "$interp_out")
    
    # AOT 编译 (30s 超时)
    rm -rf "$SCRIPT_DIR/.zigphp_aot_build"
    $TIMEOUT 30s "$INTERPRETER" --compile --output="$aot_binary" "$script_path" > "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" 2>&1
    AOT_COMPILE_EXIT=$?
    
    # 如果编译成功，运行 AOT 二进制
    if [ $AOT_COMPILE_EXIT -eq 0 ] && [ -x "$aot_binary" ]; then
        $TIMEOUT 30s "$aot_binary" > "$aot_out" 2>&1
        AOT_EXIT=$?
        AOT_RESULT=$(cat "$aot_out")
    else
        AOT_EXIT=1
        AOT_RESULT="[编译失败]"
    fi
    
    # 判断状态
    if [ $PHP_EXIT -ne 0 ]; then
        STATUS="PHP_ERROR"
        PHP_RESULT="[PHP错误: $PHP_EXIT]"
    elif [ $INTERP_EXIT -ne 0 ]; then
        STATUS="INTERP_ERROR"
    elif [ $AOT_COMPILE_EXIT -ne 0 ]; then
        STATUS="AOT_COMPILE_ERROR"
        AOT_RESULT="[编译错误]"
    elif [ $AOT_EXIT -ne 0 ]; then
        STATUS="AOT_RUNTIME_ERROR"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        STATUS="RESULT_MISMATCH"
    elif [ "$INTERP_RESULT" != "$PHP_RESULT" ]; then
        STATUS="INTERP_MISMATCH"
    else
        STATUS="PASS"
    fi
    
    # 错误信息
    if [ $AOT_COMPILE_EXIT -ne 0 ]; then
        ERROR_INFO=$(cat "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" | head -20 | tr '\n' ' ')
    elif [ $AOT_EXIT -ne 0 ]; then
        ERROR_INFO="运行时错误 (exit: $AOT_EXIT)"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        ERROR_INFO="期望: $PHP_RESULT, 实际: $AOT_RESULT"
    else
        ERROR_INFO="-"
    fi
    
    # 写入报告
    echo "| $COUNTER | test_$COUNTER.php | $category | ${PHP_RESULT:0:50} | ${INTERP_RESULT:0:50} | ${AOT_RESULT:0:50} | $STATUS | ${ERROR_INFO:0:80} |" >> "$REPORT_FILE"
    
    echo "[$COUNTER] $category - $STATUS: $desc"
    
    COUNTER=$((COUNTER + 1))
}

# ===== 复杂测试用例生成 =====

# 1. 深层嵌套循环
test_script '
function deepNested($n) {
    $result = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            for ($k = 0; $k < $n; $k++) {
                $result += $i * $j + $k;
            }
        }
    }
    return $result;
}
echo deepNested(5);
' "深层嵌套循环" "循环"

# 2. 复杂条件表达式
test_script '
$x = 5;
$y = 10;
$z = 15;
$result = ($x > 3 && $y < 20) || ($z == 15 && $x + $y > $z) ? ($x * $y) + ($z / 3) : ($x - $y) * $z;
echo $result;
' "复杂条件表达式" "表达式"

# 3. 多维数组操作
test_script '
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];
$sum = 0;
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $sum += $matrix[$i][$j];
    }
}
echo $sum;
' "多维数组操作" "数组"

# 4. 递归与循环混合
test_script '
function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
$result = 0;
for ($i = 0; $i < 10; $i++) {
    $result += fib($i);
}
echo $result;
' "递归与循环混合" "递归"

# 5. 全局变量复杂操作
test_script '
global $counter;
$counter = 0;
function increment() {
    global $counter;
    $counter++;
    return $counter;
}
for ($i = 0; $i < 5; $i++) {
    echo increment();
}
' "全局变量操作" "全局变量"

# 6. 字符串连接
test_script '
$str = "Hello";
$str .= " World";
echo $str;
' "字符串连接" "字符串"

# 7. 关联数组操作
test_script '
$assoc = ["a" => 1, "b" => 2, "c" => 3];
$sum = 0;
foreach ($assoc as $key => $value) {
    $sum += $value;
}
echo $sum;
' "关联数组" "数组"

# 8. 复杂的三元嵌套
test_script '
$x = 5;
$y = 10;
$result = $x > 0 ? ($y > 0 ? ($x > $y ? "x>y" : "y>=x") : "y<=0") : "x<=0";
echo $result;
' "嵌套三元运算符" "表达式"

# 9. Switch 复杂用法
test_script '
$value = 2;
switch ($value) {
    case 1:
        echo "one";
        break;
    case 2:
        echo "two";
        break;
    default:
        echo "other";
}
' "Switch语句" "控制流"

# 10. Do-while 循环
test_script '
$i = 0;
do {
    echo $i;
    $i++;
} while ($i < 5);
' "Do-while循环" "循环"

# 11. 复杂布尔表达式
test_script '
$a = true;
$b = false;
$c = true;
$result = ($a && $b) || ($b && $c) || ($a && $c);
echo $result ? "true" : "false";
' "复杂布尔表达式" "表达式"

# 12. 位运算操作
test_script '
$x = 5;
$y = 3;
echo ($x & $y) . ($x | $y) . ($x ^ $y);
' "位运算操作" "运算符"

# 13. 浮点数运算
test_script '
$x = 3.14;
$y = 2.5;
$z = $x * $y;
echo round($z, 2);
' "浮点数运算" "数值"

# 14. 负数运算
test_script '
$x = -5;
$y = -3;
echo abs($x) . ($x + $y) . ($x * $y);
' "负数运算" "数值"

# 15. 数组Push操作
test_script '
$arr = [];
for ($i = 0; $i < 5; $i++) {
    $arr[] = $i * 2;
}
echo count($arr) . implode(",", $arr);
' "数组Push" "数组"

# 16. 嵌套函数调用
test_script '
function f1($x) { return $x + 1; }
function f2($x) { return $x * 2; }
function f3($x) { return $x - 3; }
echo f1(f2(f3(10)));
' "嵌套函数调用" "函数"

# 17. 多个全局变量
test_script '
global $a, $b, $c;
$a = 1; $b = 2; $c = 3;
function test() {
    global $a, $b, $c;
    return $a + $b + $c;
}
echo test();
' "多全局变量" "全局变量"

# 18. 数组索引表达式
test_script '
$arr = [1, 2, 3, 4, 5];
echo $arr[0] + $arr[count($arr) - 1];
' "数组索引表达式" "数组"

# 19. 字符串索引
test_script '
$str = "abcde";
echo $str[0] . $str[2] . $str[4];
' "字符串索引" "字符串"

# 20. 类型混合运算
test_script '
$x = 5;
$y = "10";
$z = 3.5;
echo $x + $y + (int)$z;
' "类型混合运算" "类型"

# 21. 复合赋值复杂表达式
test_script '
$x = 10;
$x += 5;
$x *= 2;
$x -= 10;
echo $x;
' "复合赋值" "运算符"

# 22. 递增递减复杂用法
test_script '
$x = 5;
$y = $x++;
$z = ++$x;
echo $x . $y . $z;
' "递增递减" "运算符"

# 23. Match 表达式
test_script '
$value = 2;
$result = match($value) {
    1 => "one",
    2 => "two",
    3 => "three",
    default => "other",
};
echo $result;
' "Match表达式" "控制流"

# 24. 空数组字面量
test_script '
$arr = [];
echo count($arr);
' "空数组" "数组"

# 25. 空字符串
test_script '
$str = "";
echo strlen($str) . ($str == "" ? "empty" : "not empty");
' "空字符串" "字符串"

# 26. Break/Continue 层级
test_script '
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j == 1) continue 2;
        echo "$i-$j ";
    }
}
' "Continue层级" "控制流"

# 27. 数组元素修改
test_script '
$arr = [1, 2, 3];
$arr[0] = 10;
$arr[1] += 5;
echo implode(",", $arr);
' "数组元素修改" "数组"

# 28. 复杂循环条件
test_script '
$i = 0;
while ($i < 5 && $i != 3) {
    echo $i;
    $i++;
}
' "While循环" "循环"

# 29. For 循环复杂条件
test_script '
for ($i = 0, $j = 10; $i < 5 && $j > 5; $i++, $j--) {
    echo "$i-$j ";
}
' "For复杂条件" "循环"

# 30. Foreach 键值
test_script '
$arr = ["a" => 1, "b" => 2, "c" => 3];
foreach ($arr as $k => $v) {
    echo "$k$v ";
}
' "Foreach键值" "数组"

# 31. 函数默认参数
test_script '
function test($x = 5, $y = 10) {
    return $x + $y;
}
echo test() . test(2) . test(2, 3);
' "默认参数" "函数"

# 32. 函数多返回值场景
test_script '
function getValues() {
    return [1, 2, 3];
}
$arr = getValues();
echo $arr[0] + $arr[1] + $arr[2];
' "函数返回数组" "函数"

# 33. 深层数组访问
test_script '
$arr = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]];
echo $arr[1][0][1];
' "深层数组访问" "数组"

# 34. 条件中数组操作
test_script '
$arr = [1, 2, 3];
if (count($arr) > 0 && $arr[0] == 1) {
    echo "yes";
} else {
    echo "no";
}
' "条件中数组" "数组"

# 35. 循环中修改数组
test_script '
$arr = [1, 2, 3, 4, 5];
for ($i = 0; $i < count($arr); $i++) {
    $arr[$i] *= 2;
}
echo implode(",", $arr);
' "循环修改数组" "数组"

# 36. 复杂逻辑表达式
test_script '
$x = 5;
$y = 10;
$z = 15;
echo ($x < $y && $y < $z) || ($x > $z);
' "复杂逻辑" "表达式"

# 37. 混合类型数组
test_script '
$arr = [1, "two", 3.5, true, null];
echo $arr[0] . $arr[1] . $arr[2];
' "混合类型数组" "数组"

# 38. 数组比较
test_script '
$arr1 = [1, 2, 3];
$arr2 = [1, 2, 3];
echo $arr1 == $arr2 ? "equal" : "not equal";
' "数组比较" "数组"

# 39. 嵌套 Foreach
test_script '
$matrix = [[1, 2], [3, 4]];
foreach ($matrix as $row) {
    foreach ($row as $val) {
        echo $val;
    }
}
' "嵌套Foreach" "数组"

# 40. 函数中全局变量修改
test_script '
$x = 1;
function modify() {
    global $x;
    $x = 100;
}
modify();
echo $x;
' "全局变量修改" "全局变量"

# 41. 递归 factorial
test_script '
function factorial($n) {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}
echo factorial(5);
' "递归阶乘" "递归"

# 42. 字符串插值
test_script '
$name = "World";
$age = 25;
echo "Hello $name, you are $age years old.";
' "字符串插值" "字符串"

# 43. 数组键访问
test_script '
$arr = [10 => "ten", 20 => "twenty"];
echo $arr[10] . $arr[20];
' "数组键访问" "数组"

# 44. 比较运算
test_script '
echo 5 == 5 ? "eq" : "neq";
echo 5 == "5" ? "eq" : "neq";
echo 5 === "5" ? "seq" : "sneq";
' "比较运算" "运算符"

# 45. 逻辑运算短路
test_script '
function sideEffect() {
    echo "called";
    return true;
}
$result = false && sideEffect();
echo $result ? "true" : "false";
$result = true || sideEffect();
echo $result ? "true" : "false";
' "逻辑短路" "运算符"

# 46. 数组解构赋值
test_script '
$arr = [1, 2, 3];
list($a, $b, $c) = $arr;
echo $a + $b + $c;
' "list赋值" "数组"

# 47. Null coalescing
test_script '
$x = null;
$y = $x ?? "default";
$z = "value";
$w = $z ?? "default";
echo $y . $w;
' "Null合并运算符" "运算符"

# 48. Spaceship 运算符
test_script '
echo 5 <=> 3;
echo 5 <=> 5;
echo 3 <=> 5;
' "Spaceship运算符" "运算符"

# 49. 可变变量
test_script '
$var = "hello";
$$var = "world";
echo $hello;
' "可变变量" "变量"

# 50. 函数引用返回
test_script '
function &getRef() {
    static $x = 10;
    return $x;
}
$ref = &getRef();
$ref = 20;
echo getRef();
' "引用返回" "函数"

echo ""
echo "========================================="
echo "测试完成！报告保存在: $REPORT_FILE"
echo "========================================="
cat "$REPORT_FILE"