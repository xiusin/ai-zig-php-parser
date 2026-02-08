<?php
/**
 * AOT 编译综合测试脚本
 * 
 * 测试覆盖：
 * - 多维数组操作
 * - 字符串处理和插值
 * - 数学运算（整数和浮点数）
 * - 控制流结构
 * - 函数定义和递归
 * - 内置函数（字符串、数组、时间、随机数）
 * - 复合赋值运算符
 * - 三元运算符
 * - 类型转换
 */

// 全局测试统计
$total_tests = 0;
$passed_tests = 0;
$failed_tests = 0;

/**
 * 测试断言函数
 */
function assert_test($condition, $test_name) {
    global $total_tests, $passed_tests, $failed_tests;
    $total_tests++;
    
    if ($condition) {
        $passed_tests++;
        echo "[PASS] " . $test_name . "\n";
        return true;
    } else {
        $failed_tests++;
        echo "[FAIL] " . $test_name . "\n";
        return false;
    }
}

/**
 * 测试1: 多维数组操作
 */
function test_multidimensional_arrays() {
    echo "\n=== 测试多维数组操作 ===\n";
    
    // 创建多维数组
    $matrix = array(
        array(1, 2, 3),
        array(4, 5, 6),
        array(7, 8, 9)
    );
    
    // 访问元素
    assert_test($matrix[0][0] == 1, "多维数组访问 [0][0]");
    assert_test($matrix[1][2] == 6, "多维数组访问 [1][2]");
    assert_test($matrix[2][1] == 8, "多维数组访问 [2][1]");
    
    // 修改元素
    $matrix[1][1] = 99;
    assert_test($matrix[1][1] == 99, "多维数组修改");
    
    // 嵌套数组
    $nested = array(
        "users" => array(
            array("name" => "Alice", "age" => 30),
            array("name" => "Bob", "age" => 25)
        ),
        "count" => 2
    );
    
    assert_test($nested["users"][0]["name"] == "Alice", "关联数组嵌套访问");
    assert_test($nested["users"][1]["age"] == 25, "关联数组嵌套访问2");
    
    // 三维数组
    $cube = array(
        array(
            array(1, 2),
            array(3, 4)
        ),
        array(
            array(5, 6),
            array(7, 8)
        )
    );
    
    assert_test($cube[1][0][1] == 6, "三维数组访问");
}

/**
 * 测试2: 字符串操作
 */
function test_string_operations() {
    echo "\n=== 测试字符串操作 ===\n";
    
    // 字符串拼接
    $str1 = "Hello";
    $str2 = "World";
    $result = $str1 . " " . $str2;
    assert_test($result == "Hello World", "字符串拼接");
    
    // 字符串插值
    $name = "PHP";
    $version = 8;
    $message = "Welcome to " . $name . " " . $version;
    assert_test($message == "Welcome to PHP 8", "字符串插值");
    
    // strlen
    assert_test(strlen("Hello") == 5, "strlen 函数");
    assert_test(strlen("") == 0, "strlen 空字符串");
    
    // substr
    $text = "Hello World";
    assert_test(substr($text, 0, 5) == "Hello", "substr 提取");
    assert_test(substr($text, 6) == "World", "substr 从位置开始");
    
    // strpos
    assert_test(strpos("Hello World", "World") == 6, "strpos 查找位置");
    assert_test(strpos("Hello World", "PHP") === false, "strpos 未找到");
    
    // str_replace
    $original = "Hello World";
    $replaced = str_replace("World", "PHP", $original);
    assert_test($replaced == "Hello PHP", "str_replace 替换");
    
    // strtoupper / strtolower
    assert_test(strtoupper("hello") == "HELLO", "strtoupper 转大写");
    assert_test(strtolower("WORLD") == "world", "strtolower 转小写");
    
    // trim
    assert_test(trim("  hello  ") == "hello", "trim 去空格");
}

/**
 * 测试3: 数学运算
 */
function test_math_operations() {
    echo "\n=== 测试数学运算 ===\n";
    
    // 基本运算
    assert_test(10 + 5 == 15, "加法运算");
    assert_test(10 - 5 == 5, "减法运算");
    assert_test(10 * 5 == 50, "乘法运算");
    assert_test(10 / 5 == 2, "除法运算");
    assert_test(10 % 3 == 1, "取模运算");
    
    // 浮点数运算
    $float1 = 3.14;
    $float2 = 2.0;
    assert_test($float1 + $float2 > 5.1 && $float1 + $float2 < 5.2, "浮点数加法");
    assert_test($float1 * $float2 > 6.2 && $float1 * $float2 < 6.3, "浮点数乘法");
    
    // 复合赋值运算符
    $x = 10;
    $x += 5;
    assert_test($x == 15, "复合赋值 +=");
    
    $x -= 3;
    assert_test($x == 12, "复合赋值 -=");
    
    $x *= 2;
    assert_test($x == 24, "复合赋值 *=");
    
    $x /= 4;
    assert_test($x == 6, "复合赋值 /=");
    
    // 自增自减
    $y = 5;
    $y++;
    assert_test($y == 6, "后置自增");
    
    $y--;
    assert_test($y == 5, "后置自减");
}

/**
 * 测试4: 控制流
 */
function test_control_flow() {
    echo "\n=== 测试控制流 ===\n";
    
    // if-else
    $value = 10;
    $result = "";
    if ($value > 5) {
        $result = "greater";
    } else {
        $result = "less";
    }
    assert_test($result == "greater", "if-else 条件");
    
    // 三元运算符
    $age = 20;
    $status = ($age >= 18) ? "adult" : "minor";
    assert_test($status == "adult", "三元运算符");
    
    // for 循环
    $sum = 0;
    for ($i = 1; $i <= 10; $i++) {
        $sum += $i;
    }
    assert_test($sum == 55, "for 循环求和");
    
    // while 循环
    $count = 0;
    $n = 1;
    while ($n <= 5) {
        $count += $n;
        $n++;
    }
    assert_test($count == 15, "while 循环");
    
    // foreach 循环
    $arr = array(1, 2, 3, 4, 5);
    $total = 0;
    foreach ($arr as $val) {
        $total += $val;
    }
    assert_test($total == 15, "foreach 数组遍历");
    
    // foreach 关联数组
    $assoc = array("a" => 1, "b" => 2, "c" => 3);
    $sum_values = 0;
    foreach ($assoc as $key => $value) {
        $sum_values += $value;
    }
    assert_test($sum_values == 6, "foreach 关联数组");
}

/**
 * 测试5: 函数定义和调用
 */
function test_functions() {
    echo "\n=== 测试函数 ===\n";
    
    // 简单函数
    function add($a, $b) {
        return $a + $b;
    }
    assert_test(add(3, 4) == 7, "简单函数调用");
    
    // 递归函数 - 阶乘
    function factorial($n) {
        if ($n <= 1) {
            return 1;
        }
        return $n * factorial($n - 1);
    }
    assert_test(factorial(5) == 120, "递归函数 - 阶乘");
    assert_test(factorial(0) == 1, "递归函数 - 边界条件");
    
    // 递归函数 - 斐波那契
    function fibonacci($n) {
        if ($n <= 1) {
            return $n;
        }
        return fibonacci($n - 1) + fibonacci($n - 2);
    }
    assert_test(fibonacci(6) == 8, "递归函数 - 斐波那契");
    
    // 多参数函数
    function calculate($a, $b, $c) {
        return ($a + $b) * $c;
    }
    assert_test(calculate(2, 3, 4) == 20, "多参数函数");
}

/**
 * 测试6: 数组函数
 */
function test_array_functions() {
    echo "\n=== 测试数组函数 ===\n";
    
    // count
    $arr = array(1, 2, 3, 4, 5);
    assert_test(count($arr) == 5, "count 函数");
    
    // array_push
    array_push($arr, 6);
    assert_test(count($arr) == 6, "array_push 添加元素");
    assert_test($arr[5] == 6, "array_push 验证值");
    
    // array_pop
    $last = array_pop($arr);
    assert_test($last == 6, "array_pop 返回值");
    assert_test(count($arr) == 5, "array_pop 后长度");
    
    // in_array
    assert_test(in_array(3, $arr) == true, "in_array 存在");
    assert_test(in_array(99, $arr) == false, "in_array 不存在");
    
    // array_merge
    $arr1 = array(1, 2, 3);
    $arr2 = array(4, 5, 6);
    $merged = array_merge($arr1, $arr2);
    assert_test(count($merged) == 6, "array_merge 合并");
    assert_test($merged[3] == 4, "array_merge 验证值");
}

/**
 * 测试7: 类型转换
 */
function test_type_conversion() {
    echo "\n=== 测试类型转换 ===\n";
    
    // 字符串转整数
    $str_num = "123";
    $int_num = (int)$str_num;
    assert_test($int_num == 123, "字符串转整数");
    
    // 整数转字符串
    $num = 456;
    $str = (string)$num;
    assert_test($str == "456", "整数转字符串");
    
    // 浮点数转整数
    $float = 3.14;
    $int = (int)$float;
    assert_test($int == 3, "浮点数转整数");
    
    // 布尔转换
    $true_val = (bool)1;
    $false_val = (bool)0;
    assert_test($true_val == true, "整数转布尔 true");
    assert_test($false_val == false, "整数转布尔 false");
}

/**
 * 测试8: 时间和随机数
 */
function test_time_and_random() {
    echo "\n=== 测试时间和随机数 ===\n";
    
    // time() 函数
    $timestamp = time();
    assert_test($timestamp > 0, "time() 返回时间戳");
    
    // 随机数范围测试
    $random = rand(1, 10);
    assert_test($random >= 1 && $random <= 10, "rand() 范围检查");
    
    // 多次随机数测试
    $in_range = true;
    for ($i = 0; $i < 10; $i++) {
        $r = rand(0, 100);
        if ($r < 0 || $r > 100) {
            $in_range = false;
            break;
        }
    }
    assert_test($in_range, "rand() 多次范围检查");
}

/**
 * 性能测试：循环性能
 */
function test_performance() {
    echo "\n=== 性能测试 ===\n";
    
    $start = microtime(true);
    
    // 大量循环计算
    $sum = 0;
    for ($i = 0; $i < 10000; $i++) {
        $sum += $i;
    }
    
    $end = microtime(true);
    $duration = $end - $start;
    
    echo "循环10000次耗时: " . $duration . " 秒\n";
    assert_test($sum == 49995000, "性能测试 - 计算正确性");
    
    // 字符串拼接性能
    $start2 = microtime(true);
    $str = "";
    for ($i = 0; $i < 1000; $i++) {
        $str .= "x";
    }
    $end2 = microtime(true);
    
    echo "字符串拼接1000次耗时: " . ($end2 - $start2) . " 秒\n";
    assert_test(strlen($str) == 1000, "性能测试 - 字符串拼接");
}

/**
 * 主测试函数
 */
function run_all_tests() {
    echo "========================================\n";
    echo "  AOT 编译综合测试开始\n";
    echo "========================================\n";
    
    test_multidimensional_arrays();
    test_string_operations();
    test_math_operations();
    test_control_flow();
    test_functions();
    test_array_functions();
    test_type_conversion();
    test_time_and_random();
    test_performance();
    
    // 输出测试统计
    global $total_tests, $passed_tests, $failed_tests;
    echo "\n========================================\n";
    echo "  测试统计\n";
    echo "========================================\n";
    echo "总测试数: " . $total_tests . "\n";
    echo "通过: " . $passed_tests . "\n";
    echo "失败: " . $failed_tests . "\n";
    
    $pass_rate = ($total_tests > 0) ? ($passed_tests * 100 / $total_tests) : 0;
    echo "通过率: " . $pass_rate . "%\n";
    
    if ($failed_tests == 0) {
        echo "\n✓ 所有测试通过！\n";
    } else {
        echo "\n✗ 存在失败的测试\n";
    }
}

// 执行所有测试
run_all_tests();

?>
