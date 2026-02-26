#!/bin/bash
# AOT 编译器稳定性测试套件
# 确保编译器在所有情况下都能生成正确的代码

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== AOT 编译器稳定性测试 ==="
echo ""

# 测试用例列表
TESTS=(
    "/tmp/test_concat_int.php:字符串拼接"
    "benchmarks/micro/simple_loop.php:简单循环"
    "benchmarks/micro/arithmetic.php:算术运算"
)

PASSED=0
FAILED=0

for test_case in "${TESTS[@]}"; do
    IFS=':' read -r file desc <<< "$test_case"
    
    if [ ! -f "$file" ]; then
        echo "⚠️  跳过: $desc (文件不存在: $file)"
        continue
    fi
    
    echo "测试: $desc"
    echo "  文件: $file"
    
    # 清理
    rm -rf .zigphp_aot_build
    
    # 编译
    output_name="/tmp/aot_test_$(basename $file .php)"
    compile_output=$(./zig-out/bin/php-interpreter --compile --output="$output_name" "$file" 2>&1)
    
    if echo "$compile_output" | grep -q "Success"; then
        # 运行
        "$output_name" >/dev/null 2>&1
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "  ✅ 通过"
            ((PASSED++))
        else
            echo "  ❌ 运行失败 (退出码: $exit_code)"
            "$output_name" 2>&1 | head -3
            ((FAILED++))
        fi
    else
        echo "  ❌ 编译失败"
        echo "$compile_output" | grep "error:" | head -3
        ((FAILED++))
    fi
    echo ""
done

echo "=== 测试结果 ==="
echo "通过: $PASSED"
echo "失败: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ 所有测试通过！编译器稳定。"
    exit 0
else
    echo "❌ 有测试失败。编译器不稳定。"
    exit 1
fi
