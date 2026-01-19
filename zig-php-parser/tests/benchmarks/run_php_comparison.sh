#!/bin/bash

# 字符串性能测试 - PHP 对比脚本
# 运行所有生成的 PHP 测试脚本并收集性能数据

echo "================================================================================"
echo "           字符串操作性能测试 - PHP 原生性能测试"
echo "================================================================================"
echo ""
echo "测试目录: tests/benchmarks/string"
echo "迭代次数: 10,000"
echo ""

# 切换到脚本目录
cd "$(dirname "$0")/string" || exit 1

# 统计变量
total_tests=0
total_time=0

# 运行所有 PHP 脚本
for php_file in *.php; do
    if [ -f "$php_file" ]; then
        test_name="${php_file%.php}"
        
        # 运行 PHP 脚本并提取时间
        output=$(php "$php_file" 2>&1)
        time_ms=$(echo "$output" | grep -oP 'Time: \K[0-9.]+')
        
        if [ -n "$time_ms" ]; then
            printf "  %-30s %10.2f ms\n" "$test_name" "$time_ms"
            total_tests=$((total_tests + 1))
            total_time=$(echo "$total_time + $time_ms" | bc)
        else
            printf "  %-30s %10s\n" "$test_name" "ERROR"
        fi
    fi
done

echo ""
echo "================================================================================"
echo "                           总结"
echo "================================================================================"
echo ""
echo "总测试数: $total_tests"
printf "总耗时: %.2f ms\n" "$total_time"

if [ "$total_tests" -gt 0 ]; then
    avg_time=$(echo "scale=2; $total_time / $total_tests" | bc)
    printf "平均耗时: %.2f ms/测试\n" "$avg_time"
fi

echo ""
echo "提示: 将此结果与 Zig 实现的性能进行对比"
echo "      运行 'zig build bench-string' 查看 Zig 性能"
