#!/bin/bash

# AOT 模糊测试脚本生成器 v3
# 生成更多复杂测试用例

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=51

# 追加到报告文件
REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"

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

# ===== 更多复杂测试用例 =====

# 51. 类和对象
test_script '
class Foo {
    public \$x = 10;
    public function getX() {
        return \$this->x;
    }
}
\$obj = new Foo();
echo \$obj->getX();
' "类和对象" "OOP"

# 52. 类继承
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
\$obj = new Derived();
echo \$obj->greet();
' "类继承" "OOP"

# 53. 静态方法
test_script '
class Math {
    public static function add(\$a, \$b) {
        return \$a + \$b;
    }
}
echo Math::add(3, 4);
' "静态方法" "OOP"

# 54. 构造函数
test_script '
class Person {
    public \$name;
    public function __construct(\$name) {
        \$this->name = \$name;
    }
}
\$p = new Person("John");
echo \$p->name;
' "构造函数" "OOP"

# 55. 对象属性访问
test_script '
class Point {
    public \$x = 5;
    public \$y = 10;
}
\$p = new Point();
echo \$p->x + \$p->y;
' "对象属性" "OOP"

# 56. 对象方法链式调用
test_script '
class Builder {
    public \$value = "";
    public function add(\$s) {
        \$this->value .= \$s;
        return \$this;
    }
}
\$b = new Builder();
echo \$b->add("Hello")->add("World")->value;
' "链式调用" "OOP"

# 57. 数组排序
test_script '
\$arr = [3, 1, 4, 1, 5];
sort(\$arr);
echo implode(",", \$arr);
' "数组排序" "数组"

# 58. 数组反转
test_script '
\$arr = [1, 2, 3, 4, 5];
\$rev = array_reverse(\$arr);
echo implode(",", \$rev);
' "数组反转" "数组"

# 59. 数组合并
test_script '
\$a = [1, 2];
\$b = [3, 4];
\$c = array_merge(\$a, \$b);
echo implode(",", \$c);
' "数组合并" "数组"

# 60. 数组键值分离
test_script '
\$arr = ["a" => 1, "b" => 2];
\$keys = array_keys(\$arr);
\$vals = array_values(\$arr);
echo implode(",", \$keys) . "|" . implode(",", \$vals);
' "数组键值" "数组"

# 61. count 函数
test_script '
\$arr = [1, 2, 3, 4, 5];
echo count(\$arr);
' "count函数" "函数"

# 62. in_array 函数
test_script '
\$arr = [1, 2, 3];
echo in_array(2, \$arr) ? "yes" : "no";
echo in_array(5, \$arr) ? "yes" : "no";
' "in_array" "函数"

# 63. array_search 函数
test_script '
\$arr = ["a", "b", "c"];
echo array_search("b", \$arr);
' "array_search" "函数"

# 64. 字符串长度
test_script '
\$str = "Hello";
echo strlen(\$str);
' "strlen" "函数"

# 65. 字符串转大写
test_script '
\$str = "hello";
echo strtoupper(\$str);
' "strtoupper" "函数"

# 66. 字符串转小写
test_script '
\$str = "HELLO";
echo strtolower(\$str);
' "strtolower" "函数"

# 67. 字符串替换
test_script '
\$str = "Hello World";
echo str_replace("World", "PHP", \$str);
' "str_replace" "函数"

# 68. 字符串截取
test_script '
\$str = "Hello";
echo substr(\$str, 1, 3);
' "substr" "函数"

# 69. 字符串位置
test_script '
\$str = "Hello World";
echo strpos(\$str, "World");
' "strpos" "函数"

# 70. explode/implode
test_script '
\$str = "a,b,c";
\$arr = explode(",", \$str);
echo implode("-", \$arr);
' "explode_implode" "函数"

# 71. trim 函数
test_script '
\$str = "  hello  ";
echo trim(\$str);
' "trim" "函数"

# 72. sprintf 函数
test_script '
echo sprintf("Value: %d", 42);
' "sprintf" "函数"

# 73. printf 函数
test_script '
printf("Num: %d, Str: %s", 42, "test");
' "printf" "函数"

# 74. is_array 函数
test_script '
\$a = [1, 2];
\$b = "test";
echo is_array(\$a) ? "yes" : "no";
echo is_array(\$b) ? "yes" : "no";
' "is_array" "函数"

# 75. is_int/is_string
test_script '
\$a = 42;
\$b = "test";
echo is_int(\$a) ? "int" : "not int";
echo is_string(\$b) ? "str" : "not str";
' "is_int" "函数"

# 76. empty 函数
test_script '
\$a = "";
\$b = "test";
echo empty(\$a) ? "empty" : "not empty";
echo empty(\$b) ? "empty" : "not empty";
' "empty" "函数"

# 77. isset 函数
test_script '
\$a = null;
\$b = "test";
echo isset(\$a) ? "set" : "not set";
echo isset(\$b) ? "set" : "not set";
' "isset" "函数"

# 78. defined 函数
test_script '
define("MY_CONST", 42);
echo MY_CONST;
' "defined" "常量"

# 79. 常量定义
test_script '
const PI = 3.14;
echo PI;
' "const常量" "常量"

# 80. 匿名函数/闭包
test_script '
\$add = function(\$a, \$b) {
    return \$a + \$b;
};
echo \$add(3, 4);
' "匿名函数" "函数"

# 81. 闭包 use
test_script '
\$x = 10;
\$add = function(\$y) use (\$x) {
    return \$x + \$y;
};
echo \$add(5);
' "闭包use" "函数"

# 82. array_map
test_script '
\$arr = [1, 2, 3];
\$mapped = array_map(function(\$x) { return \$x * 2; }, \$arr);
echo implode(",", \$mapped);
' "array_map" "函数"

# 83. array_filter
test_script '
\$arr = [1, 2, 3, 4, 5];
\$filtered = array_filter(\$arr, function(\$x) { return \$x > 2; });
echo implode(",", \$filtered);
' "array_filter" "函数"

# 84. array_reduce
test_script '
\$arr = [1, 2, 3, 4];
\$sum = array_reduce(\$arr, function(\$carry, \$item) { return \$carry + \$item; }, 0);
echo \$sum;
' "array_reduce" "函数"

# 85. range 函数
test_script '
\$arr = range(1, 5);
echo implode(",", \$arr);
' "range" "函数"

# 86. shuffle 函数
test_script '
\$arr = [1, 2, 3, 4, 5];
shuffle(\$arr);
echo implode(",", \$arr);
' "shuffle" "函数"

# 87. array_sum
test_script '
\$arr = [1, 2, 3, 4, 5];
echo array_sum(\$arr);
' "array_sum" "函数"

# 88. array_product
test_script '
\$arr = [1, 2, 3, 4, 5];
echo array_product(\$arr);
' "array_product" "函数"

# 89. max/min 函数
test_script '
echo max(1, 5, 3);
echo min(1, 5, 3);
' "max_min" "函数"

# 90. abs 函数
test_script '
echo abs(-5);
echo abs(3.14);
' "abs" "函数"

# 91. round 函数
test_script '
echo round(3.7);
echo round(3.14159, 2);
' "round" "函数"

# 92. floor/ceil
test_script '
echo floor(3.7);
echo ceil(3.2);
' "floor_ceil" "函数"

# 93. pow 函数
test_script '
echo pow(2, 10);
' "pow" "函数"

# 94. sqrt 函数
test_script '
echo sqrt(16);
' "sqrt" "函数"

# 95. rand 函数
test_script '
echo rand(1, 100);
' "rand" "函数"

# 96. mt_rand 函数
test_script '
echo mt_rand(1, 100);
' "mt_rand" "函数"

# 97. time 函数
test_script '
echo time();
' "time" "函数"

# 98. microtime 函数
test_script '
echo microtime();
' "microtime" "函数"

# 99. date 函数
test_script '
echo date("Y-m-d");
' "date" "函数"

# 100. strtotime 函数
test_script '
echo strtotime("+1 day");
' "strtotime" "函数"

echo ""
echo "========================================="
echo "测试完成！报告保存在: $REPORT_FILE"
echo "========================================="
cat "$REPORT_FILE"
