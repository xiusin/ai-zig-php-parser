#!/bin/bash
# 快速编译测试

cd /Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser

echo "=== 编译项目 ==="
if zig build -Doptimize=ReleaseFast install 2>&1 | tee /tmp/build.log | tail -20; then
    echo ""
    echo "✅ 编译成功"
    
    echo ""
    echo "=== 测试单个用例 (05_foreach_break) ==="
    if tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/05_foreach_break.php 2>&1 | tee /tmp/test.log; then
        echo "✅ 05_foreach_break 编译成功"
    else
        echo "❌ 05_foreach_break 编译失败"
        echo "错误信息："
        grep "error:" /tmp/test.log | head -5
    fi
else
    echo ""
    echo "❌ 项目编译失败"
    echo "错误信息："
    grep "error:" /tmp/build.log | head -10
    exit 1
fi
