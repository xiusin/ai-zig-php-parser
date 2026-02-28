#!/bin/bash

# AOT 模糊测试脚本 v18 - 继续复杂场景测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=1028

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

# 1028-1127 复杂场景测试

auto_test '$x = 100; $y = 50; echo $x - $y + 25;' "加减混合2" "表达式"
auto_test '$x = 7; $y = 3; echo $x * $y + $x / $y;' "乘除混合2" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); $sum = 0; for ($i = 0; $i < count($arr); $i++) { $sum += $arr[$i]; } echo $sum;' "for遍历求和" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $product = 1; foreach ($arr as $v) { $product *= $v; } echo $product;' "foreach乘积" "循环"
auto_test '$n = 10; $fact = 1; for ($i = 1; $i <= $n; $i++) { $fact *= $i; } echo $fact;' "10的阶乘2" "循环"
auto_test '$n = 8; $fib = array(1, 1); for ($i = 2; $i < $n; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo implode(",", $fib);' "斐波那契数列" "循环"
auto_test '$arr = array(5, 8, 2, 9, 1, 7, 3, 6, 4); sort($arr); echo implode(",", $arr);' "9数排序" "函数"
auto_test '$arr = array(1 => "a", 0 => "b", 2 => "c"); ksort($arr); echo implode(",", $arr);' "关联键排序" "函数"
auto_test '$arr = array(3 => "c", 1 => "a", 2 => "b"); asort($arr); echo implode(",", $arr);' "关联值排序" "函数"
auto_test '$str = "abc123"; echo is_numeric($str) ? "yes" : "no";' "数字字符串检测" "函数"
auto_test '$str = "123"; echo is_numeric($str) ? "yes" : "no";' "纯数字检测" "函数"
auto_test '$x = 3.14; echo is_int($x) ? "int" : "not int";' "整数检测2" "函数"
auto_test '$x = 5; echo is_float($x) ? "float" : "not float";' "浮点检测2" "函数"
auto_test '$x = null; echo is_null($x) ? "null" : "not null";' "空值检测2" "函数"
auto_test '$x = "hello"; echo gettype($x);' "获取类型2" "函数"
auto_test '$x = "123"; echo intval($x) + 7;' "intval加法" "表达式"
auto_test '$x = 3.14; echo floatval($x) * 2;' "floatval乘法" "表达式"
auto_test '$x = 123; echo strval($x) . "abc";' "strval连接" "表达式"
auto_test '$x = 1; echo (bool)$x;' "bool转换2" "表达式"
auto_test '$x = 0; echo (int)$x + 5;' "int转换加法" "表达式"
auto_test '$x = 9.5; echo (int)$x + 1;' "int转换截断" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo print_r($arr, true);' "print_r2" "函数"
auto_test '$arr = array("name" => "Tom", "age" => 25); echo print_r($arr, true);' "print_r关联" "函数"
auto_test '$arr = array(1, 2, 3); var_dump($arr);' "var_dump2" "函数"
auto_test '$str = "1,2,3"; print_r(str_getcsv($str));' "CSV解析" "函数"
auto_test '$str1 = "hello"; $str2 = "HELLO"; echo similar_text($str1, $str2);' "相似度" "函数"
auto_test '$s1 = "abc"; $s2 = "abc"; echo strcmp($s1, $s2);' "字符串比较2" "函数"
auto_test '$s1 = "abc"; $s2 = "abd"; echo strcmp($s1, $s2);' "字符串比较3" "函数"
auto_test '$s1 = "abc"; $s2 = "ABC"; echo strcasecmp($s1, $s2);' "大小写比较" "函数"
auto_test '$s1 = "abc"; $s2 = "abcdef"; echo strncmp($s1, $s2, 3);' "前3比较" "函数"
auto_test '$str = "Hello World"; echo strpos($str, "o");' "查找o位置" "函数"
auto_test '$str = "Hello World"; echo strpos($str, "o", 5);' "从5后查找" "函数"
auto_test '$str = "Hello"; echo stripos($str, "L");' "不区分大小写" "函数"
auto_test '$str = "Hello World"; echo strrpos($str, "o");' "最后o位置" "函数"
auto_test '$str = "Hello World"; echo strripos($str, "O");' "最后O位置" "函数"
auto_test '$str = "Hello World"; echo strstr($str, " ");' "查找到空格" "函数"
auto_test '$str = "HELLO"; echo stristr($str, "e");' "不区分查找" "函数"
auto_test '$str = "abcdef"; echo substr($str, 1, 3);' "截取bcd" "函数"
auto_test '$str = "abcdef"; echo substr($str, -2);' "截取最后2" "函数"
auto_test '$str = "hello"; echo substr_replace($str, "xx", 1, 2);' "替换中间" "函数"
auto_test '$str = "hello world"; echo strtr($str, "o", "0");' "字符替换" "函数"
auto_test '$arr = array("a" => "x", "b" => "y"); echo strtr("aabb", $arr);' "映射替换" "函数"
auto_test '$x = 255; echo dechex($x);' "十转十六2" "函数"
auto_test '$x = "ff"; echo hexdec($x);' "十六转十2" "函数"
auto_test '$x = 63; echo decoct($x);' "十转八2" "函数"
auto_test '$x = "77"; echo octdec($x);' "八转十2" "函数"
auto_test '$x = "1010"; echo bindec($x);' "二转十2" "函数"
auto_test '$num = 1234567; echo number_format($num);' "数字格式化" "函数"
auto_test '$num = 1234.5678; echo round($num, 2);' "四舍五入2位" "函数"
auto_test '$num = 3.14159; echo round($num, 3);' "四舍五入3位" "函数"
auto_test '$arr = array(); for ($i = 1; $i <= 20; $i++) { $arr[] = $i; } echo count($arr);' "创建20元素" "循环"
auto_test '$arr = range(1, 20); echo array_sum($arr);' "1到20求和" "函数"
auto_test '$arr = range(1, 25); $prod = 1; foreach ($arr as $v) { $prod *= $v; } echo $prod;' "1到25乘积" "循环"
auto_test '$n = 15; $fact = 1; for ($i = 1; $i <= $n; $i++) { $fact *= $i; } echo $fact;' "15阶乘" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10); echo array_sum($arr);' "1到10和2" "函数"
auto_test '$arr = array(1, 2, 3); $sum = $arr[0]; for ($i = 1; $i < count($arr); $i++) { $sum += $arr[$i]; } echo $sum;' "数组循环加" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $max = $arr[0]; foreach ($arr as $v) { if ($v > $max) $max = $v; } echo $max;' "foreach找最大" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $min = $arr[0]; foreach ($arr as $v) { if ($v < $min) $min = $v; } echo $min;' "foreach找最小" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $even = 0; foreach ($arr as $v) { if ($v % 2 == 0) $even++; } echo $even;' "偶数计数" "循环"
auto_test '$arr = array(1, 2, 3, 4, 5); $odd = 0; foreach ($arr as $v) { if ($v % 2 != 0) $odd++; } echo $odd;' "奇数计数" "循环"
auto_test '$n = 7; $isPrime = true; for ($i = 2; $i <= sqrt($n); $i++) { if ($n % $i == 0) { $isPrime = false; break; } } echo $isPrime ? "prime" : "not";' "素数判断" "循环"
auto_test '$arr = array(1, 1, 2, 2, 3, 3, 3); echo count(array_unique($arr));' "唯一元素数" "函数"
auto_test '$arr = array("a", "b", "a", "c", "b"); echo implode(",", array_unique($arr));' "去重保留" "函数"
auto_test '$arr = array(1, 2, 3); $arr2 = array(4, 5, 6); echo implode(",", array_merge($arr, $arr2));' "数组合并2" "函数"
auto_test '$arr1 = array("a" => 1); $arr2 = array("b" => 2); echo implode(",", array_merge($arr1, $arr2));' "关联合并" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $first = reset($arr); echo $first;' "首元素" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); $last = end($arr); prev($arr); echo current($arr);' "倒数第二" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); next($arr); next($arr); echo current($arr);' "指针前进" "函数"
auto_test '$str = "abcdefgh"; echo strlen($str);' "8字符长度" "函数"
auto_test '$str = "  hello  "; echo trim($str);' "trim2" "函数"
auto_test '$str = "---hello---"; echo trim($str, "-");' "去除横线" "函数"
auto_test '$str = "hello"; echo ltrim($str);' "ltrim2" "函数"
auto_test '$str = "hello   "; echo rtrim($str);' "rtrim2" "函数"
auto_test '$str = "hello"; echo str_pad($str, 10, "-", STR_PAD_BOTH);' "两端填充" "函数"
auto_test '$str = "abc"; echo str_repeat($str, 5);' "重复5次" "函数"
auto_test '$str = "abcdef"; echo substr_count($str, "c");' "字符计数" "函数"
auto_test '$str = "aaaabaaaa"; echo substr_count($str, "aa");' "子串计数" "函数"
auto_test '$x = 5; $y = 3; echo ($x > $y) ? $x : $y;' "三元取大" "表达式"
auto_test '$arr = array(1, 2, 3); echo $arr[0] + $arr[1] + $arr[2];' "数组元素加" "表达式"
auto_test '$x = 100; echo $x / 4 / 5;' "连续除法" "表达式"
auto_test '$x = 2; echo $x ** 4;' "幂运算" "表达式"
auto_test '$x = 3; $y = 4; echo sqrt($x*$x + $y*$y);' "勾股定理" "表达式"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($carry, $item) { return $carry + $item; }, 0);' "reduce求和2" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($carry, $item) { return $carry * $item; }, 1);' "reduce乘积" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_filter($arr, function($x) { return $x % 2 == 1; });' "filter奇数" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_map(function($x) { return $x * 2; }, $arr);' "map乘2" "函数"
auto_test '$arr = array_chunk(array(1, 2, 3, 4, 5), 2); echo count($arr);' "chunk计数" "函数"
auto_test '$str = "a,b,c,d,e"; $arr = explode(",", $str); echo count($arr);' "分割计数" "函数"
auto_test '$arr = array(5, 1, 3, 2, 4); asort($arr); echo implode(",", $arr);' "值排序2" "函数"
auto_test '$arr = array(5, 1, 3, 2, 4); arsort($arr); echo implode(",", $arr);' "值倒序2" "函数"
auto_test '$arr = array("b" => 2, "a" => 1, "c" => 3); ksort($arr); echo implode(",", array_keys($arr));' "键排序2" "函数"
auto_test '$arr = array("b" => 2, "a" => 1, "c" => 3); krsort($arr); echo implode(",", array_keys($arr));' "键倒序2" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); echo count(array_unique($arr));' "唯一计数" "函数"
auto_test '$str = "hello"; echo str_shuffle($str);' "随机打乱" "函数"
auto_test '$arr = array("a", "b", "c"); shuffle($arr); echo implode(",", $arr);' "数组打乱" "函数"
auto_test '$arr = array(3, 1, 4, 1, 5, 9, 2, 6); echo in_array(5, $arr) ? "yes" : "no";' "数组查找" "函数"
auto_test '$arr = array("x" => 1, "y" => 2); echo array_key_exists("x", $arr) ? "yes" : "no";' "键存在" "函数"
auto_test '$arr = array(1, 2, 3, 4, 5); echo array_search(3, $arr);' "数组搜索" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_slice($arr, 3, 4));' "切片求和" "函数"

echo ""
echo "========================================="
echo "测试完成！"
echo "========================================="
