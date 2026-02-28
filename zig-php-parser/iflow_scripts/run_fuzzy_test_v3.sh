#!/bin/bash

# AOT 模糊测试脚本生成器 v4 - 修复变量转义问题
# 生成更多复杂测试用例

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=101

# 追加到报告文件
REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"

# 测试函数 - 使用 cat <<'ENDPHP' 来避免转义问题
test_script() {
    local desc="$2"
    local category="$3"
    
    local script_path="$SCRIPT_DIR/test_${COUNTER}.php"
    local php_out="$SCRIPT_DIR/test_${COUNTER}_php.out"
    local interp_out="$SCRIPT_DIR/test_${COUNTER}_interp.out"
    local aot_out="$SCRIPT_DIR/test_${COUNTER}_aot.out"
    local aot_binary="$SCRIPT_DIR/test_${COUNTER}_aot"
    
    # 直接写入测试代码（不通过 echo）
    cat > "$script_path" << 'ENDPHP'
<?php
ENDPHP
    echo "$1" >> "$script_path"
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
        ERROR_INFO=$(cat "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" | tail -5 | head -3 | tr '\n' ' ')
    elif [ $AOT_EXIT -ne 0 ]; then
        ERROR_INFO="运行时错误 (exit: $AOT_EXIT)"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        ERROR_INFO="期望: $PHP_RESULT, 实际: $AOT_RESULT"
    else
        ERROR_INFO="-"
    fi
    
    # 写入报告
    echo "| $COUNTER | test_$COUNTER.php | $category | ${PHP_RESULT:0:40} | ${INTERP_RESULT:0:40} | ${AOT_RESULT:0:40} | $STATUS | ${ERROR_INFO:0:60} |" >> "$REPORT_FILE"
    
    echo "[$COUNTER] $category - $STATUS: $desc"
    
    COUNTER=$((COUNTER + 1))
}

# ===== 类和对象测试 =====

test_script '
class Foo {
    public $x = 10;
    public function getX() {
        return $this->x;
    }
}
$obj = new Foo();
echo $obj->getX();
' "类和对象" "OOP"

test_script '
class Base {
    public function greet() {
        return "Hello";
    }
}
class Derived extends Base {
    public function greet() {
        return "Hi";
    }
}
$obj = new Derived();
echo $obj->greet();
' "类继承" "OOP"

test_script '
class Math {
    public static function add($a, $b) {
        return $a + $b;
    }
}
echo Math::add(3, 4);
' "静态方法" "OOP"

test_script '
class Person {
    public $name;
    public function __construct($name) {
        $this->name = $name;
    }
}
$p = new Person("John");
echo $p->name;
' "构造函数" "OOP"

test_script '
class Point {
    public $x = 5;
    public $y = 10;
}
$p = new Point();
echo $p->x + $p->y;
' "对象属性" "OOP"

# ===== 更多内置函数测试 =====

test_script '
$arr = [3, 1, 4, 1, 5];
sort($arr);
echo implode(",", $arr);
' "数组排序" "数组"

test_script '
$arr = [1, 2, 3, 4, 5];
$rev = array_reverse($arr);
echo implode(",", $rev);
' "数组反转" "数组"

test_script '
$a = [1, 2];
$b = [3, 4];
$c = array_merge($a, $b);
echo implode(",", $c);
' "数组合并" "数组"

test_script '
$arr = [3, 1, 4, 1, 5, 9, 2, 6];
sort($arr);
echo implode(",", $arr);
echo count($arr);
' "sort_count" "数组"

test_script '
$arr = [1, 2, 3, 4, 5];
echo in_array(3, $arr) ? "yes" : "no";
echo in_array(6, $arr) ? "yes" : "no";
' "in_array" "函数"

test_script '
echo strlen("Hello World");
' "strlen" "函数"

test_script '
echo strtoupper("hello");
' "strtoupper" "函数"

test_script '
echo strtolower("HELLO");
' "strtolower" "函数"

test_script '
echo str_replace("World", "PHP", "Hello World");
' "str_replace" "函数"

test_script '
echo substr("Hello World", 6, 5);
' "substr" "函数"

test_script '
echo strpos("Hello World", "World");
' "strpos" "函数"

test_script '
$arr = explode(",", "a,b,c");
echo implode("-", $arr);
' "explode_implode" "函数"

test_script '
echo trim("  hello  ");
' "trim" "函数"

test_script '
echo sprintf("Num: %d, Str: %s", 42, "test");
' "sprintf" "函数"

test_script '
echo is_array([1,2,3]) ? "yes" : "no";
echo is_array("test") ? "yes" : "no";
' "is_array" "函数"

test_script '
echo is_int(42) ? "int" : "not int";
echo is_string("test") ? "str" : "not str";
' "is_int_is_string" "函数"

test_script '
$a = "";
$b = "test";
echo empty($a) ? "empty" : "not empty";
echo empty($b) ? "empty" : "not empty";
' "empty" "函数"

test_script '
$a = null;
$b = "test";
echo isset($a) ? "set" : "not set";
echo isset($b) ? "set" : "not set";
' "isset" "函数"

# ===== 更多边界测试 =====

test_script '
$x = 0;
echo $x++;
echo $x;
' "后缀递增" "运算符"

test_script '
$x = 0;
echo ++$x;
echo $x;
' "前缀递增" "运算符"

test_script '
echo 5 & 3;
echo 5 | 3;
echo 5 ^ 3;
' "位运算" "运算符"

test_script '
echo 5 << 2;
echo 20 >> 2;
' "位移运算" "运算符"

test_script '
$x = null;
echo $x ?? "default";
$y = "value";
echo $y ?? "default";
' "空合并" "运算符"

test_script '
echo 5 <=> 3;
echo 5 <=> 5;
echo 3 <=> 5;
' "spaceship" "运算符"

test_script '
echo 1 ?: "default";
echo 0 ?: "default";
echo "" ?: "default";
' "elvis" "运算符"

test_script '
$arr = [1, 2, 3];
echo $arr[0] ?? "default";
echo $arr[10] ?? "default";
' "数组空合并" "运算符"

test_script '
echo pow(2, 10);
echo sqrt(16);
echo abs(-5);
echo round(3.7);
echo floor(3.7);
echo ceil(3.2);
' "数学函数" "函数"

test_script '
echo max(1, 5, 3);
echo min(1, 5, 3);
echo rand(1, 100);
' "max_min_rand" "函数"

test_script '
echo time();
' "time" "函数"

test_script '
echo date("Y-m-d H:i:s");
' "date" "函数"

test_script '
define("MY_CONST", 42);
echo MY_CONST;
' "define" "常量"

test_script '
const PI = 3.14159;
echo PI;
' "const常量" "常量"

# ===== 复杂嵌套测试 =====

test_script '
$result = 0;
for ($i = 1; $i <= 10; $i++) {
    if ($i % 2 == 0) {
        $result += $i;
    }
}
echo $result;
' "for_if" "循环"

test_script '
$arr = [];
for ($i = 0; $i < 10; $i++) {
    if ($i % 2 == 0) {
        $arr[] = $i;
    }
}
echo implode(",", $arr);
' "for_if_array" "循环"

test_script '
function test($a, $b = 5, $c = 10) {
    return $a + $b + $c;
}
echo test(1);
echo test(1, 2);
echo test(1, 2, 3);
' "默认参数" "函数"

test_script '
$x = 1;
function test() {
    global $x;
    $x = 100;
}
test();
echo $x;
' "全局变量修改" "全局变量"

test_script '
$x = 10;
$y = $x;
$y = 20;
echo $x;
echo $y;
' "值传递" "变量"

test_script '
$arr = [1, 2, 3];
$arr2 = $arr;
$arr2[0] = 100;
echo $arr[0];
echo $arr2[0];
' "数组值传递" "数组"

test_script '
$str = "original";
$str2 = $str;
$str2 = "modified";
echo $str;
echo $str2;
' "字符串值传递" "字符串"

# ===== 更多复杂场景 =====

test_script '
$arr = [1, 2, 3, 4, 5];
$sum = 0;
foreach ($arr as $v) {
    $sum += $v;
}
echo $sum;
' "foreach_sum" "数组"

test_script '
$dict = ["a" => 1, "b" => 2, "c" => 3];
$sum = 0;
foreach ($dict as $k => $v) {
    $sum += $v;
}
echo $sum;
' "foreach_kv" "数组"

test_script '
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        echo "$i$j ";
    }
}
' "嵌套循环" "循环"

test_script '
$i = 0;
while ($i < 5) {
    echo $i;
    $i++;
}
' "while循环" "循环"

test_script '
$i = 0;
do {
    echo $i;
    $i++;
} while ($i < 5);
' "do_while" "循环"

test_script '
$x = 5;
if ($x > 0) {
    echo "positive";
} else if ($x < 0) {
    echo "negative";
} else {
    echo "zero";
}
' "if_elseif_else" "控制流"

test_script '
$x = 2;
switch ($x) {
    case 1:
        echo "one";
        break;
    case 2:
        echo "two";
        break;
    default:
        echo "other";
}
' "switch" "控制流"

test_script '
$x = 1;
$result = match($x) {
    1 => "one",
    2 => "two",
    default => "other",
};
echo $result;
' "match" "控制流"

test_script '
$a = true;
$b = false;
$c = true;
echo ($a && $b) || $c ? "true" : "false";
' "复杂布尔" "表达式"

test_script '
echo "Result: " . (5 + 3);
' "字符串表达式" "字符串"

test_script '
$arr = [1, [2, [3, 4]], 5];
echo count($arr, COUNT_RECURSIVE);
' "多维数组" "数组"

echo ""
echo "========================================="
echo "测试完成！报告保存在: $REPORT_FILE"
echo "========================================="
tail -60 "$REPORT_FILE"
