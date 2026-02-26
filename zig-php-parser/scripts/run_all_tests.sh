#!/bin/bash
# 运行所有稳定性测试

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         AOT 编译器完整稳定性验证套件                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    local script="$2"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "测试: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    ((TOTAL_TESTS++))
    
    if "$script"; then
        echo ""
        echo "✅ $name 通过"
        ((PASSED_TESTS++))
    else
        echo ""
        echo "❌ $name 失败"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# 运行所有测试
run_test "基础稳定性测试" "./scripts/test_aot_stability.sh"
run_test "压力测试 (100次编译)" "./scripts/test_stability_stress.sh"
run_test "代码质量验证" "./scripts/test_code_quality.sh"
run_test "多文件测试 (40次编译)" "./scripts/test_multi_file.sh"

# 总结
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      最终结果                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "总测试数: $TOTAL_TESTS"
echo "通过: $PASSED_TESTS"
echo "失败: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ✅ 所有测试通过！编译器完全稳定！                          ║"
    echo "║                                                            ║"
    echo "║  - 100 次重复编译生成完全相同的代码                         ║"
    echo "║  - 40 次多文件编译全部成功                                  ║"
    echo "║  - 所有代码质量检查通过                                     ║"
    echo "║  - 无缓冲区覆盖问题                                         ║"
    echo "║  - 无随机变量名错误                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    exit 0
else
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ❌ 有测试失败！编译器不稳定！                              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    exit 1
fi
