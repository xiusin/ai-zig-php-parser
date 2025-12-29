#!/bin/bash

# HTTP协程服务框架完整测试套件运行脚本

echo "======================================================================"
echo "           HTTP协程服务框架完整测试套件"
echo "======================================================================"
echo ""

INTERPRETER="./zig-out/bin/php-interpreter"
TEST_DIR="."
PASSED=0
FAILED=0

# 检查解释器是否存在
if [ ! -f "$INTERPRETER" ]; then
    echo "错误: PHP解释器不存在: $INTERPRETER"
    echo "请先运行: zig build"
    exit 1
fi

# 测试文件列表
TESTS=(
    "test_http_server.php"
    "test_http_client.php"
    "test_coroutine_concurrency.php"
    "test_router_middleware.php"
    "test_memory_safety.php"
    "test_request_context.php"
)

# 运行每个测试
for test in "${TESTS[@]}"; do
    echo "======================================================================"
    echo "运行测试: $test"
    echo "======================================================================"
    
    if [ -f "$TEST_DIR/$test" ]; then
        $INTERPRETER "$TEST_DIR/$test"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ $test 执行完成"
            PASSED=$((PASSED + 1))
        else
            echo ""
            echo "❌ $test 执行失败"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "⚠️  测试文件不存在: $test"
        FAILED=$((FAILED + 1))
    fi
    
    echo ""
done

# 输出总结
echo "======================================================================"
echo "                        测试总结"
echo "======================================================================"
echo "总测试文件数: $((PASSED + FAILED))"
echo "通过: $PASSED"
echo "失败: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 所有测试套件执行完成!"
    exit 0
else
    echo "⚠️  部分测试套件执行失败"
    exit 1
fi
