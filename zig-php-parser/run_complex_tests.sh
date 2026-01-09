#!/bin/bash
# 复杂功能测试脚本

INTERPRETER="./zig-out/bin/php-interpreter"
TEST_DIR="examples/tests/complex"

echo "=== 复杂功能测试 ==="
echo ""

success=0
failed=0
crashed=0
total=0

# 遍历所有测试目录
for dir in "$TEST_DIR"/*/; do
    echo "Testing: $(basename "$dir")"
    for file in "$dir"*.php; do
        if [ -f "$file" ]; then
            total=$((total + 1))
            
            # 运行测试
            result=$("$INTERPRETER" "$file" 2>&1)
            exit_code=$?
            
            # 获取PHP原生输出作为基准
            php_result=$(php "$file" 2>&1)
            php_exit=$?

            # 移除解释器的统计信息行
            result=$(echo "$result" | sed '/^=== PHP Interpreter Performance Statistics ===$/,/^===============================================$/d')
            
            # 检查是否崩溃
            if [ $exit_code -ne 0 ]; then
                echo "  [CRASH] $(basename "$file")"
                crashed=$((crashed + 1))
                continue
            fi
            
            # 检查输出是否匹配
            if [ "$result" = "$php_result" ]; then
                echo "  [PASS] $(basename "$file")"
                success=$((success + 1))
            else
                echo "  [FAIL] $(basename "$file")"
                failed=$((failed + 1))
                echo "    Expected:"
                echo "$php_result" | head -3 | sed 's/^/      /'
                echo "    Got:"
                echo "$result" | head -3 | sed 's/^/      /'
            fi
        fi
    done
    echo ""
done

echo "=== 结果汇总 ==="
echo "总计: $total"
echo "通过: $success"
echo "失败: $failed"
echo "崩溃: $crashed"
