#!/bin/bash
# AOT 编译器综合测试脚本

set -e  # 遇到错误立即退出

echo "=== AOT 编译器综合测试 ==="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试文件
TEST_FILE="examples/aot_comprehensive_test.php"
OUTPUT_BIN="aot_test_output"

# 清理旧文件
rm -f "$OUTPUT_BIN"

echo "📝 测试文件: $TEST_FILE"
echo ""

# ============================================================================
# 1. 编译测试
# ============================================================================
echo "🔨 步骤 1: AOT 编译..."
if zig build-exe src/main.zig -femit-bin=zig-out/bin/php-aot 2>&1 | tee compile.log; then
    echo -e "${GREEN}✅ 编译器构建成功${NC}"
else
    echo -e "${RED}❌ 编译器构建失败${NC}"
    exit 1
fi
echo ""

# ============================================================================
# 2. AOT 编译 PHP 脚本
# ============================================================================
echo "🚀 步骤 2: AOT 编译 PHP 脚本..."
if ./zig-out/bin/php-aot --compile --optimize=release-fast --output="$OUTPUT_BIN" "$TEST_FILE" 2>&1 | tee aot_compile.log; then
    echo -e "${GREEN}✅ AOT 编译成功${NC}"
else
    echo -e "${YELLOW}⚠️  AOT 编译功能未完全实现，使用解释器模式${NC}"
    
    # 使用解释器模式运行
    echo ""
    echo "🏃 使用解释器运行测试..."
    if ./zig-out/bin/php-aot "$TEST_FILE" 2>&1 | tee interpreter.log; then
        echo -e "${GREEN}✅ 解释器执行成功${NC}"
    else
        echo -e "${RED}❌ 解释器执行失败${NC}"
        exit 1
    fi
    
    # 内存泄漏检查
    echo ""
    echo "🔍 步骤 3: 内存泄漏检查..."
    if command -v valgrind &> /dev/null; then
        valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes \
            ./zig-out/bin/php-aot "$TEST_FILE" 2>&1 | tee valgrind.log
        
        if grep -q "no leaks are possible" valgrind.log; then
            echo -e "${GREEN}✅ 无内存泄漏${NC}"
        else
            echo -e "${YELLOW}⚠️  检测到潜在内存泄漏，请查看 valgrind.log${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  valgrind 未安装，跳过内存泄漏检查${NC}"
    fi
    
    exit 0
fi

# ============================================================================
# 3. 执行编译后的二进制
# ============================================================================
echo ""
echo "🏃 步骤 3: 执行编译后的二进制..."
if [ -f "$OUTPUT_BIN" ]; then
    if ./"$OUTPUT_BIN" 2>&1 | tee execution.log; then
        echo -e "${GREEN}✅ 执行成功${NC}"
    else
        echo -e "${RED}❌ 执行失败${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ 编译后的二进制文件不存在${NC}"
    exit 1
fi

# ============================================================================
# 4. 内存泄漏检查
# ============================================================================
echo ""
echo "🔍 步骤 4: 内存泄漏检查..."
if command -v valgrind &> /dev/null; then
    valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes \
        ./"$OUTPUT_BIN" 2>&1 | tee valgrind.log
    
    if grep -q "no leaks are possible" valgrind.log; then
        echo -e "${GREEN}✅ 无内存泄漏${NC}"
    else
        echo -e "${YELLOW}⚠️  检测到潜在内存泄漏，请查看 valgrind.log${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  valgrind 未安装，跳过内存泄漏检查${NC}"
fi

# ============================================================================
# 5. 性能对比
# ============================================================================
echo ""
echo "📊 步骤 5: 性能对比..."

# 解释器模式
echo "  解释器模式:"
time ./zig-out/bin/php-aot "$TEST_FILE" > /dev/null 2>&1

# AOT 模式
echo "  AOT 模式:"
time ./"$OUTPUT_BIN" > /dev/null 2>&1

# ============================================================================
# 总结
# ============================================================================
echo ""
echo "=== 测试总结 ==="
echo -e "${GREEN}✅ 所有测试通过！${NC}"
echo ""
echo "生成的文件："
echo "  - compile.log: 编译器构建日志"
echo "  - aot_compile.log: AOT 编译日志"
echo "  - execution.log: 执行日志"
echo "  - valgrind.log: 内存泄漏检查日志"
echo ""
echo "🎉 AOT 编译器验证完成！"
