<?php
/**
 * AOT编译器综合功能测试脚本
 * 
 * 测试AOT编译器支持的所有PHP功能：
 * - 算术运算
 * - 比较运算
 * - 逻辑运算
 * - 字符串操作
 * - 数组操作
 * - 数学函数
 * - 类型检查
 * - 类型转换
 */

$passed = 0;
$failed = 0;

function test($name, $condition) {
    global $passed, $failed;
    if ($condition) {
        echo "✓ $name\n";
        $passed++;
    } else {
        echo "✗ $name\n";
        $failed++;
    }
}

echo "=== AOT编译器综合功能测试 ===\n\n";

// 算术运算测试
echo "--- 算术运算 ---\n";
test("加法: 10 + 20 = 30", 10 + 20 === 30);
test("减法: 30 - 20 = 10", 30 - 20 === 10);
test("乘法: 5 * 6 = 30", 5 * 6 === 30);
test("除法: 30 / 5 = 6", 30 / 5 === 6);
test("取模: 17 % 5 = 2", 17 % 5 === 2);
test("幂运算: 2 ** 10 = 1024", 2 ** 10 === 1024);
test("浮点加法: 3.14 + 2.86 = 6.0", abs((3.14 + 2.86) - 6.0) < 0.001);
test("负数运算: -5 + 10 = 5", -5 + 10 === 5);

echo "\n--- 比较运算 ---\n";
test("等于: 10 == 10", 10 == 10);
test("不等于: 10 != 20", 10 != 20);
test("小于: 5 < 10", 5 < 10);
test("大于: 15 > 10", 15 > 10);
test("小于等于: 10 <= 10", 10 <= 10);
test("大于等于: 10 >= 10", 10 >= 10);
test("全等: 10 === 10", 10 === 10);
test("类型不同不全等: 10 !== '10'", 10 !== '10');

echo "\n--- 逻辑运算 ---\n";
test("与: true && true", true && true);
test("与: true && false = false", (true && false) === false);
test("或: true || false", true || false);
test("或: false || false = false", (false || false) === false);
test("非: !true = false", !true === false);
test("非: !false = true", !false === true);

echo "\n--- 字符串操作 ---\n";
test("strlen: strlen('Hello') = 5", strlen('Hello') === 5);
test("连接: 'Hello' . ' World'", 'Hello' . ' World' === 'Hello World');
test("strtoupper: 'hello' -> 'HELLO'", strtoupper('hello') === 'HELLO');
test("strtolower: 'HELLO' -> 'hello'", strtolower('HELLO') === 'hello');
test("trim: '  hello  ' -> 'hello'", trim('  hello  ') === 'hello');
test("ltrim: '  hello' -> 'hello'", ltrim('  hello') === 'hello');
test("rtrim: 'hello  ' -> 'hello'", rtrim('hello  ') === 'hello');
test("strrev: 'hello' -> 'olleh'", strrev('hello') === 'olleh');
test("substr: substr('Hello World', 0, 5)", substr('Hello World', 0, 5) === 'Hello');
test("strpos: strpos('Hello World', 'World')", strpos('Hello World', 'World') === 6);
test("str_replace: 替换字符串", str_replace('World', 'PHP', 'Hello World') === 'Hello PHP');
test("str_repeat: 重复字符串", str_repeat('ab', 3) === 'ababab');
test("ucfirst: 首字母大写", ucfirst('hello') === 'Hello');
test("lcfirst: 首字母小写", lcfirst('HELLO') === 'hELLO');
test("ucwords: 每个单词首字母大写", ucwords('hello world') === 'Hello World');

// PHP 8.0+ 字符串函数
test("str_contains: 包含子串", str_contains('Hello World', 'World'));
test("str_starts_with: 以指定前缀开始", str_starts_with('Hello World', 'Hello'));
test("str_ends_with: 以指定后缀结束", str_ends_with('Hello World', 'World'));

echo "\n--- 数学函数 ---\n";
test("abs: abs(-42) = 42", abs(-42) === 42);
test("sqrt: sqrt(16) = 4", sqrt(16) === 4.0);
test("round: round(3.7) = 4", round(3.7) === 4.0);
test("floor: floor(3.7) = 3", floor(3.7) === 3.0);
test("ceil: ceil(3.2) = 4", ceil(3.2) === 4.0);
test("min: min(10, 20) = 10", min(10, 20) === 10);
test("max: max(10, 20) = 20", max(10, 20) === 20);
test("pow: pow(2, 8) = 256", pow(2, 8) === 256);
test("sin: sin(0) = 0", abs(sin(0)) < 0.0001);
test("cos: cos(0) = 1", abs(cos(0) - 1) < 0.0001);
test("tan: tan(0) = 0", abs(tan(0)) < 0.0001);
test("log: log(e) ≈ 1", abs(log(M_E) - 1) < 0.0001);
test("exp: exp(1) ≈ e", abs(exp(1) - M_E) < 0.0001);
test("pi: pi() ≈ 3.14159", abs(pi() - 3.14159) < 0.001);
test("deg2rad: deg2rad(180) = π", abs(deg2rad(180) - M_PI) < 0.0001);
test("rad2deg: rad2deg(π) = 180", abs(rad2deg(M_PI) - 180) < 0.0001);
test("fmod: fmod(5.5, 2.5) = 0.5", abs(fmod(5.5, 2.5) - 0.5) < 0.0001);

echo "\n--- 类型检查 ---\n";
test("is_null: is_null(null)", is_null(null));
test("is_null: !is_null(42)", !is_null(42));
test("is_bool: is_bool(true)", is_bool(true));
test("is_bool: !is_bool(1)", !is_bool(1));
test("is_int: is_int(42)", is_int(42));
test("is_int: !is_int(42.0)", !is_int(42.0));
test("is_float: is_float(3.14)", is_float(3.14));
test("is_float: !is_float(3)", !is_float(3));
test("is_string: is_string('hello')", is_string('hello'));
test("is_string: !is_string(42)", !is_string(42));
test("is_array: is_array([1,2,3])", is_array([1, 2, 3]));
test("is_array: !is_array('array')", !is_array('array'));
test("is_numeric: is_numeric(42)", is_numeric(42));
test("is_numeric: is_numeric('123')", is_numeric('123'));
test("is_numeric: !is_numeric('abc')", !is_numeric('abc'));

echo "\n--- 类型转换 ---\n";
test("intval: intval(3.7) = 3", intval(3.7) === 3);
test("intval: intval('42') = 42", intval('42') === 42);
test("floatval: floatval(42) = 42.0", floatval(42) === 42.0);
test("floatval: floatval('3.14') = 3.14", floatval('3.14') === 3.14);
test("boolval: boolval(0) = false", boolval(0) === false);
test("boolval: boolval(1) = true", boolval(1) === true);
test("strval: strval(42) = '42'", strval(42) === '42');

echo "\n--- 数组操作 ---\n";
$arr = [1, 2, 3, 4, 5];
test("count: count([1,2,3,4,5]) = 5", count($arr) === 5);
test("in_array: in_array(3, [1,2,3,4,5])", in_array(3, $arr));
test("in_array: !in_array(6, [1,2,3,4,5])", !in_array(6, $arr));

$arr2 = [1, 2, 3];
array_push($arr2, 4);
test("array_push: 添加元素", count($arr2) === 4 && $arr2[3] === 4);

$arr3 = [1, 2, 3];
$popped = array_pop($arr3);
test("array_pop: 弹出元素", $popped === 3 && count($arr3) === 2);

$keys = array_keys(['a' => 1, 'b' => 2, 'c' => 3]);
test("array_keys: 获取键", count($keys) === 3);

$values = array_values(['a' => 1, 'b' => 2, 'c' => 3]);
test("array_values: 获取值", $values === [1, 2, 3]);

$slice = array_slice([1, 2, 3, 4, 5], 1, 3);
test("array_slice: 切片数组", $slice === [2, 3, 4]);

$merged = array_merge([1, 2], [3, 4]);
test("array_merge: 合并数组", $merged === [1, 2, 3, 4]);

$exploded = explode(',', 'a,b,c');
test("explode: 分割字符串", $exploded === ['a', 'b', 'c']);

$imploded = implode(',', ['a', 'b', 'c']);
test("implode: 连接数组", $imploded === 'a,b,c');

echo "\n--- 控制流 ---\n";
$x = 10;
if ($x > 5) {
    $if_result = 'greater';
} else {
    $if_result = 'smaller';
}
test("if-else: 条件判断", $if_result === 'greater');

$sum = 0;
for ($i = 1; $i <= 5; $i++) {
    $sum += $i;
}
test("for循环: 求和1到5", $sum === 15);

$sum2 = 0;
$j = 1;
while ($j <= 5) {
    $sum2 += $j;
    $j++;
}
test("while循环: 求和1到5", $sum2 === 15);

$arr4 = [1, 2, 3];
$foreach_sum = 0;
foreach ($arr4 as $val) {
    $foreach_sum += $val;
}
test("foreach循环: 遍历数组求和", $foreach_sum === 6);

$switch_result = '';
$grade = 'B';
switch ($grade) {
    case 'A':
        $switch_result = 'Excellent';
        break;
    case 'B':
        $switch_result = 'Good';
        break;
    default:
        $switch_result = 'Unknown';
}
test("switch: 多分支选择", $switch_result === 'Good');

echo "\n--- 函数定义 ---\n";
function add($a, $b) {
    return $a + $b;
}
test("函数: add(3, 4) = 7", add(3, 4) === 7);

function factorial($n) {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}
test("递归: factorial(5) = 120", factorial(5) === 120);

function greet($name = 'World') {
    return "Hello, $name!";
}
test("默认参数: greet()", greet() === 'Hello, World!');
test("传参: greet('PHP')", greet('PHP') === 'Hello, PHP!');

echo "\n=== 测试结果 ===\n";
echo "通过: $passed\n";
echo "失败: $failed\n";
echo "总计: " . ($passed + $failed) . "\n";

if ($failed === 0) {
    echo "\n🎉 所有测试通过!\n";
} else {
    echo "\n⚠️ 有 $failed 个测试失败\n";
}
