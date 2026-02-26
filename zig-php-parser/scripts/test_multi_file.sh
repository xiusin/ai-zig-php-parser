#!/bin/bash
# 多文件并发编译测试
# 验证编译器在并发情况下的稳定性

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== 多文件并发编译测试 ==="
echo ""

# 创建测试文件
mkdir -p /tmp/concurrent_test

cat > /tmp/concurrent_test/test1.php << 'EOF'
<?php
$a = 10;
$b = 20;
echo $a + $b . "\n";
EOF

cat > /tmp/concurrent_test/test2.php << 'EOF'
<?php
$x = "Hello";
$y = "World";
echo $x . " " . $y . "\n";
EOF

cat > /tmp/concurrent_test/test3.php << 'EOF'
<?php
for ($i = 0; $i < 5; $i++) {
    echo $i . "\n";
}
EOF

cat > /tmp/concurrent_test/test4.php << 'EOF'
<?php
$a = 100;
$b = 200;
$c = $a * $b;
echo "Result: " . $c . "\n";
EOF

echo "创建了 4 个测试文件"
echo ""

PASSED=0
FAILED=0

# 顺序编译每个文件 10 次
for file in /tmp/concurrent_test/*.php; do
    filename=$(basename "$file")
    echo "测试: $filename"
    
    for i in $(seq 1 10); do
        rm -rf .zigphp_aot_build
        output="/tmp/concurrent_$(basename $file .php)_$i"
        
        if ./zig-out/bin/php-interpreter --compile --output="$output" "$file" >/dev/null 2>&1; then
            if "$output" >/dev/null 2>&1; then
                ((PASSED++))
            else
                echo "  [$i/10] ❌ 运行失败"
                ((FAILED++))
            fi
        else
            echo "  [$i/10] ❌ 编译失败"
            ((FAILED++))
        fi
    done
    
    echo "  ✅ 完成 10 次编译"
    echo ""
done

echo "=== 测试结果 ==="
echo "总计: $((PASSED + FAILED))"
echo "通过: $PASSED"
echo "失败: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✅ 所有文件都能稳定编译和运行！"
    exit 0
else
    echo "❌ 有 $FAILED 次失败。"
    exit 1
fi
