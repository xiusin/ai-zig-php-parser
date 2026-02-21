#!/bin/bash
# P0 阶段完整验证脚本
# 验证 P0-1, P0-2, P0-3 的所有修复

set -e

cd "$(dirname "$0")/../.."

echo "=========================================="
echo "P0 阶段验证 - 编译错误修复"
echo "=========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 统计变量
total_tests=0
compile_success=0
compile_fail=0
run_success=0
run_fail=0
output_match=0
output_mismatch=0

# P0-1 用例（编译错误修复）
P0_1_CASES=(
    "05_foreach_break"
    "34_bool"
    "41_nested_break_levels"
    "44_do_while_nested"
    "47_deep_nesting"
    "50_mixed_break_continue"
    "51_unset_iter_consistency"
)

# P0-2 用例（panic 修复）
P0_2_CASES=(
    "42_nested_continue_levels"
    "43_mixed_control_flow"
    "45_match_in_loop"
    "46_complex_nesting"
    "49_recursive_with_loops"
)

# P0-3 用例（unset 语义）
P0_3_CASES=(
    "52_foreach_by_ref"
)

echo "[1/4] 编译项目..."
echo "----------------------------------------"
if zig build -Doptimize=ReleaseFast install 2>&1 | tail -10; then
    echo -e "${GREEN}✅ 项目编译成功${NC}"
else
    echo -e "${RED}❌ 项目编译失败${NC}"
    exit 1
fi

echo ""
echo "[2/4] P0-1 验证：类型转换修复（7 个用例）"
echo "----------------------------------------"
for case in "${P0_1_CASES[@]}"; do
    total_tests=$((total_tests + 1))
    echo -n "测试 $case ... "
    
    # 编译测试
    if tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile "tests/aot/suite/${case}.php" > /tmp/${case}_compile.log 2>&1; then
        compile_success=$((compile_success + 1))
        echo -e "${GREEN}编译✅${NC}"
        
        # 运行测试
        if [ -f "./${case}" ]; then
            if ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 "./${case}" > /tmp/${case}_run.log 2>&1; then
                run_success=$((run_success + 1))
                echo "  运行: ✅"
                
                # 检查输出（如果有期望输出）
                if php "tests/aot/suite/${case}.php" > /tmp/${case}_php.log 2>&1; then
                    if diff -q /tmp/${case}_run.log /tmp/${case}_php.log > /dev/null 2>&1; then
                        output_match=$((output_match + 1))
                        echo "  输出: ✅ 匹配"
                    else
                        output_mismatch=$((output_mismatch + 1))
                        echo -e "  输出: ${YELLOW}⚠️  不匹配${NC}"
                    fi
                fi
            else
                run_fail=$((run_fail + 1))
                exit_code=$?
                echo -e "  运行: ${RED}❌ (exit $exit_code)${NC}"
            fi
        fi
    else
        compile_fail=$((compile_fail + 1))
        echo -e "${RED}编译❌${NC}"
        echo "  错误信息："
        grep "error:" /tmp/${case}_compile.log | head -3 | sed 's/^/    /'
    fi
done

echo ""
echo "[3/4] P0-2 验证：panic 修复（5 个用例）"
echo "----------------------------------------"
for case in "${P0_2_CASES[@]}"; do
    total_tests=$((total_tests + 1))
    echo -n "测试 $case ... "
    
    # 编译测试
    if tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile "tests/aot/suite/${case}.php" > /tmp/${case}_compile.log 2>&1; then
        compile_success=$((compile_success + 1))
        echo -e "${GREEN}编译✅${NC}"
        
        # 运行测试（检查是否 panic）
        if [ -f "./${case}" ]; then
            ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 "./${case}" > /tmp/${case}_run.log 2>&1
            exit_code=$?
            
            if [ $exit_code -eq 134 ]; then
                run_fail=$((run_fail + 1))
                echo -e "  运行: ${RED}❌ panic (exit 134)${NC}"
                grep "panic:" /tmp/${case}_run.log | head -1 | sed 's/^/    /'
            elif [ $exit_code -eq 137 ]; then
                run_fail=$((run_fail + 1))
                echo -e "  运行: ${YELLOW}⚠️  超时 (exit 137)${NC}"
            elif [ $exit_code -eq 0 ]; then
                run_success=$((run_success + 1))
                echo "  运行: ✅"
                
                # 检查输出
                if php "tests/aot/suite/${case}.php" > /tmp/${case}_php.log 2>&1; then
                    if diff -q /tmp/${case}_run.log /tmp/${case}_php.log > /dev/null 2>&1; then
                        output_match=$((output_match + 1))
                        echo "  输出: ✅ 匹配"
                    else
                        output_mismatch=$((output_mismatch + 1))
                        echo -e "  输出: ${YELLOW}⚠️  不匹配${NC}"
                    fi
                fi
            else
                run_fail=$((run_fail + 1))
                echo -e "  运行: ${RED}❌ (exit $exit_code)${NC}"
            fi
        fi
    else
        compile_fail=$((compile_fail + 1))
        echo -e "${RED}编译❌${NC}"
        echo "  错误信息："
        grep "error:" /tmp/${case}_compile.log | head -3 | sed 's/^/    /'
    fi
done

echo ""
echo "[4/4] P0-3 验证：unset 语义（1 个用例）"
echo "----------------------------------------"
for case in "${P0_3_CASES[@]}"; do
    total_tests=$((total_tests + 1))
    echo -n "测试 $case ... "
    
    # 编译测试
    if tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile "tests/aot/suite/${case}.php" > /tmp/${case}_compile.log 2>&1; then
        compile_success=$((compile_success + 1))
        echo -e "${GREEN}编译✅${NC}"
        
        # 运行测试
        if [ -f "./${case}" ]; then
            if ZIGPHP_ALLOC_STATS=1 tests/aot/timeout.sh 4 "./${case}" > /tmp/${case}_run.log 2>&1; then
                run_success=$((run_success + 1))
                echo "  运行: ✅"
                
                # 检查输出
                if php "tests/aot/suite/${case}.php" > /tmp/${case}_php.log 2>&1; then
                    if diff -q /tmp/${case}_run.log /tmp/${case}_php.log > /dev/null 2>&1; then
                        output_match=$((output_match + 1))
                        echo "  输出: ✅ 匹配"
                    else
                        output_mismatch=$((output_mismatch + 1))
                        echo -e "  输出: ${YELLOW}⚠️  不匹配${NC}"
                        echo "  期望输出："
                        cat /tmp/${case}_php.log | sed 's/^/    /'
                        echo "  实际输出："
                        cat /tmp/${case}_run.log | sed 's/^/    /'
                    fi
                fi
                
                # 检查内存泄漏
                if grep -q "live_allocs=0" /tmp/${case}_run.log; then
                    echo "  内存: ✅ 无泄漏"
                else
                    echo -e "  内存: ${YELLOW}⚠️  可能有泄漏${NC}"
                    grep "live_allocs" /tmp/${case}_run.log | sed 's/^/    /'
                fi
            else
                run_fail=$((run_fail + 1))
                exit_code=$?
                echo -e "  运行: ${RED}❌ (exit $exit_code)${NC}"
            fi
        fi
    else
        compile_fail=$((compile_fail + 1))
        echo -e "${RED}编译❌${NC}"
        echo "  错误信息："
        grep "error:" /tmp/${case}_compile.log | head -3 | sed 's/^/    /'
    fi
done

echo ""
echo "=========================================="
echo "P0 验证结果汇总"
echo "=========================================="
echo ""
echo "总测试数: $total_tests"
echo ""
echo "编译结果:"
echo "  成功: ${compile_success}/${total_tests}"
echo "  失败: ${compile_fail}/${total_tests}"
echo ""
echo "运行结果:"
echo "  成功: ${run_success}/${compile_success}"
echo "  失败: ${run_fail}/${compile_success}"
echo ""
echo "输出匹配:"
echo "  匹配: ${output_match}/${run_success}"
echo "  不匹配: ${output_mismatch}/${run_success}"
echo ""

# 计算成功率
if [ $total_tests -gt 0 ]; then
    compile_rate=$((compile_success * 100 / total_tests))
    echo "编译成功率: ${compile_rate}%"
fi

if [ $compile_success -gt 0 ]; then
    run_rate=$((run_success * 100 / compile_success))
    echo "运行成功率: ${run_rate}%"
fi

if [ $run_success -gt 0 ]; then
    output_rate=$((output_match * 100 / run_success))
    echo "输出匹配率: ${output_rate}%"
fi

echo ""
echo "=========================================="

# 判断是否全部通过
if [ $compile_fail -eq 0 ] && [ $run_fail -eq 0 ]; then
    echo -e "${GREEN}🎉 P0 阶段验证通过！所有用例编译和运行成功。${NC}"
    exit 0
elif [ $compile_fail -eq 0 ]; then
    echo -e "${YELLOW}⚠️  P0 阶段部分通过：编译全部成功，但有运行失败。${NC}"
    exit 1
else
    echo -e "${RED}❌ P0 阶段验证失败：仍有编译错误。${NC}"
    exit 1
fi
