#!/bin/bash

# AOT 模糊测试脚本 v23 - 编号从1000000开始

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1000000

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
    
    if [ "$STATUS" = "PASS" ]; then
        echo "[$COUNTER] PASS: $desc"
        rm -f "$script_path" "$php_out" "$interp_out" "$aot_out" "$aot_binary" "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log"
        COUNTER=$((COUNTER + 1))
        return
    fi
    
    if [ $AOT_COMPILE_EXIT -ne 0 ]; then
        ERROR_INFO=$(cat "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" 2>/dev/null | head -3 | tr '\n' ' ' | cut -c1-80)
    elif [ $AOT_EXIT -ne 0 ]; then
        ERROR_INFO="AOT运行时错误"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        ERROR_INFO="结果不一致"
    else
        ERROR_INFO="-"
    fi
    
    echo "| $COUNTER | test_$COUNTER.php | $category | ${PHP_RESULT:0:30} | ${INTERP_RESULT:0:30} | ${AOT_RESULT:0:30} | $STATUS | ${ERROR_INFO:0:60} |" >> "$REPORT_FILE"
    
    echo "[$COUNTER] $STATUS: $desc"
    
    COUNTER=$((COUNTER + 1))
}

# 测试用例 - 1000000开始

auto_test '$arr = array(); for ($i = 1; $i <= 20; $i++) { $arr[] = $i * $i; } echo array_sum($arr);' "20个平方和" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 30; $i++) { if ($i % 3 == 0) $arr[] = $i; } echo array_sum($arr);' "30内3的倍数和" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 50; $i++) { if ($i % 5 == 0 && $i % 7 == 0) $arr[] = $i; } echo implode(",", $arr);' "5和7公倍数" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 100; $i++) { $sum += $i * $i; } echo $sum;' "平方和100" "循环"
auto_test '$fib = array(1, 1); for ($i = 2; $i < 15; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo $fib[14];' "第15项斐波那契" "循环"
auto_test '$arr = array(3, 7, 2, 9, 1, 5, 8, 4); sort($arr); echo $arr[0];' "排序取最小" "函数"
auto_test '$arr = array(3, 7, 2, 9, 1, 5, 8, 4); rsort($arr); echo $arr[0];' "倒序取最大" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr);' "数组求和5" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5, 6); echo array_product($arr);' "数组乘积6" "函数"
auto_test '$str = "hello world"; echo strlen($str);' "字符串长度3" "函数"
auto_test '$str = "HELLO"; echo strtolower($str);' "转小写2" "函数"
auto_test '$str = "hello"; echo strtoupper($str);' "转大写2" "函数"
auto_test '$str = "hello world"; echo ucwords($str);' "首字母大写2" "函数"
auto_test '$str = "hello"; echo ucfirst($str);' "首字母大写3" "函数"
auto_test '$str = "HELLO"; echo lcfirst($str);' "首字母小写" "函数"
auto_test '$str = "hello"; echo strrev($str);' "字符串反转2" "函数"
auto_test '$str = "a,b,c,d"; $arr = explode(",", $str); echo count($arr);' "逗号分割" "函数"
auto_test '$arr = array("a", "b", "c"); echo implode("-", $arr);' "数组连接2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo in_array(3, $arr) ? "yes" : "no";' "查找3" "函数"
auto_test '$arr = array("a" => 1, "b" => 2); echo array_key_exists("a", $arr) ? "yes" : "no";' "键存在检测" "函数"
auto_test '$arr = array(5, 3, 8, 1, 9); sort($arr); echo implode(",", $arr);' "排序5元素" "函数"
auto_test '$arr = array(5, 3, 8, 1, 9); rsort($arr); echo implode(",", $arr);' "倒序5元素" "函数"
auto_test '$arr = array("c" => 3, "a" => 1, "b" => 2); ksort($arr); echo implode(",", array_keys($arr));' "键排序" "函数"
auto_test '$arr = array("c" => 3, "a" => 1, "b" => 2); asort($arr); echo implode(",", $arr);' "值排序" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_slice($arr, 1, 2);' "切片2元素" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); array_splice($arr, 1, 2); echo implode(",", $arr);' "删除中间元素" "函数"
auto_test '$arr1 = array(1, 2); $arr2 = array(3, 4, 5); echo implode(",", array_merge($arr1, $arr2));' "合并数组" "函数"
auto_test '$arr = array(1, 2, 3); echo implode(",", array_reverse($arr));' "反转数组" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_filter($arr, function($x) { return $x > 3; }));' "过滤大于3" "函数"
auto_test '$arr = array(1, 2, 3); echo end($arr);' "取最后元素" "函数"
auto_test '$arr = array(1, 2, 3); echo current($arr); next($arr); echo current($arr);' "指针操作2" "函数"
auto_test '$x = 17; $y = 5; echo intdiv($x, $y);' "整数除法2" "函数"
auto_test '$x = 17; $y = 5; echo $x % $y;' "取模2" "表达式"
auto_test '$x = -10; echo abs($x);' "绝对值2" "函数"
auto_test '$x = 3.7; echo floor($x);' "向下取整" "函数"
auto_test '$x = 3.2; echo ceil($x);' "向上取整" "函数"
auto_test '$x = 3.5; echo round($x);' "四舍五入" "函数"
auto_test '$x = 2; echo pow($x, 10);' "2的10次方" "函数"
auto_test '$x = 16; echo sqrt($x);' "平方根2" "函数"
auto_test '$arr = array(3, 1, 4); echo max($arr);' "最大值3" "函数"
auto_test '$arr = array(3, 1, 4); echo min($arr);' "最小值3" "函数"
auto_test '$x = 5; $x++; echo $x;' "后置递增2" "表达式"
auto_test '$x = 5; ++$x; echo $x;' "前置递增2" "表达式"
auto_test '$x = 10; $x += 7; echo $x;' "加等于2" "表达式"
auto_test '$x = 10; $x -= 3; echo $x;' "减等于2" "表达式"
auto_test '$x = 3; $x *= 4; echo $x;' "乘等于2" "表达式"
auto_test '$x = 12; $x /= 3; echo $x;' "除等于2" "表达式"
auto_test '$x = 10; $x %= 3; echo $x;' "模等于2" "表达式"
auto_test '$x = 1 and 1; echo $x;' "逻辑and2" "表达式"
auto_test '$x = 0 or 1; echo $x;' "逻辑or2" "表达式"
auto_test '$x = 1; echo !$x;' "逻辑非2" "表达式"
auto_test '$x = 6; echo $x & 3;' "按位与2" "表达式"
auto_test '$x = 6; echo $x | 3;' "按位或2" "表达式"
auto_test '$x = 6; echo $x ^ 3;' "异或2" "表达式"
auto_test '$x = 2; echo $x << 3;' "左移2" "表达式"
auto_test '$x = 16; echo $x >> 2;' "右移2" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum($arr) / count($arr);' "平均值3" "函数"
auto_test '$arr = range(1, 15); echo array_sum($arr);' "1到15和" "函数"
auto_test '$arr = range(1, 25); $sum = 0; foreach ($arr as $v) { if ($v % 2 == 0) $sum += $v; } echo $sum;' "25内偶数和" "循环"
auto_test '$arr = range(1, 30); $sum = 0; foreach ($arr as $v) { if ($v % 3 == 0) $sum += $v; } echo $sum;' "30内3倍数和" "循环"
auto_test '$arr = range(1, 40); $sum = 0; foreach ($arr as $v) { if ($v % 5 == 0) $sum += $v; } echo $sum;' "40内5倍数和" "循环"
auto_test '$x = 1; while ($x < 100) { $x *= 2; } echo $x;' "while翻倍3" "循环"
auto_test '$x = 200; while ($x > 1) { $x = intdiv($x, 2); } echo $x;' "while减半3" "循环"
auto_test '$arr = array(7, 2, 9, 4, 1, 8); $min = $arr[0]; foreach ($arr as $v) { if ($v < $min) $min = $v; } echo $min;' "遍历找最小" "循环"
auto_test '$arr = array(7, 2, 9, 4, 1, 8); $max = $arr[0]; foreach ($arr as $v) { if ($v > $max) $max = $v; } echo $max;' "遍历找最大" "循环"
auto_test '$x = 2; $y = 3; $z = 4; echo ($x + $y) * $z;' "括号3" "表达式"
auto_test '$x = 5; $y = 10; $z = 15; echo $x + $y * $z - $x;' "混合运算2" "表达式"
auto_test '$arr = array(1, 2); echo count($arr) + strlen("abc");' "函数组合3" "表达式"
auto_test '$str = "a-b-c-d"; $arr = explode("-", $str); echo implode(",", $arr);' "分割连接" "函数"
auto_test '$arr = array(1, 2, 3); $arr2 = array_reverse($arr); echo implode(",", $arr2);' "反转连接" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, 0, 2));' "前2元素和" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_sum(array_slice($arr, -2));' "后2元素和" "函数"
auto_test '$str = "abc"; echo ord($str[0]);' "字符转ASCII2" "函数"
auto_test '$x = 70; echo chr($x);' "ASCII转字符2" "函数"
auto_test '$arr = array(1, 2, 3); $sum = 0; foreach ($arr as $v) { $sum += $v; } echo $sum;' "foreach求和2" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; $i = 0; while ($i < count($arr)) { $sum += $arr[$i]; $i++; } echo $sum;' "while遍历2" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 15; $i++) { $arr[] = $i; } echo array_sum($arr);' "创建数组15" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 12; $i++) { if ($i % 2 == 0) $arr[] = $i; } echo implode(",", $arr);' "筛选偶数12" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $found = false; foreach ($arr as $v) { if ($v == 4) { $found = true; break; } } echo $found ? "found" : "not";' "查找4" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $count = 0; foreach ($arr as $v) { if ($v > 2) $count++; } echo $count;' "计数大于2" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v * 3; } echo $sum;' "3倍求和" "循环"
auto_test '$arr = array(1, 2, 2, 3, 3, 3); echo implode(",", array_unique($arr));' "去重3" "函数"
auto_test '$arr = array(1, 2, 3); echo array_count_values($arr);' "计数2" "函数"
auto_test '$arr = array(1, 2, 3, 2, 1); echo max(array_count_values($arr));' "最多次数2" "函数"
auto_test '$arr = array("a", "b", "c"); echo join(",", $arr);' "join2" "函数"
auto_test '$str = "hello"; echo join("", str_split($str));' "分割合并2" "函数"
auto_test '$arr = array(); for ($i = 1; $i <= 8; $i++) { $arr[] = $i * $i; } echo implode(",", $arr);' "平方数列8" "循环"
auto_test '$arr = array(2, 4, 6, 8, 10); echo array_sum($arr);' "偶数和2" "函数"
auto_test '$arr = array(1, 3, 5, 7, 9); echo array_sum($arr);' "奇数和2" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_filter($arr, function($x) { return $x > 5; }));' "大于5求和" "函数"
auto_test '$arr = range(1, 8); $mapped = array_map(function($x) { return $x * $x; }, $arr); echo implode(",", $mapped);' "平方映射" "函数"
auto_test '$arr = array(1, 2, 3, 4); echo end($arr); prev($arr); echo current($arr);' "指针操作3" "函数"
auto_test '$str = "abc"; echo str_pad($str, 6, "-");' "右填充2" "函数"
auto_test '$str = "abc"; echo str_pad($str, 6, "-", STR_PAD_LEFT);' "左填充2" "函数"
auto_test '$str = "test"; echo str_repeat($str, 3);' "重复3次" "函数"
auto_test '$str = "hello"; echo substr($str, 1, 2);' "截取2字符" "函数"
auto_test '$str = "hello"; echo substr($str, -3);' "末尾3字符" "函数"
auto_test '$arr = array(1, 2, 3); echo count($arr) + array_sum($arr);' "计数加求和" "表达式"
auto_test '$arr = array(1, 2, 3, 4); echo max($arr) - min($arr);' "极差" "函数"
auto_test '$x = 100; $y = 50; echo $x - $y + 25;' "加减混合2" "表达式"
auto_test '$x = 7; $y = 3; echo $x * $y + $x / $y;' "乘除混合2" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = 0; $i < count($arr); $i++) { $sum += $arr[$i]; } echo $sum;' "for遍历求和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $product = 1; foreach ($arr as $v) { $product *= $v; } echo $product;' "foreach乘积" "循环"
auto_test '$n = 10; $fact = 1; for ($i = 1; $i <= $n; $i++) { $fact *= $i; } echo $fact;' "10的阶乘2" "循环"
auto_test '$n = 8; $fib = array(1, 1); for ($i = 2; $i < $n; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo implode(",", $fib);' "斐波那契数列" "循环"
auto_test '$arr = array(5, 8, 2, 9, 1, 7, 3, 6, 4); sort($arr); echo implode(",", $arr);' "9数排序" "函数"
auto_test '$arr = array(1 => "a", 0 => "b", 2 => "c"); ksort($arr); echo implode(",", $arr);' "关联键排序" "函数"
auto_test '$arr = array(3 => "c", 1 => "a", 2 => "b"); asort($arr); echo implode(",", $arr);' "关联值排序" "函数"

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
