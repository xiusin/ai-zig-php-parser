#!/bin/bash
# P0-1 阶段测试脚本：验证编译错误修复

set -e

echo "=== P0-1 阶段测试：统一 Value↔标量转换 ==="
echo ""

# 编译项目
echo "[1/3] 编译项目..."
zig build -Doptimize=ReleaseFast install 2>&1 | tail -20

echo ""
echo "[2/3] 测试 P0-1 目标用例（编译阶段）..."
echo ""

# P0-1 目标用例列表
test_cases=(
    "05_foreach_break"
    "34_bool"
    "41_nested_break_levels"
    "44_do_while_nested"
    "47_deep_nesting"
    "50_mixed_break_continue"
    "51_unset_iter_consistency"
)

success_count=0
fail_count=0

for test_case in "${test_cases[@]}"; do
    echo "测试: $test_case"
    if tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile "tests/aot/suite/${test_case}.php" 2>&1 | grep -q "error:"; then
        echo "  ❌ 编译失败"
        ((fail_count++))
    else
        echo "  ✅ 编译成功"
        ((success_count++))
    fi
done

echo ""
echo "[3/3] 测试结果汇总"
echo "  成功: $success_count / ${#test_cases[@]}"
echo "  失败: $fail_count / ${#test_cases[@]}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo "🎉 P0-1 阶段目标达成！所有用例编译成功。"
    exit 0
else
    echo "⚠️  仍有 $fail_count 个用例编译失败，需要继续修复。"
    exit 1
fi
