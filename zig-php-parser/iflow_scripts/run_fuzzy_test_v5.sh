#!/bin/bash

# AOT 模糊测试脚本生成器 v6 - 持续自动测试
# 自动生成并执行测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=206

REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"

# 自动测试单个脚本
auto_test() {
    local php_code="$1"
    local desc="$2"
    local category="$3"
    
    local script_path="$SCRIPT_DIR/test_${COUNTER}.php"
    local php_out="$SCRIPT_DIR/test_${COUNTER}_php.out"
    local interp_out="$SCRIPT_DIR/test_${COUNTER}_interp.out"
    local aot_out="$SCRIPT_DIR/test_${COUNTER}_aot.out"
    local aot_binary="$SCRIPT_DIR/test_${COUNTER}_aot"
    
    cat > "$script_path" << 'ENDPHP'
<?php
ENDPHP
    echo "$php_code" >> "$script_path"
    echo "?>" >> "$script_path"
    
    $TIMEOUT 30s $PHP "$script_path" > "$php_out" 2>&1
    PHP_EXIT=$?
    PHP_RESULT=$(cat "$php_out")
    
    $TIMEOUT 30s "$INTERPRETER" "$script_path" 2>&1 | head -1 > "$interp_out" 2>&1
    INTERP_EXIT=$?
    INTERP_RESULT=$(cat "$interp_out")
    
    rm -rf "$SCRIPT_DIR/.zigphp_aot_build"
    $TIMEOUT 30s "$INTERPRETER" --compile --output="$aot_binary" "$script_path" > "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" 2>&1
    AOT_COMPILE_EXIT=$?
    
    if [ $AOT_COMPILE_EXIT -eq 0 ] && [ -x "$aot_binary" ]; then
        $TIMEOUT 30s "$aot_binary" > "$aot_out" 2>&1
        AOT_EXIT=$?
        AOT_RESULT=$(cat "$aot_out")
    else
        AOT_EXIT=1
        AOT_RESULT="[编译失败]"
    fi
    
    if [ $PHP_EXIT -ne 0 ]; then
        STATUS="PHP_ERROR"
    elif [ $INTERP_EXIT -ne 0 ]; then
        STATUS="INTERP_ERROR"
    elif [ $AOT_COMPILE_EXIT -ne 0 ]; then
        STATUS="AOT_COMPILE_ERROR"
    elif [ $AOT_EXIT -ne 0 ]; then
        STATUS="AOT_RUNTIME_ERROR"
    elif [ "$INTERP_RESULT" != "$PHP_RESULT" ]; then
        STATUS="INTERP_MISMATCH"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        STATUS="RESULT_MISMATCH"
    else
        STATUS="PASS"
    fi
    
    if [ $AOT_COMPILE_EXIT -ne 0 ]; then
        ERROR_INFO=$(cat "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" 2>/dev/null | grep -i "error" | head -1 | cut -c1-60)
    elif [ $AOT_EXIT -ne 0 ]; then
        ERROR_INFO="AOT运行时错误"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        ERROR_INFO="结果不一致"
    else
        ERROR_INFO="-"
    fi
    
    echo "| $COUNTER | test_$COUNTER.php | $category | ${PHP_RESULT:0:30} | ${INTERP_RESULT:0:30} | ${AOT_RESULT:0:30} | $STATUS | ${ERROR_INFO:0:50} |" >> "$REPORT_FILE"
    
    echo "[$COUNTER] $STATUS: $desc"
    
    COUNTER=$((COUNTER + 1))
}

# ===== 批量生成复杂测试 =====

# 基础类型测试
auto_test '\$x = 123; echo \$x;' "整数赋值" "基础"
auto_test '\$x = 3.14; echo \$x;' "浮点数赋值" "基础"
auto_test '\$x = "hello"; echo \$x;' "字符串赋值" "基础"
auto_test '\$x = true; echo \$x;' "布尔赋值" "基础"
auto_test '\$x = null; echo isset(\$x) ? "set" : "null";' "null赋值" "基础"

# 算术运算
auto_test 'echo 10 + 5;' "加法" "运算"
auto_test 'echo 10 - 5;' "减法" "运算"
auto_test 'echo 10 * 5;' "乘法" "运算"
auto_test 'echo 10 / 5;' "除法" "运算"
auto_test 'echo 10 % 3;' "取模" "运算"

# 复合赋值
auto_test '\$x = 10; \$x += 5; echo \$x;' "加等于" "运算"
auto_test '\$x = 10; \$x -= 5; echo \$x;' "减等于" "运算"
auto_test '\$x = 10; \$x *= 5; echo \$x;' "乘等于" "运算"
auto_test '\$x = "hello"; \$x .= " world"; echo \$x;' "字符串连接等于" "运算"

# 比较运算
auto_test 'echo 5 > 3 ? "yes" : "no";' "大于" "比较"
auto_test 'echo 5 < 3 ? "yes" : "no";' "小于" "比较"
auto_test 'echo 5 == 5 ? "yes" : "no";' "等于" "比较"
auto_test 'echo 5 != 3 ? "yes" : "no";' "不等于" "比较"
auto_test 'echo 5 >= 5 ? "yes" : "no";' "大于等于" "比较"
auto_test 'echo 5 <= 5 ? "yes" : "no";' "小于等于" "比较"

# 逻辑运算
auto_test 'echo true && true ? "yes" : "no";' "逻辑与" "逻辑"
auto_test 'echo false || true ? "yes" : "no";' "逻辑或" "逻辑"
auto_test 'echo !false ? "yes" : "no";' "逻辑非" "逻辑"

# 位运算
auto_test 'echo 5 & 3;' "位与" "位运算"
auto_test 'echo 5 | 3;' "位或" "位运算"
auto_test 'echo 5 ^ 3;' "位异或" "位运算"
auto_test 'echo ~5;' "位非" "位运算"
auto_test 'echo 5 << 2;' "左移" "位运算"
auto_test 'echo 20 >> 2;' "右移" "位运算"

# 递增递减
auto_test '\$x = 5; echo ++\$x;' "前缀递增" "运算"
auto_test '\$x = 5; echo \$x++;' "后缀递增" "运算"
auto_test '\$x = 5; echo --\$x;' "前缀递减" "运算"
auto_test '\$x = 5; echo \$x--;' "后缀递减" "运算"

# 数组基本操作
auto_test '\$arr = [1, 2, 3]; echo \$arr[0];' "数组访问" "数组"
auto_test '\$arr = [1, 2, 3]; \$arr[0] = 10; echo \$arr[0];' "数组修改" "数组"
auto_test '\$arr = []; \$arr[] = 1; \$arr[] = 2; echo count(\$arr);' "数组push" "数组"
auto_test '\$arr = [1, 2, 3]; echo count(\$arr);' "数组count" "数组"

# 关联数组
auto_test '\$arr = ["a" => 1, "b" => 2]; echo \$arr["a"];' "关联数组访问" "数组"
auto_test '\$arr = ["a" => 1]; \$arr["b"] = 2; echo \$arr["b"];' "关联数组修改" "数组"

# 循环
auto_test 'for (\$i = 0; \$i < 5; \$i++) { echo \$i; }' "for循环" "循环"
auto_test '\$i = 0; while (\$i < 5) { echo \$i; \$i++; }' "while循环" "循环"
auto_test '\$i = 0; do { echo \$i; \$i++; } while (\$i < 5);' "do_while" "循环"
auto_test '\$arr = [1, 2, 3]; foreach (\$arr as \$v) { echo \$v; }' "foreach" "循环"

# 控制流
auto_test 'if (true) { echo "yes"; }' "if语句" "控制流"
auto_test 'if (false) { echo "yes"; } else { echo "no"; }' "if_else" "控制流"
auto_test '\$x = 2; if (\$x == 1) { echo "one"; } elseif (\$x == 2) { echo "two"; } else { echo "other"; }' "elseif" "控制流"
auto_test '\$x = 2; switch (\$x) { case 1: echo "one"; break; case 2: echo "two"; break; }' "switch" "控制流"
auto_test '\$x = 1; echo match(\$x) { 1 => "one", 2 => "two", default => "other" };' "match" "控制流"

# 三元运算符
auto_test 'echo true ? "yes" : "no";' "三元运算符" "表达式"
auto_test '\$x = 5; echo \$x > 0 ? (\$x > 10 ? "big" : "small") : "negative";' "嵌套三元" "表达式"

# 函数
auto_test 'function test() { return 42; } echo test();' "函数定义" "函数"
auto_test 'function add(\$a, \$b) { return \$a + \$b; } echo add(3, 4);' "函数参数" "函数"
auto_test 'function def(\$x = 5) { return \$x; } echo def();' "默认参数" "函数"
auto_test 'function add(\$a, \$b) { return \$a + \$b; } \$fn = "add"; echo \$fn(3, 4);' "可变函数" "函数"

# 字符串操作
auto_test 'echo "hello" . " world";' "字符串连接" "字符串"
auto_test '\$str = "hello"; echo \$str[0];' "字符串索引" "字符串"
auto_test '\$str = "hello"; \$str[0] = "H"; echo \$str;' "字符串修改" "字符串"

# 类型转换
auto_test '\$x = "5"; echo \$x + 3;' "字符串转数字" "类型"
auto_test '\$x = 5; echo (string)\$x;' "数字转字符串" "类型"
auto_test '\$x = 1; echo (bool)\$x;' "转布尔" "类型"

# 空合并
auto_test '\$x = null; echo \$x ?? "default";' "空合并" "运算符"
auto_test '\$x = "value"; echo \$x ?? "default";' "非空合并" "运算符"

# continue/break
auto_test 'for (\$i = 0; \$i < 5; \$i++) { if (\$i == 2) continue; echo \$i; }' "continue" "控制流"
auto_test 'for (\$i = 0; \$i < 5; \$i++) { if (\$i == 2) break; echo \$i; }' "break" "控制流"

# 全局变量
auto_test '\$x = 1; function test() { global \$x; echo \$x; } test();' "全局变量读取" "全局"
auto_test '\$x = 1; function test() { global \$x; \$x = 100; } test(); echo \$x;' "全局变量修改" "全局"

# 静态变量
auto_test 'function counter() { static \$c = 0; \$c++; return \$c; } echo counter(); echo counter();' "静态变量" "函数"

# 复杂表达式
auto_test 'echo (1 + 2) * 3 - 4 / 2;' "复杂算术" "表达式"
auto_test 'echo 1 < 2 && 2 < 3 || 3 > 4;' "复杂逻辑" "表达式"
auto_test '\$arr = [1, 2, 3]; echo \$arr[0] + \$arr[count(\$arr) - 1];' "数组表达式" "表达式"

# 更多循环
auto_test 'for (\$i = 0; \$i < 3; \$i++) { for (\$j = 0; \$j < 3; \$j++) { echo "\$i\$j "; } }' "嵌套循环" "循环"
auto_test '\$arr = [[1, 2], [3, 4]]; echo \$arr[1][0];' "二维数组" "数组"

# 递归
auto_test 'function fib(\$n) { if (\$n <= 1) return \$n; return fib(\$n-1) + fib(\$n-2); } echo fib(10);' "斐波那契递归" "递归"

# 更多内置函数
auto_test 'echo abs(-5);' "abs" "函数"
auto_test 'echo round(3.7);' "round" "函数"
auto_test 'echo floor(3.7);' "floor" "函数"
auto_test 'echo ceil(3.2);' "ceil" "函数"
auto_test 'echo max(1, 5, 3);' "max" "函数"
auto_test 'echo min(1, 5, 3);' "min" "函数"

# 边界测试
auto_test '\$x = 0; echo \$x;' "零值" "边界"
auto_test '\$x = -1; echo \$x;' "负数" "边界"
auto_test '\$arr = []; echo count(\$arr);' "空数组" "边界"
auto_test '\$str = ""; echo strlen(\$str);' "空字符串" "边界"

# 更多数组测试
auto_test '\$a = [1, 2]; \$b = [3, 4]; \$c = array_merge(\$a, \$b); echo implode(",", \$c);' "array_merge" "函数"
auto_test '\$arr = [3, 1, 2]; sort(\$arr); echo implode(",", \$arr);' "sort" "函数"

echo ""
echo "========================================="
echo "测试完成！共 $(($COUNTER - 206)) 个测试用例"
echo "报告: $REPORT_FILE"
echo "========================================="
tail -60 "$REPORT_FILE"
