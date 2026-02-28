#!/bin/bash

# AOT 模糊测试脚本 v21 - 嵌套和复杂场景测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1337

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
    
    # 只记录失败的测试
    if [ "$STATUS" = "PASS" ]; then
        echo "[$COUNTER] PASS: $desc"
        COUNTER=$((COUNTER + 1))
        return
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

# 1337-1436 更多测试

auto_test '$arr = array(array(1, 2), array(3, 4)); echo $arr[0][0];' "二维数组访问" "数组"
auto_test '$arr = array(array(1, 2), array(3, 4)); echo $arr[1][1];' "二维数组访问2" "数组"
auto_test '$arr = array(array(1, 2, 3), array(4, 5, 6)); echo array_sum($arr[0]);' "二维数组求和" "数组"
auto_test '$arr = array(array(1, 2, 3), array(4, 5, 6)); echo array_sum($arr[1]);' "二维数组求和2" "数组"
auto_test '$arr = array(); $arr[] = array(1, 2); $arr[] = array(3, 4); echo count($arr);' "二维数组计数" "数组"
auto_test '$arr = array("a" => array("x" => 1, "y" => 2), "b" => array("x" => 3, "y" => 4)); echo $arr["a"]["y"];' "关联二维访问" "数组"
auto_test '$arr = array(); for ($i = 0; $i < 3; $i++) { $arr[] = $i * $i; } echo implode(",", $arr);' "循环建数组" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 7; $i++) { if ($i % 2 != 0) $arr[] = $i; } echo implode(",", $arr);' "循环筛选" "循环"
auto_test '$arr = array(); $i = 0; while ($i < 5) { $arr[] = $i * 2; $i++; } echo implode(",", $arr);' "while建数组" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 10; $i++) { for ($j = 1; $j <= 10; $j++) { $sum++; } } echo $sum;' "嵌套循环计数" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 5; $i++) { for ($j = 1; $j <= $i; $j++) { $sum += $j; } } echo $sum;' "三角求和" "循环"
auto_test '$result = ""; for ($i = 1; $i <= 5; $i++) { for ($j = 1; $j <= $i; $j++) { $result .= "*"; } $result .= "\n"; } echo $result;' "三角形打印" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 9; $i++) { for ($j = 1; $j <= 9; $j++) { if ($i == $j) $sum += $i * $j; } } echo $sum;' "对角线求和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $found = false; foreach ($arr as $v) { if ($v == 3) { $found = true; } } echo $found ? "found" : "not";' "遍历查找" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v > 2) $sum += $v; } echo $sum;' "条件遍历求和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $filtered = array(); foreach ($arr as $v) { if ($v % 2 == 0) $filtered[] = $v; } echo implode(",", $filtered);' "遍历过滤" "循环"
auto_test '$arr = array(1, 2, 3); $doubled = array(); foreach ($arr as $v) { $doubled[] = $v * 2; } echo implode(",", $doubled);' "遍历映射" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; $i = 0; while ($i < count($arr)) { $sum += $arr[$i]; $i += 2; } echo $sum;' "隔位求和" "循环"
auto_test '$arr = array(5, 4, 3, 2, 1); $sorted = $arr; sort($sorted); echo implode(",", $sorted);' "数组排序复制" "数组"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); $max = max($arr); echo $max;' "max函数" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); $min = min($arr); echo $min;' "min函数" "函数"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(4, 5, 6); echo array_sum($arr1) + array_sum($arr2);' "两数组求和" "函数"
auto_test '$arr = array(1, 2, 2, 3, 3, 3, 4); echo max(array_count_values($arr));' "最多次数" "函数"
auto_test '$str = "hello world"; $words = explode(" ", $str); echo count($words);' "单词计数" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = explode(",", $str); echo end($arr);' "分割取最后" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr) > 10 ? "big" : "small";' "数组和判断" "表达式"
auto_test '$arr = array(1, 2, 3); echo count($arr) == 3 ? "three" : "other";' "数组计数判断" "表达式"
auto_test '$x = 5; $arr = array(); for ($i = 0; $i < $x; $i++) { $arr[] = $i; } echo implode(",", $arr);' "变量控制循环" "循环"
auto_test '$n = 5; $fact = 1; for ($i = 1; $i <= $n; $i++) { $fact *= $i; } echo $fact;' "变量阶乘" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $copy = $arr; echo implode(",", $copy);' "数组复制" "数组"
auto_test '$arr1 = array(1, 2); $arr2 = $arr1; $arr2[] = 3; echo count($arr1); echo count($arr2);' "复制独立性" "数组"
auto_test '$str = "abc"; echo strtolower($str) . strtoupper($str);' "大小写组合" "函数"
auto_test '$str = "hello"; echo strlen($str) + count(array(1, 2, 3));' "长度加计数" "表达式"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr) * array_product($arr);' "和乘积" "表达式"
auto_test '$x = 10; $y = 20; echo max($x, $y) - min($x, $y);' "极差函数" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo abs(array_sum($arr) - 15);' "绝对值差" "表达式"
auto_test '$x = 3; echo ($x > 0) ? (($x % 2 == 0) ? "正偶" : "正奇") : "非正";' "嵌套三元判断" "表达式"
auto_test '$x = 4; echo ($x > 0) ? (($x % 2 == 0) ? "正偶" : "正奇") : "非正";' "嵌套三元判断2" "表达式"
auto_test '$x = -1; echo ($x > 0) ? (($x % 2 == 0) ? "正偶" : "正奇") : "非正";' "嵌套三元负" "表达式"
auto_test '$arr = array(1, 2, 3); if (count($arr) > 0 && array_sum($arr) > 0) { echo "valid"; } else { echo "invalid"; }' "复合数组判断" "控制流"
auto_test '$arr = array(); if (count($arr) > 0 && array_sum($arr) > 0) { echo "valid"; } else { echo "invalid"; }' "空数组判断" "控制流"
auto_test '$x = 5; if ($x > 0 && $x < 10 && $x % 2 == 1) { echo "odd digit"; } else { echo "other"; }' "多条件判断" "控制流"
auto_test '$x = 8; if ($x > 0 && $x < 10 && $x % 2 == 1) { echo "odd digit"; } else { echo "other"; }' "多条件判断2" "控制流"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v % 2 == 0) continue; $sum += $v; } echo $sum;' "continue过滤" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $result = ""; foreach ($arr as $v) { if ($v == 3) break; $result .= $v; } echo $result;' "foreach break" "循环"
auto_test '$i = 0; $result = ""; while ($i < 5) { $i++; if ($i == 3) continue; $result .= $i; } echo $result;' "while continue" "循环"
auto_test '$i = 0; $result = ""; while ($i < 5) { $i++; if ($i > 3) break; $result .= $i; } echo $result;' "while break" "循环"
auto_test '$arr = range(1, 10); echo array_sum(array_slice($arr, 0, 3));' "range切片求和" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_slice($arr, 5));' "range后5求和" "函数"
auto_test '$arr1 = array(1, 2, 3); $arr2 = array(3, 4, 5); echo implode(",", array_intersect($arr1, $arr2));' "数组交集" "函数"
auto_test '$arr1 = array(1, 2, 3, 4); $arr2 = array(3, 4, 5, 6); echo implode(",", array_diff($arr1, $arr2));' "数组差集" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $first = reset($arr); $last = end($arr); echo $first + $last;' "首尾和" "函数"
auto_test '$arr = array(1, 2, 3); echo array_sum($arr) / count($arr);' "平均值2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v * $v; } echo $sum;' "平方和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); echo in_array(3, $arr) ? $arr[2] : 0;' "查找取值" "表达式"
auto_test '$arr = array("a", "b", "c"); echo in_array("b", $arr) ? "found" : "not";' "字符串查找" "函数"
auto_test '$arr = array("x" => 1, "y" => 2, "z" => 3); echo array_sum($arr);' "关联数组求和" "函数"
auto_test '$arr = array("a" => 1, "b" => 2, "c" => 3); $sum = 0; foreach ($arr as $k => $v) { $sum += $v; } echo $sum;' "遍历关联求和" "循环"
auto_test '$arr = array("a" => 1, "b" => 2, "c" => 3); $keys = array_keys($arr); echo $keys[0];' "首键" "函数"
auto_test '$arr = array("a" => 1, "b" => 2, "c" => 3); $values = array_values($arr); echo $values[1];' "第二个值" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo round(array_sum($arr) / count($arr));' "四舍五入平均" "函数"
auto_test '$x = 123; echo intval($x / 10); echo $x % 10;' "各位分离" "表达式"
auto_test '$x = 123; echo intval($x / 100); echo intval(($x / 10) % 10); echo $x % 10;' "百十个" "表达式"
auto_test '$x = 5; echo $x * $x + $x;' "x平方加x" "表达式"
auto_test '$x = 10; $arr = array(); for ($i = 1; $i <= $x; $i++) { if ($x % $i == 0) $arr[] = $i; } echo implode(",", $arr);' "因数分解" "循环"
auto_test '$x = 17; $isPrime = true; for ($i = 2; $i <= sqrt($x); $i++) { if ($x % $i == 0) { $isPrime = false; break; } } echo $isPrime ? "prime" : "not";' "素数判断2" "循环"
auto_test '$arr = array(1, 1, 2, 2, 3, 3); echo implode(",", array_unique($arr));' "唯一化" "函数"
auto_test '$arr = array(1, 2, 3); echo in_array(1, $arr) && in_array(3, $arr) ? "both" : "no";' "多值检测" "表达式"
auto_test '$x = 3; echo ($x == 1) ? "one" : (($x == 2) ? "two" : (($x == 3) ? "three" : "other"));' "多层三元" "表达式"
auto_test '$x = 1; echo ($x == 1) ? "one" : (($x == 2) ? "two" : (($x == 3) ? "three" : "other"));' "多层三元2" "表达式"
auto_test '$x = 5; echo ($x == 1) ? "one" : (($x == 2) ? "two" : (($x == 3) ? "three" : "other"));' "多层三元默认" "表达式"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { $arr[] = $i; } echo array_sum($arr);' "1到10和2" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { $arr[] = $i * 2; } echo implode(",", $arr);' "偶数数组" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 10; $i++) { if ($i % 2 != 0) $arr[] = $i; } echo implode(",", $arr);' "奇数数组" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v % 2 == 0) $sum += $v; } echo $sum;' "偶数求和2" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v % 2 != 0) $sum += $v; } echo $sum;' "奇数求和2" "循环"
auto_test '$arr = range(1, 20); $evens = array_filter($arr, function($x) { return $x % 2 == 0; }); echo array_sum($evens);' "filter偶数" "函数"
auto_test '$arr = range(1, 20); $odds = array_filter($arr, function($x) { return $x % 2 != 0; }); echo array_sum($odds);' "filter奇数" "函数"
auto_test '$arr = range(1, 10); $mapped = array_map(function($x) { return $x * 10; }, $arr); echo implode(",", $mapped);' "map乘10" "函数"
auto_test '$arr = range(1, 5); echo array_reduce($arr, function($a, $b) { return $a + $b; });' "reduce求和3" "函数"
auto_test '$arr = range(1, 5); echo array_reduce($arr, function($a, $b) { return $a * $b; });' "reduce乘积2" "函数"
auto_test '$arr = range(1, 5); echo array_reduce($arr, function($a, $b) { return ($a > $b) ? $a : $b; });' "reduce最大" "函数"
auto_test '$arr = range(1, 5); echo array_reduce($arr, function($a, $b) { return ($a < $b) ? $a : $b; });' "reduce最小" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr) / 2;' "和的一半" "表达式"
auto_test '$arr = array(5, 10, 15, 20); echo array_sum($arr) / count($arr);' "4数平均" "函数"
auto_test '$x = 8; echo ($x > 5 && $x < 15) ? "in" : "out";' "范围判断" "表达式"
auto_test '$x = 20; echo ($x > 5 && $x < 15) ? "in" : "out";' "范围外判断" "表达式"
auto_test '$x = 5; echo ($x < 10 || $x > 20) ? "a" : "b";' "或范围" "表达式"
auto_test '$x = 15; echo ($x < 10 || $x > 20) ? "a" : "b";' "或范围真" "表达式"
auto_test '$x = 0; $y = $x ?: 0; echo $y;' "elvis零2" "表达式"
auto_test '$x = null; $y = $x ?: 0; echo $y;' "elvis null2" "表达式"
auto_test '$x = ""; $y = $x ?: "default"; echo $y;' "elvis空串" "表达式"
auto_test '$arr = array(0 => "a", 1 => "b", 2 => "c"); echo implode(",", $arr);' "数字键数组2" "数组"
auto_test '$arr = array(0 => "a", 1 => "b", 2 => "c"); echo count($arr);' "数字键计数" "数组"
auto_test '$arr = array(1, 2, 3); echo isset($arr[0]) && isset($arr[1]) && isset($arr[2]) ? "complete" : "incomplete";' "索引检查" "表达式"
auto_test '$arr = array(1, 2, 3); echo isset($arr[5]) ? "set" : "not";' "越界检查" "表达式"
auto_test '$str = "hello"; echo str_pad($str, 8, "*", STR_PAD_LEFT);' "左填充2" "函数"
auto_test '$str = "hello"; echo str_pad($str, 8, "*", STR_PAD_RIGHT);' "右填充2" "函数"
auto_test '$str = "hello"; echo str_pad($str, 11, "*", STR_PAD_BOTH);' "两端填充2" "函数"
auto_test '$str = "abcdef"; echo substr($str, 0, 3);' "首3字符" "函数"
auto_test '$str = "abcdef"; echo substr($str, 3);' "后3字符" "函数"
auto_test '$str = "abcdef"; echo substr($str, 1, -1);' "去首尾" "函数"
auto_test '$str = "abc"; echo str_repeat($str, 4);' "重复4次" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = explode(",", $str); echo implode("-", $arr);' "交换分隔符" "函数"
auto_test '$arr = array(1, 2, 3); echo implode(",", array_reverse($arr));' "反转字符串" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5); sort($arr); echo implode(",", $arr);' "排序输出" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5); rsort($arr); echo implode(",", $arr);' "倒序输出" "函数"
auto_test '$arr = array("b" => 2, "a" => 1, "c" => 3); asort($arr); echo implode(",", $arr);' "值排序2" "函数"
auto_test '$arr = array("b" => 2, "a" => 1, "c" => 3); arsort($arr); echo implode(",", $arr);' "值倒序2" "函数"

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
