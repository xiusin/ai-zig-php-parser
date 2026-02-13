#!/bin/bash
# 性能基准测试

cd "$(dirname "$0")"

echo "=== PHP AOT 编译器性能基准测试 ==="
echo ""

# 测试用例
tests=(
    "01_if_else:简单条件"
    "02_while:while循环"
    "03_for:for循环"
    "08_nested_loop:嵌套循环"
    "15_string_funcs:字符串函数"
    "16_array_funcs:数组函数"
    "27_fibonacci:斐波那契"
    "41_nested_break_levels:多层break"
)

echo "编译所有测试..."
for test_info in "${tests[@]}"; do
    test_name="${test_info%%:*}"
    rm -f "./$test_name"
    ./zig-out/bin/php-interpreter --compile "tests/aot/suite/${test_name}.php" >/dev/null 2>&1
done

echo ""
echo "运行性能测试..."
echo "格式: 测试名称 | PHP时间 | AOT时间 | 加速比"
echo "----------------------------------------"

for test_info in "${tests[@]}"; do
    test_name="${test_info%%:*}"
    test_desc="${test_info##*:}"
    
    # PHP 基准
    php_time=$(php -r "
        \$start = microtime(true);
        for (\$i = 0; \$i < 1000; \$i++) {
            include 'tests/aot/suite/${test_name}.php';
        }
        echo microtime(true) - \$start;
    " 2>/dev/null)
    
    # AOT 基准
    aot_time=$(php -r "
        \$start = microtime(true);
        for (\$i = 0; \$i < 1000; \$i++) {
            exec('./${test_name}');
        }
        echo microtime(true) - \$start;
    " 2>/dev/null)
    
    # 计算加速比
    speedup=$(php -r "echo round($php_time / $aot_time, 2);")
    
    printf "%-30s | %8.3fs | %8.3fs | %6.2fx\n" "$test_desc" "$php_time" "$aot_time" "$speedup"
done

echo ""
echo "测试完成！"
