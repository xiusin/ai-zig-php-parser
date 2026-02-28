#!/bin/bash

# AOT 模糊测试脚本生成器 v5 - 无限模糊测试
# 持续生成复杂 PHP 脚本进行测试

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/iflow_scripts"
INTERPRETER="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
TIMEOUT="/opt/homebrew/bin/gtimeout"
COUNTER=156

REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"

test_script() {
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
    echo "$1" >> "$script_path"
    echo "?>" >> "$script_path"
    
    $TIMEOUT 30s $PHP "$script_path" > "$php_out" 2>&1
    PHP_EXIT=$?
    PHP_RESULT=$(cat "$php_out")
    
    $TIMEOUT 30s "$INTERPRETER" "$script_path" > "$interp_out" 2>&1
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
    
    if [ $AOT_COMPILE_EXIT -ne 0 ]; then
        ERROR_INFO=$(cat "$SCRIPT_DIR/test_${COUNTER}_aot_compile.log" | tail -5 | head -3 | tr '\n' ' ')
    elif [ $AOT_EXIT -ne 0 ]; then
        ERROR_INFO="运行时错误 (exit: $AOT_EXIT)"
    elif [ "$PHP_RESULT" != "$AOT_RESULT" ]; then
        ERROR_INFO="期望: $PHP_RESULT, 实际: $AOT_RESULT"
    else
        ERROR_INFO="-"
    fi
    
    echo "| $COUNTER | test_$COUNTER.php | $category | ${PHP_RESULT:0:40} | ${INTERP_RESULT:0:40} | ${AOT_RESULT:0:40} | $STATUS | ${ERROR_INFO:0:60} |" >> "$REPORT_FILE"
    
    echo "[$COUNTER] $category - $STATUS: $desc"
    
    COUNTER=$((COUNTER + 1))
}

# ===== 更多边界和复杂测试 =====

# 156. 深度递归
test_script '
function deepRecursive($n) {
    if ($n <= 0) return 0;
    return $n + deepRecursive($n - 1);
}
echo deepRecursive(100);
' "深度递归" "递归"

# 157. 多重三元
test_script '
$x = 5;
$y = 10;
$z = 15;
echo $x > $y ? "x>y" : ($y > $z ? "y>z" : ($x > $z ? "x>z" : "all ordered"));
' "多重三元" "表达式"

# 158. 复杂数组操作
test_script '
$arr = [1, 2, 3, 4, 5];
$arr[] = 6;
$arr[] = 7;
echo count($arr);
echo end($arr);
' "数组push_end" "数组"

# 159. 字符串函数链式
test_script '
$str = "  Hello World  ";
$str = trim($str);
$str = strtolower($str);
$str = str_replace("world", "php", $str);
echo $str;
' "字符串函数链" "字符串"

# 160. 复杂条件
test_script '
$x = 5;
$y = 10;
$z = 15;
if (($x < $y && $y < $z) || ($x > $z)) {
    echo "condition1";
} elseif (($x == 5) || ($y == 10 && $z == 15)) {
    echo "condition2";
} else {
    echo "other";
}
' "复杂条件分支" "控制流"

# 161. 数组键操作
test_script '
$arr = [];
$arr["a"] = 1;
$arr["b"] = 2;
$arr["c"] = 3;
echo isset($arr["a"]) ? $arr["a"] : 0;
echo isset($arr["d"]) ? $arr["d"] : 0;
' "数组键操作" "数组"

# 162. 函数返回数组
test_script '
function getArray() {
    return [1, 2, 3, 4, 5];
}
$arr = getArray();
echo array_sum($arr);
' "函数返回数组" "函数"

# 163. 嵌套数组字面量
test_script '
$arr = [
    "users" => [
        ["name" => "Alice", "age" => 25],
        ["name" => "Bob", "age" => 30]
    ]
];
echo $arr["users"][0]["name"];
' "嵌套数组字面量" "数组"

# 164. 负数索引
test_script '
$arr = [1, 2, 3, 4, 5];
echo end($arr);
echo prev($arr);
' "数组prev" "数组"

# 165. 数组指针操作
test_script '
$arr = [1, 2, 3];
echo current($arr);
next($arr);
echo current($arr);
next($arr);
echo current($arr);
' "数组指针" "数组"

# 166. 复杂数学表达式
test_script '
$a = 10;
$b = 20;
$c = 30;
$result = ($a + $b) * $c - ($a * $b) + ($c / $a);
echo round($result, 2);
' "复杂数学" "表达式"

# 167. 字符串连接赋值
test_script '
$str = "Hello";
$str .= " ";
$str .= "World";
$str .= "!";
echo $str;
' "字符串连接赋值" "字符串"

# 168. 比较运算符链
test_script '
echo 1 < 2 < 3 ? "yes" : "no";
echo 3 > 2 > 1 ? "yes" : "no";
' "比较链" "表达式"

# 169. 数组遍历修改
test_script '
$arr = [1, 2, 3, 4, 5];
foreach ($arr as &$v) {
    $v *= 2;
}
unset($v);
echo implode(",", $arr);
' "foreach引用修改" "数组"

# 170. 多层break
test_script '
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j == 1) break 2;
        echo "$i-$j ";
    }
}
' "多层break" "控制流"

# 171. 复杂循环退出条件
test_script '
$i = 0;
$j = 0;
while ($i < 10) {
    $i++;
    $j += $i;
    if ($j > 20) break;
}
echo $i;
echo $j;
' "while_break" "循环"

# 172. 数组键存在检查
test_script '
$arr = ["a" => 1, "b" => 2];
echo array_key_exists("a", $arr) ? "yes" : "no";
echo array_key_exists("c", $arr) ? "yes" : "no";
' "array_key_exists" "函数"

# 173. 字符串str_repeat
test_script '
echo str_repeat("ab", 5);
' "str_repeat" "函数"

# 174. 字符串str_pad
test_script '
echo str_pad("abc", 10, "*", STR_PAD_LEFT);
echo str_pad("abc", 10, "*", STR_PAD_RIGHT);
echo str_pad("abc", 10, "*", STR_PAD_BOTH);
' "str_pad" "函数"

# 175. 字符串str_split
test_script '
$arr = str_split("hello");
echo implode(",", $arr);
' "str_split" "函数"

# 176. 字符串ucfirst lcfirst
test_script '
echo ucfirst("hello");
echo lcfirst("HELLO");
' "ucfirst_lcfirst" "函数"

# 177. 字符串md5 sha1
test_script '
echo md5("hello");
echo sha1("hello");
' "md5_sha1" "函数"

# 178. 字符串ord chr
test_script '
echo ord("A");
echo chr(65);
' "ord_chr" "函数"

# 179. 字符串number_format
test_script '
echo number_format(1234567.89, 2, ".", ",");
' "number_format" "函数"

# 180. 字符串wordwrap
test_script '
echo wordwrap("This is a long string that needs to be wrapped", 10, "<br>", true);
' "wordwrap" "函数"

# 181. 数组array_slice
test_script '
$arr = [1, 2, 3, 4, 5];
$slice = array_slice($arr, 1, 3);
echo implode(",", $slice);
' "array_slice" "函数"

# 182. 数组array_splice
test_script '
$arr = [1, 2, 3, 4, 5];
array_splice($arr, 1, 2, [10, 20]);
echo implode(",", $arr);
' "array_splice" "函数"

# 183. 数组array_fill
test_script '
$arr = array_fill(0, 5, "value");
echo implode(",", $arr);
' "array_fill" "函数"

# 184. 数组array_keys + array_values
test_script '
$arr = ["a" => 1, "b" => 2, "c" => 3];
echo implode(",", array_keys($arr));
echo implode(",", array_values($arr));
' "array_keys_values" "函数"

# 185. 数组array_count_values
test_script '
$arr = [1, 2, 2, 3, 3, 3];
$counts = array_count_values($arr);
echo $counts[2];
echo $counts[3];
' "array_count_values" "函数"

# 186. 数组array_flip
test_script '
$arr = ["a" => 1, "b" => 2];
$flipped = array_flip($arr);
echo $flipped[1];
echo $flipped[2];
' "array_flip" "函数"

# 187. 数组array_diff
test_script '
$a = [1, 2, 3, 4];
$b = [2, 4];
$diff = array_diff($a, $b);
echo implode(",", $diff);
' "array_diff" "函数"

# 188. 数组array_intersect
test_script '
$a = [1, 2, 3, 4];
$b = [2, 4, 6];
$intersect = array_intersect($a, $b);
echo implode(",", $intersect);
' "array_intersect" "函数"

# 189. 数组array_unique
test_script '
$arr = [1, 2, 2, 3, 3, 3, 4, 4, 4, 4];
$unique = array_unique($arr);
echo implode(",", $unique);
' "array_unique" "函数"

# 190. 数组array_rand
test_script '
$arr = ["a", "b", "c", "d", "e"];
$key = array_rand($arr);
echo $arr[$key];
' "array_rand" "函数"

# 191. 数组shuffle
test_script '
$arr = [1, 2, 3, 4, 5];
shuffle($arr);
echo implode(",", $arr);
' "shuffle" "函数"

# 192. 数组arsort asort
test_script '
$arr = ["b" => 2, "a" => 1, "d" => 4, "c" => 3];
asort($arr);
echo implode(",", $arr);
arsort($arr);
echo implode(",", $arr);
' "asort_arsort" "函数"

# 193. 数组ksort krsort
test_script '
$arr = ["b" => 2, "a" => 1, "d" => 4, "c" => 3];
ksort($arr);
echo implode(",", $arr);
krsort($arr);
echo implode(",", $arr);
' "ksort_krsort" "函数"

# 194. 数组natsort natcasesort
test_script '
$arr = ["img2.png", "img10.png", "img1.png"];
sort($arr);
echo implode(",", $arr);
natsort($arr);
echo implode(",", $arr);
' "natsort" "函数"

# 195. 数组compact
test_script '
$a = 1;
$b = 2;
$c = 3;
$arr = compact("a", "b", "c");
echo implode(",", $arr);
' "compact" "函数"

# 196. 数组extract
test_script '
$arr = ["a" => 1, "b" => 2, "c" => 3];
extract($arr);
echo $a + $b + $c;
' "extract" "函数"

# 197. 数组array_pad
test_script '
$arr = [1, 2, 3];
$padded = array_pad($arr, 6, 0);
echo implode(",", $padded);
' "array_pad" "函数"

# 198. 数组array_fill_keys
test_script '
$keys = ["a", "b", "c"];
$arr = array_fill_keys($keys, "value");
echo implode(",", $arr);
' "array_fill_keys" "函数"

# 199. 数组array_combine
test_script '
$keys = ["a", "b", "c"];
$values = [1, 2, 3];
$combined = array_combine($keys, $values);
echo $combined["a"] + $combined["b"] + $combined["c"];
' "array_combine" "函数"

# 200. 数组array_chunk
test_script '
$arr = [1, 2, 3, 4, 5, 6];
$chunks = array_chunk($arr, 2);
echo count($chunks);
echo count($chunks[0]);
' "array_chunk" "函数"

# 201. 复杂函数链式调用
test_script '
function add($a, $b) { return $a + $b; }
function mul($a, $b) { return $a * $b; }
function sub($a, $b) { return $a - $b; }
$result = sub(mul(add(1, 2), 3), 4);
echo $result;
' "函数链式" "函数"

# 202. 变量函数
test_script '
function add($a, $b) { return $a + $b; }
$func = "add";
echo $func(3, 4);
' "变量函数" "函数"

# 203. 回调函数
test_script '
$arr = [1, 2, 3, 4, 5];
$sum = 0;
array_map(function($x) use (&$sum) {
    $sum += $x;
}, $arr);
echo $sum;
' "回调函数" "函数"

# 204. 递归数组操作
test_script '
function sumArray($arr) {
    $sum = 0;
    foreach ($arr as $v) {
        if (is_array($v)) {
            $sum += sumArray($v);
        } else {
            $sum += $v;
        }
    }
    return $sum;
}
$arr = [1, [2, 3], [4, [5, 6]]];
echo sumArray($arr);
' "递归数组" "递归"

# 205. 动态属性访问
test_script '
$obj = new stdClass();
$obj->name = "John";
$obj->age = 30;
$prop = "name";
echo $obj->$prop;
' "动态属性" "OOP"

echo ""
echo "========================================="
echo "测试完成！报告保存在: $REPORT_FILE"
echo "========================================="
tail -70 "$REPORT_FILE"
