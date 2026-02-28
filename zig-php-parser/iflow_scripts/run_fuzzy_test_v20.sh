#!/bin/bash

# AOT 模糊测试脚本 v20 - 控制流测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1238

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

# 1238-1337 控制流测试

auto_test '$x = 5; if ($x > 3) { echo "big"; } else { echo "small"; }' "if-else" "控制流"
auto_test '$x = 2; if ($x > 3) { echo "big"; } else { echo "small"; }' "if-else2" "控制流"
auto_test '$x = 5; if ($x > 10) { echo "A"; } elseif ($x > 5) { echo "B"; } else { echo "C"; }' "elseif链" "控制流"
auto_test '$x = 7; if ($x > 10) { echo "A"; } elseif ($x > 5) { echo "B"; } else { echo "C"; }' "elseif中" "控制流"
auto_test '$x = 12; if ($x > 10) { echo "A"; } elseif ($x > 5) { echo "B"; } else { echo "C"; }' "elseif首" "控制流"
auto_test '$x = 1; switch($x) { case 1: echo "one"; break; case 2: echo "two"; break; default: echo "other"; }' "switch1" "控制流"
auto_test '$x = 2; switch($x) { case 1: echo "one"; break; case 2: echo "two"; break; default: echo "other"; }' "switch2" "控制流"
auto_test '$x = 5; switch($x) { case 1: echo "one"; break; case 2: echo "two"; break; default: echo "other"; }' "switch默认" "控制流"
auto_test '$x = "hello"; switch($x) { case "hello": echo "hi"; break; case "world": echo "yo"; break; default: echo "?"; }' "switch字符串" "控制流"
auto_test '$x = "test"; switch($x) { case "hello": echo "hi"; break; case "world": echo "yo"; break; default: echo "?"; }' "switch串默认" "控制流"
auto_test '$i = 0; while ($i < 5) { echo $i; $i++; }' "while循环" "循环"
auto_test '$i = 0; while ($i < 5) { echo $i; $i++; }' "while5次" "循环"
auto_test '$i = 5; while ($i > 0) { echo $i; $i--; }' "while倒序" "循环"
auto_test '$i = 0; do { echo $i; $i++; } while ($i < 3);' "do-while" "循环"
auto_test '$i = 0; do { echo $i; $i++; } while ($i < 3);' "do-while3" "循环"
auto_test '$result = ""; for ($i = 1; $i <= 3; $i++) { $result .= $i; } echo $result;' "for连接" "循环"
auto_test '$result = ""; for ($i = 1; $i <= 5; $i++) { $result .= $i; } echo $result;' "for5次" "循环"
auto_test '$result = ""; for ($i = 5; $i >= 1; $i--) { $result .= $i; } echo $result;' "for倒序" "循环"
auto_test '$arr = array(1, 2, 3); $result = ""; foreach ($arr as $v) { $result .= $v; } echo $result;' "foreach连接" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $result = ""; foreach ($arr as $v) { $result .= $v; } echo $result;' "foreach5次" "循环"
auto_test '$arr = array("a", "b", "c"); $result = ""; foreach ($arr as $v) { $result .= $v; } echo $result;' "foreach串" "循环"
auto_test '$arr = array("x" => 1, "y" => 2); $result = ""; foreach ($arr as $k => $v) { $result .= $k . $v; } echo $result;' "foreach键值" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { if ($v % 2 == 0) $sum += $v; } echo $sum;' "foreach偶数和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; foreach ($arr as $v) { $sum += $v; if ($sum > 6) break; } echo $sum;' "foreach break" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $result = ""; foreach ($arr as $v) { if ($v == 3) continue; $result .= $v; } echo $result;' "foreach continue" "循环"
auto_test '$i = 0; $sum = 0; while (true) { $i++; $sum += $i; if ($i >= 5) break; } echo $sum;' "while break" "循环"
auto_test '$i = 0; $result = ""; while ($i < 5) { $i++; if ($i == 3) continue; $result .= $i; } echo $result;' "while continue" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 10; $i++) { if ($i % 3 == 0) continue; $sum += $i; } echo $sum;' "for continue" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 10; $i++) { if ($i > 7) break; $sum += $i; } echo $sum;' "for break" "循环"
auto_test '$arr = array(1, 2); foreach ($arr as &$v) { $v *= 2; } echo implode(",", $arr);' "foreach引用" "循环"
auto_test '$arr = array(1, 2, 3); foreach ($arr as $k => $v) { echo $k . ":" . $v . ";"; }' "foreach遍历" "循环"
auto_test '$x = 5; $result = $x > 3 ? "big" : "small"; echo $result;' "三元简单" "表达式"
auto_test '$x = 2; $result = $x > 3 ? "big" : "small"; echo $result;' "三元小值" "表达式"
auto_test '$x = 5; $y = 3; $result = $x > $y ? $x : $y; echo $result;' "三元取大" "表达式"
auto_test '$x = 1; $result = $x == 1 ? "one" : ($x == 2 ? "two" : "other"); echo $result;' "嵌套三元" "表达式"
auto_test '$x = 2; $result = $x == 1 ? "one" : ($x == 2 ? "two" : "other"); echo $result;' "嵌套三元2" "表达式"
auto_test '$x = 5; $result = $x == 1 ? "one" : ($x == 2 ? "two" : "other"); echo $result;' "嵌套三元默认" "表达式"
auto_test '$x = 5; $y = 10; $z = 3; $max = $x > $y ? ($x > $z ? $x : $z) : ($y > $z ? $y : $z); echo $max;' "嵌套取最大" "表达式"
auto_test '$x = 0; if ($x) { echo "true"; } else { echo "false"; }' "if零" "控制流"
auto_test '$x = 1; if ($x) { echo "true"; } else { echo "false"; }' "if一" "控制流"
auto_test '$x = ""; if ($x) { echo "true"; } else { echo "false"; }' "if空串" "控制流"
auto_test '$x = "hello"; if ($x) { echo "true"; } else { echo "false"; }' "if非空串" "控制流"
auto_test '$x = array(); if ($x) { echo "true"; } else { echo "false"; }' "if空数组" "控制流"
auto_test '$x = array(1); if ($x) { echo "true"; } else { echo "false"; }' "if非空数组" "控制流"
auto_test '$x = null; if ($x) { echo "true"; } else { echo "false"; }' "if null" "控制流"
auto_test '$x = true; if ($x) { echo "true"; } else { echo "false"; }' "if true" "控制流"
auto_test '$x = false; if ($x) { echo "true"; } else { echo "false"; }' "if false" "控制流"
auto_test '$x = 1 and 1; if ($x) { echo "true"; } else { echo "false"; }' "and结果" "控制流"
auto_test '$x = 1 or 0; if ($x) { echo "true"; } else { echo "false"; }' "or结果" "控制流"
auto_test '$x = 1 && 1; if ($x) { echo "true"; } else { echo "false"; }' "&&结果" "控制流"
auto_test '$x = 0 || 1; if ($x) { echo "true"; } else { echo "false"; }' "||结果" "控制流"
auto_test '$arr = array(1, 2, 3); if (in_array(2, $arr)) { echo "found"; } else { echo "not"; }' "in_array if" "控制流"
auto_test '$arr = array(1, 2, 3); if (in_array(5, $arr)) { echo "found"; } else { echo "not"; }' "in_array否" "控制流"
auto_test '$arr = array("a" => 1, "b" => 2); if (array_key_exists("a", $arr)) { echo "yes"; } else { echo "no"; }' "key_exists if" "控制流"
auto_test '$arr = array("a" => 1, "b" => 2); if (array_key_exists("c", $arr)) { echo "yes"; } else { echo "no"; }' "key_exists否" "控制流"
auto_test '$x = 5; if ($x > 0 && $x < 10) { echo "in range"; } else { echo "out"; }' "复合条件" "控制流"
auto_test '$x = 15; if ($x > 0 && $x < 10) { echo "in range"; } else { echo "out"; }' "复合条件否" "控制流"
auto_test '$x = 5; if ($x < 0 || $x > 10) { echo "out"; } else { echo "in range"; }' "或条件" "控制流"
auto_test '$x = 5; if ($x < 0 || $x > 10) { echo "out"; } else { echo "in range"; }' "或条件真" "控制流"
auto_test '$x = 5; if (!($x > 10)) { echo "not big"; } else { echo "big"; }' "非条件" "控制流"
auto_test '$x = 15; if (!($x > 10)) { echo "not big"; } else { echo "big"; }' "非条件2" "控制流"
auto_test '$i = 0; $sum = 0; while ($i < 100) { $i++; $sum += $i; } echo $sum;' "1到100和" "循环"
auto_test '$i = 0; $product = 1; while ($i < 10) { $i++; $product *= $i; } echo $product;' "10阶乘" "循环"
auto_test '$fib = array(1, 1); for ($i = 2; $i < 20; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo $fib[19];' "第20斐波那契" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 50; $i++) { if ($i % 7 == 0) $sum += $i; } echo $sum;' "50内7倍数" "循环"
auto_test '$count = 0; for ($i = 1; $i <= 30; $i++) { if ($i % 3 == 0 && $i % 5 == 0) $count++; } echo $count;' "30内15倍数" "循环"
auto_test '$arr = array(1, 5, 3, 8, 2); $max = $arr[0]; for ($i = 1; $i < count($arr); $i++) { if ($arr[$i] > $max) $max = $arr[$i]; } echo $max;' "找最大" "循环"
auto_test '$arr = array(1, 5, 3, 8, 2); $min = $arr[0]; for ($i = 1; $i < count($arr); $i++) { if ($arr[$i] < $min) $min = $arr[$i]; } echo $min;' "找最小" "循环"
auto_test '$prime = true; for ($i = 2; $i <= 29; $i++) { if (29 % $i == 0 && $i != 29) { $prime = false; break; } } echo $prime ? "prime" : "not";' "29素数" "循环"
auto_test '$prime = true; for ($i = 2; $i <= 25; $i++) { if (25 % $i == 0 && $i != 25) { $prime = false; break; } } echo $prime ? "prime" : "not";' "25非素数" "循环"
auto_test '$sum = 0; for ($i = 1; $i <= 20; $i++) { $sum += $i * $i; } echo $sum;' "平方和20" "循环"
auto_test '$result = 1; for ($i = 1; $i <= 12; $i++) { $result *= $i; } echo $result;' "12阶乘" "循环"
auto_test '$sum = 0; $i = 1; while ($i <= 25) { $sum += $i; $i++; } echo $sum;' "1到25和while" "循环"
auto_test '$sum = 0; $i = 1; do { $sum += $i; $i++; } while ($i <= 25); echo $sum;' "1到25dowhile" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 15; $i++) { if ($i % 2 != 0) $arr[] = $i; } echo implode(",", $arr);' "15内奇数" "循环"
auto_test '$arr = array(); for ($i = 1; $i <= 15; $i++) { if ($i % 2 == 0) $arr[] = $i; } echo implode(",", $arr);' "15内偶数" "循环"
auto_test '$sum = 0; foreach (range(1, 10) as $v) { $sum += $v; } echo $sum;' "range求和" "循环"
auto_test '$product = 1; foreach (range(1, 8) as $v) { $product *= $v; } echo $product;' "range乘积" "循环"
auto_test '$arr = array(1, 2, 3); $sum = array_sum($arr); $avg = $sum / count($arr); echo $avg;' "数组平均" "表达式"
auto_test '$arr = array(1, 2, 3, 4); $sum = array_sum($arr); $avg = $sum / count($arr); echo $avg;' "数组平均4" "表达式"
auto_test '$x = 10; $y = 3; echo intdiv($x, $y); echo $x % $y;' "除法和余数" "表达式"
auto_test '$x = 17; $y = 5; echo intdiv($x, $y); echo $x % $y;' "17除5" "表达式"
auto_test '$x = 100; $y = 7; echo intdiv($x, $y); echo $x % $y;' "100除7" "表达式"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); sort($arr); echo $arr[0] . "," . $arr[7];' "排序极值" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); rsort($arr); echo $arr[0] . "," . $arr[7];' "倒序极值" "函数"
auto_test '$arr = range(1, 10); echo array_sum($arr) / count($arr);' "1到10平均" "函数"
auto_test '$arr = range(1, 20); echo array_sum($arr) / count($arr);' "1到20平均" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo in_array(3, $arr) && in_array(7, $arr) ? "both" : "not";' "多条件查找" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo in_array(3, $arr) || in_array(7, $arr) ? "found" : "not";' "或查找" "表达式"
auto_test '$x = 5; $y = 10; echo ($x + $y) / 2;' "平均数" "表达式"
auto_test '$x = 3; $y = 6; $z = 9; echo ($x + $y + $z) / 3;' "三数平均" "表达式"
auto_test '$x = 2; echo $x ** 3 + $x ** 2 + $x + 1;' "多项式" "表达式"
auto_test '$x = 1; echo $x * 3 + $x * 2 + $x + 1;' "多项式2" "表达式"
auto_test '$arr = array(1 => "a", 2 => "b", 3 => "c"); echo implode(",", $arr);' "数字键数组" "数组"
auto_test '$arr = array("a", "b", "c"); echo $arr[0] . $arr[1] . $arr[2];' "数组连接" "数组"
auto_test '$arr = array("a", "b", "c", "d", "e"); echo $arr[0] . $arr[4];' "首尾连接" "数组"
auto_test '$arr = array(5, 3, 8, 1, 9, 2); $mid = floor(count($arr) / 2); echo $arr[$mid];' "中间元素" "数组"
auto_test '$arr = array(1, 2, 3); $arr2 = $arr; $arr2[] = 4; echo count($arr);' "复制后添加" "数组"
auto_test '$arr = array(1, 2, 3); $arr2 = $arr; $arr2[] = 4; echo count($arr2);' "复制数组计数" "数组"

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
