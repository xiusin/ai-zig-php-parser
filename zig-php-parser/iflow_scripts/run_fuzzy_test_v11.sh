#!/bin/bash

# AOT 模糊测试脚本 v11 - 更多边界场景

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=538

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

# 538-600 更多边界场景

auto_test '$arr = array(); for ($i = 0; $i < 1000; $i++) { $arr[] = $i; } echo array_sum($arr);' "千次循环" "循环"
auto_test '$x = 0; for ($i = 1; $i <= 100; $i++) { $x += $i; } echo $x;' "1到100" "循环"
auto_test '$x = 1; for ($i = 1; $i <= 20; $i++) { $x *= 2; } echo $x;' "2的20次方" "循环"
auto_test '$arr = range(1, 50); $s = 0; foreach ($arr as $v) { if ($v % 3 == 0) $s += $v; } echo $s;' "3的倍数求和" "循环"
auto_test 'function f($n) { return $n <= 1 ? 1 : $n * f($n-1); } echo f(8);' "递归阶乘" "递归"
auto_test 'function fib($n) { if ($n <= 1) return $n; return fib($n-1) + fib($n-2); } echo fib(12);' "递归斐波那契" "递归"
auto_test '$a = 5; $b = 3; echo $a > $b ? ($a > 10 ? "big" : "small") : "less";' "嵌套三元2" "表达式"
auto_test '$arr = array(1,2,3,4,5); $s = 0; for ($i = 0; $i < count($arr); $i++) { $s += $arr[$i]; } echo $s;' "for遍历" "循环"
auto_test '$i = 0; $sum = 0; do { $sum += $i; $i++; } while ($i < 10); echo $sum;' "do-while" "循环"
auto_test '$arr = array(5,4,3,2,1); sort($arr); echo implode(",", $arr);' "sort排序" "函数"
auto_test '$arr = array(5,4,3,2,1); rsort($arr); echo implode(",", $arr);' "rsort倒序" "函数"
auto_test '$arr = array("c"=>3, "a"=>1, "b"=>2); ksort($arr); echo implode(",", array_keys($arr));' "ksort键排序" "函数"
auto_test '$arr = array(1,2,3,4,5); $slice = array_slice($arr, 1, 3); echo implode(",", $slice);' "array_slice" "函数"
auto_test '$arr1 = array("a","b","c"); $arr2 = array(1,2,3); $combined = array_combine($arr1, $arr2); echo implode(",", array_values($combined));' "array_combine" "函数"
auto_test '$arr = array(1,2,3,4,5); echo array_reduce($arr, function($c, $i) { return $c * $i; }, 1);' "array_reduce乘积" "函数"
auto_test '$str = "hello"; echo strtoupper($str) . strtolower($str);' "大小写转换2" "函数"
auto_test '$arr = array(1,2,3); echo array_search(2, $arr);' "array_search" "函数"
auto_test '$arr = array(1,2,3,2,1); echo max(array_count_values($arr));' "出现次数最多" "函数"
auto_test '$str = "abc"; echo str_pad($str, 10, "*", STR_PAD_BOTH);' "str_pad两端" "函数"
auto_test '$arr = array(1,2,3,4,5); echo array_sum(array_map(function($x) { return $x * $x; }, $arr));' "map后求和" "函数"
auto_test 'function add($a, $b=1, $c=2) { return $a + $b + $c; } echo add(5);' "默认参数" "函数"
auto_test '$arr = array(1,2,3); echo array_pop($arr); echo "," . array_pop($arr);' "array_pop" "函数"
auto_test '$arr = array(1,2,3); array_push($arr, 4, 5); echo implode(",", $arr);' "array_push多处" "函数"
auto_test '$arr = array(1,2,3,4,5); echo array_shift($arr); echo "," . array_shift($arr);' "array_shift" "函数"
auto_test '$arr = array(1,2,3); array_unshift($arr, 0); echo implode(",", $arr);' "array_unshift" "函数"
auto_test '$arr = array(1,2,3,4,5); $chunks = array_chunk($arr, 2); echo count($chunks);' "array_chunk" "函数"
auto_test '$arr = range(1, 10); echo array_sum(array_filter($arr, function($x) { return $x % 2 == 1; }));' "奇数求和" "函数"
auto_test 'echo abs(-123); echo abs(456);' "abs函数" "函数"
auto_test 'echo floor(3.9); echo ceil(3.1);' "floor/ceil" "函数"
auto_test 'echo round(3.5); echo round(3.4);' "round函数" "函数"
auto_test 'echo max(1,5,3); echo min(1,5,3);' "max/min标量" "函数"
auto_test '$arr = array(3,1,4,1,5,9,2,6); sort($arr); echo implode(",", $arr);' "数组排序" "函数"
auto_test '$arr = array("z"=>1, "a"=>2, "m"=>3); asort($arr); echo implode(",", array_values($arr));' "asort值排序" "函数"
auto_test '$arr = array(1,2,3,4,5); $fn = function($x) { return $x * 2; }; echo implode(",", array_map($fn, $arr));' "匿名函数map" "函数"
auto_test '$arr = range(1, 5); echo array_product($arr);' "数组乘积2" "函数"
auto_test '$str = "hello"; echo strlen($str);' "strlen函数" "函数"
auto_test '$str = "hello world"; echo str_word_count($str);' "str_word_count" "函数"
auto_test '$str = "HELLO"; echo strtolower($str);' "strtolower" "函数"
auto_test '$str = "hello"; echo strtoupper($str);' "strtoupper" "函数"
auto_test '$str = "hello"; echo ucfirst($str);' "ucfirst" "函数"
auto_test '$str = "hello world"; echo ucwords($str);' "ucwords" "函数"
auto_test '$arr = array(1,2,3); echo implode("-", $arr);' "implode连接" "函数"
auto_test '$str = "a,b,c"; $arr = explode(",", $str); echo count($arr);' "explode拆分" "函数"
auto_test '$str = "hello"; echo strpos($str, "l");' "strpos查找" "函数"
auto_test '$str = "hello"; echo str_replace("l", "x", $str);' "str_replace" "函数"
auto_test '$str = "  hello  "; echo strlen(trim($str));' "trim函数" "函数"
auto_test 'echo md5("hello");' "md5函数" "函数"
auto_test 'echo sha1("hello");' "sha1函数" "函数"
auto_test 'echo crc32("hello");' "crc32函数" "函数"
auto_test 'echo ord("A"); echo chr(65);' "ord/chr" "函数"
auto_test 'echo bin2hex("abc"); echo hex2bin("616263");' "hex转换" "函数"
auto_test '$arr = array(1, 2, 3); echo count($arr);' "count函数" "函数"
auto_test '$str = "hello"; echo substr($str, 1, 3);' "substr截取" "函数"
auto_test '$str = "hello"; echo substr($str, -3, 2);' "substr负索引" "函数"
auto_test '$arr = array(1,2,3,4,5); echo in_array(3, $arr) ? "found" : "not";' "in_array" "函数"
auto_test '$arr = array("a"=>1, "b"=>2); echo isset($arr["a"]) ? "yes" : "no";' "isset关联" "函数"
auto_test '$arr = array("a"=>1, "b"=>2); echo array_key_exists("a", $arr) ? "yes" : "no";' "array_key_exists" "函数"

echo ""
echo "========================================="
echo "测试完成！报告: $REPORT_FILE"
echo "========================================="
tail -30 "$REPORT_FILE"
