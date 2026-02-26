#!/bin/bash
# 编译器稳定性压力测试
# 同一个文件编译 100 次，验证每次生成的代码是否完全一致

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== 编译器稳定性压力测试 ==="
echo "同一个文件编译 100 次，验证生成代码的一致性"
echo ""

# 测试文件
TEST_FILE="/tmp/test_concat_int.php"

if [ ! -f "$TEST_FILE" ]; then
    echo "创建测试文件..."
    cat > "$TEST_FILE" << 'EOF'
<?php
$x = 42;
echo "Value: " . $x . "\n";
EOF
fi

echo "测试文件: $TEST_FILE"
echo ""

# 第一次编译作为基准
echo "生成基准..."
rm -rf .zigphp_aot_build
./zig-out/bin/php-interpreter --compile --output=/tmp/baseline "$TEST_FILE" >/dev/null 2>&1

if [ ! -f ".zigphp_aot_build/main.zig" ]; then
    echo "❌ 编译失败"
    exit 1
fi

cp .zigphp_aot_build/main.zig /tmp/baseline.zig
BASELINE_HASH=$(md5 -q /tmp/baseline.zig 2>/dev/null || md5sum /tmp/baseline.zig | awk '{print $1}')

echo "基准哈希: $BASELINE_HASH"
echo ""

# 压力测试
ITERATIONS=100
PASSED=0
FAILED=0

echo "开始压力测试 ($ITERATIONS 次)..."

for i in $(seq 1 $ITERATIONS); do
    rm -rf .zigphp_aot_build
    ./zig-out/bin/php-interpreter --compile --output=/tmp/test_$i "$TEST_FILE" >/dev/null 2>&1
    
    if [ ! -f ".zigphp_aot_build/main.zig" ]; then
        echo "  [$i/$ITERATIONS] ❌ 编译失败"
        ((FAILED++))
        continue
    fi
    
    CURRENT_HASH=$(md5 -q .zigphp_aot_build/main.zig 2>/dev/null || md5sum .zigphp_aot_build/main.zig | awk '{print $1}')
    
    if [ "$CURRENT_HASH" = "$BASELINE_HASH" ]; then
        if [ $((i % 10)) -eq 0 ]; then
            echo "  [$i/$ITERATIONS] ✅"
        fi
        ((PASSED++))
    else
        echo "  [$i/$ITERATIONS] ❌ 生成代码不一致"
        echo "    基准: $BASELINE_HASH"
        echo "    当前: $CURRENT_HASH"
        
        # 显示差异
        diff -u /tmp/baseline.zig .zigphp_aot_build/main.zig | head -20
        
        ((FAILED++))
    fi
done

echo ""
echo "=== 测试结果 ==="
echo "总计: $ITERATIONS"
echo "通过: $PASSED"
echo "失败: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ 编译器完全稳定！$ITERATIONS 次编译生成完全相同的代码。"
    exit 0
else
    echo "❌ 编译器不稳定！有 $FAILED 次生成了不同的代码。"
    exit 1
fi
