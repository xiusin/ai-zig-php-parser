#!/bin/bash

# AOT 模糊测试脚本 v13 - 深度嵌套和复杂逻辑

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=649

REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"

auto_test() {
    local php_code="$1"
    local desc="$2"
    local category="$3"
    
    local script_path="$SCRIPT_DIR/test_${COUNTER}.php"
    local php_out="$SCRIPT_DIR/test_${COUNTER}_php.out"
    local interp_out="$SCRIPT_DIR/test_${COUNTER}_interp.out"
    local aot_out="$SCRIPT_DIR/test_${COUNTER}_aot.out"
    local aot_binary="$SCRIPT_DIR/test_${COUNTER}_aot"
    
    printf '%s\n%s%s\n' '<?php' "$php_code" '?>' > "$script_path"
    
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

# 649-720 更多深度嵌套和复杂场景

auto_test '$arr = array(array(1,2), array(3,4), array(5,6)); $sum = 0; for ($i = 0; $i < count($arr); $i++) { for ($j = 0; $j < count($arr[$i]); $j++) { $sum += $arr[$i][$j]; } } echo $sum;' "二维数组遍历" "数组"
auto_test '$matrix = array(array(1,2,3), array(4,5,6)); $sum = 0; foreach ($matrix as $row) { foreach ($row as $val) { $sum += $val; } } echo $sum;' "二维数组foreach" "数组"
auto_test '$arr = array(); for ($i = 1; $i <= 5; $i++) { $arr[] = array(); for ($j = 1; $j <= 3; $j++) { $arr[$i-1][] = $i * 10 + $j; } } echo implode(",", $arr[2]);' "创建二维数组" "数组"
auto_test '$data = array("users" => array(array("name" => "Alice", "age" => 25), array("name" => "Bob", "age" => 30))); echo $data["users"][0]["name"];' "嵌套关联数组" "数组"
auto_test '$arr = range(1, 10); $filtered = array_filter($arr, function($x) { return $x > 5; }); echo array_sum($filtered);' "filter后求和2" "函数"
auto_test '$arr = range(1, 20); $mapped = array_map(function($x) { return $x * 2; }, $arr); echo array_sum(array_slice($mapped, 0, 5));' "链式操作" "函数"
auto_test 'function recursiveSum($arr, $i = 0) { if ($i >= count($arr)) return 0; return $arr[$i] + recursiveSum($arr, $i + 1); } echo recursiveSum(array(1,2,3,4,5));' "递归求和" "递归"
auto_test 'function factorial($n) { if ($n <= 1) return 1; return $n * factorial($n - 1); } echo factorial(10);' "递归阶乘2" "递归"
auto_test 'function isEven($n) { return $n % 2 == 0; } function filterEvens($arr) { return array_filter($arr, "isEven"); } echo implode(",", filterEvens(range(1,10)));' "函数引用" "函数"
auto_test '$x = 1; $y = 2; $z = 3; echo ($x + $y) * $z - $x / 2;' "复杂表达式2" "表达式"
auto_test 'for ($i = 1; $i <= 3; $i++) { for ($j = 1; $j <= 3; $j++) { echo "$i*$j=" . ($i*$j) . " "; } echo "\n"; }' "九九乘法表" "循环"
auto_test '$arr = array(1, 2, 3); $fn = function($x, $y) { return $x + $y; }; echo $fn(1, 2);' "闭包调用" "函数"
auto_test '$x = 10; $y = 20; echo "x=$x, y=$y";' "字符串插值" "字符串"
auto_test '$name = "World"; echo "Hello, $name!";' "字符串插值2" "字符串"
auto_test '$arr = array(1, 2, 3); echo count($arr) . strlen("hello");' "多函数调用" "表达式"
auto_test '$a = 1; $b = 2; $c = 3; $d = 4; echo ($a + $b) * ($c - $d);' "括号表达式" "表达式"
auto_test '$arr = range(1, 100); $sum = 0; foreach ($arr as $v) { if ($v % 7 == 0) $sum += $v; } echo $sum;' "7的倍数求和" "循环"
auto_test 'function pow2($n) { return $n * $n; } echo pow2(5) + pow2(3);' "函数组合" "函数"
auto_test '$arr = array(1, 2, 3); echo end($arr); prev($arr); echo current($arr);' "数组指针操作" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = explode(",", $str); echo implode("-", array_reverse($arr));' "字符串反转" "函数"
auto_test '$arr = array(5, 8, 3, 1, 9, 2); sort($arr); echo implode(",", $arr);' "快速排序" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); $unique = array_unique($arr); sort($unique); echo implode(",", $unique);' "唯一值排序" "函数"
auto_test 'echo max(array(1, 5, 3)) . min(array(1, 5, 3));' "max_min函数" "函数"
auto_test '$arr = range(1, 10); echo array_reduce($arr, function($c, $i) { return $c + $i; });' "reduce求和2" "函数"
auto_test '$str = "hello"; echo ord($str[0]) . ord($str[4]);' "字符转ASCII" "函数"
auto_test '$arr = array("a", "b", "c"); echo chr(65 + count($arr));' "ASCII转字符" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_filter($arr, function($x) { return $x % 2 != 0; }));' "奇数求和2" "函数"
auto_test '$arr = range(1, 15); $filtered = array_filter($arr, function($x) { return $x % 3 == 0; }); echo array_product($filtered);' "3的倍数乘积" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $mapped = array_map(function($x) { return $x * $x; }, $arr); echo array_sum($mapped);' "平方和2" "函数"
auto_test '$str = "the quick brown fox jumps over the lazy dog"; echo strlen($str);' "字符串长度2" "函数"
auto_test '$str = "ABC"; echo strtolower($str) . strtoupper($str);' "大小写转换3" "函数"
auto_test '$arr = array(1, 2, 3); echo in_array(2, $arr) && !in_array(4, $arr) ? "yes" : "no";' "多条件in_array" "函数"
auto_test '$arr1 = array(1, 2); $arr2 = array(3, 4); $merged = array_merge($arr1, $arr2); echo array_sum($merged);' "数组合并求和" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, 2));' "slice求和2" "函数"
auto_test '$x = 0; $x += 5; $x += 3; echo $x;' "累加赋值" "表达式"
auto_test '$x = 10; $x -= 3; echo $x;' "减法赋值" "表达式"
auto_test '$x = 2; $x *= 5; echo $x;' "乘法赋值" "表达式"
auto_test '$x = 100; $x /= 4; echo $x;' "除法赋值" "表达式"
auto_test '$x = 17; $x %= 5; echo $x;' "取模赋值" "表达式"
auto_test '$x = 5; $y = $x; $x = 10; echo "$x,$y";' "值传递" "表达式"
auto_test '$arr = array(1, 2, 3); $copy = $arr; $arr[0] = 100; echo $copy[0];' "数组值传递" "数组"
auto_test '$str = "123"; echo intval($str) + 7;' "intval转换" "函数"
auto_test '$num = 456; echo strval($num) . "789";' "strval转换" "函数"
auto_test '$x = "10"; $y = 5; echo $x + $y;' "类型转换加法" "表达式"
auto_test '$arr = array(1, "a", 2, "b"); echo count($arr);' "混合数组" "数组"
auto_test '$x = 1; if ($x > 0) { if ($x > 5) { echo "big"; } else { echo "small"; } }' "嵌套if" "条件"
auto_test '$x = 7; if ($x < 10) { echo "lt"; } elseif ($x < 20) { echo "mt"; } else { echo "gt"; }' "elseif链" "条件"
auto_test '$x = 3; switch ($x) { case 1: echo "one"; break; case 2: echo "two"; break; default: echo "other"; }' "switch语句" "控制流"
auto_test '$x = "b"; switch ($x) { case "a": echo "A"; break; case "b": echo "B"; break; default: echo "C"; }' "switch字符串" "控制流"
auto_test '$arr = array(1, 2, 3, 4, 5); foreach ($arr as $v) { if ($v == 3) continue; echo "$v,"; }' "foreach_continue" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); foreach ($arr as $v) { if ($v == 4) break; echo "$v,"; }' "foreach_break" "循环"
auto_test '$sum = 0; $i = 1; while ($i <= 10) { $sum += $i; $i++; } echo $sum;' "while累加" "循环"
auto_test '$result = 1; $i = 1; while ($i <= 5) { $result *= $i; $i++; } echo $result;' "while阶乘" "循环"
auto_test '$arr = array(5, 4, 3, 2, 1); $reversed = array_reverse($arr); echo implode(",", $reversed);' "array_reverse2" "函数"
auto_test '$str = "hello"; echo str_repeat("-", 5) . $str . str_repeat("-", 5);' "字符串装饰" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -30 "$REPORT_FILE"
