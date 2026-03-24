#!/bin/bash
# AOT模糊测试综合对比脚本

set -e

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser"
REPORT_FILE="$SCRIPT_DIR/AOT_测试问题汇总报告.md"
PHP_BIN="php"
AOT_BIN="$SCRIPT_DIR/zig-out/bin/php-interpreter"

# 计数器
TOTAL=0
PASSED=0
COMPILE_FAIL=0
MISMATCH=0
RUNTIME_FAIL=0
PHP_FAIL=0
SKIPPED=0

# 临时文件
PHP_OUT=$(mktemp)
AOT_OUT=$(mktemp)
COMPILE_ERR=$(mktemp)
trap "rm -f $PHP_OUT $AOT_OUT $COMPILE_ERR" EXIT

# 初始化报告
echo "# AOT 测试问题汇总报告" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**测试时间**: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**PHP解释器**: $PHP_BIN" >> "$REPORT_FILE"
echo "**AOT编译器**: $AOT_BIN" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 问题列表文件
ISSUES_FILE=$(mktemp)

# 测试函数
test_file() {
    local file="$1"
    local dir_name="$2"
    local basename=$(basename "$file")
    local aot_exe="${file%.php}_aot_test"
    
    TOTAL=$((TOTAL + 1))
    
    # 跳过pass目录
    if [[ "$file" == *"/pass/"* ]]; then
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    
    # 跳过包含随机性的测试
    if grep -qi "rand\|mt_rand\|random_\|shuffle" "$file" 2>/dev/null; then
        SKIPPED=$((SKIPPED + 1))
        echo "  [SKIP] $basename (randomness)" 
        return 0
    fi
    
    # PHP原生执行
    timeout 5 $PHP_BIN "$file" > "$PHP_OUT" 2>&1
    local php_exit=$?
    
    # PHP执行失败检查
    if [ $php_exit -ne 0 ] && grep -qi "fatal error\|parse error" "$PHP_OUT"; then
        PHP_FAIL=$((PHP_FAIL + 1))
        echo "  [PHP_FAIL] $basename"
        echo "PHP_FAIL|$basename|$dir_name" >> "$ISSUES_FILE"
        return 0
    fi
    
    # AOT编译
    timeout 30 $AOT_BIN --compile --output "$aot_exe" "$file" > "$COMPILE_ERR" 2>&1
    local compile_exit=$?
    
    if [ $compile_exit -ne 0 ]; then
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        echo "  [COMPILE_FAIL] $basename"
        local err_msg=$(cat "$COMPILE_ERR" | tr '\n' ' ' | cut -c1-100)
        echo "COMPILE_FAIL|$basename|$dir_name|$err_msg" >> "$ISSUES_FILE"
        return 0
    fi
    
    # AOT执行
    timeout 5 "$aot_exe" > "$AOT_OUT" 2>&1
    local aot_exit=$?
    
    # 清理
    rm -f "$aot_exe"
    
    # 检查AOT运行时错误
    if [ $aot_exit -ne 0 ] || grep -qi "panic\|error:\|segmentation fault\|abort trap" "$AOT_OUT"; then
        RUNTIME_FAIL=$((RUNTIME_FAIL + 1))
        echo "  [RUNTIME_FAIL] $basename"
        local err_msg=$(cat "$AOT_OUT" | tr '\n' ' ' | cut -c1-100)
        echo "RUNTIME_FAIL|$basename|$dir_name|$err_msg" >> "$ISSUES_FILE"
        return 0
    fi
    
    # 对比输出 (标准化)
    # 移除尾部空白后比较
    local php_norm=$(cat "$PHP_OUT" | sed 's/[[:space:]]*$//' | tr -s '\n')
    local aot_norm=$(cat "$AOT_OUT" | sed 's/[[:space:]]*$//' | tr -s '\n')
    
    if [ "$php_norm" = "$aot_norm" ]; then
        PASSED=$((PASSED + 1))
        echo "  [PASS] $basename"
    else
        MISMATCH=$((MISMATCH + 1))
        echo "  [MISMATCH] $basename"
        echo "MISMATCH|$basename|$dir_name" >> "$ISSUES_FILE"
        # 保存详细差异
        mkdir -p "$SCRIPT_DIR/test_diff"
        echo "=== PHP ===" > "$SCRIPT_DIR/test_diff/${basename}.diff"
        cat "$PHP_OUT" >> "$SCRIPT_DIR/test_diff/${basename}.diff"
        echo "" >> "$SCRIPT_DIR/test_diff/${basename}.diff"
        echo "=== AOT ===" >> "$SCRIPT_DIR/test_diff/${basename}.diff"
        cat "$AOT_OUT" >> "$SCRIPT_DIR/test_diff/${basename}.diff"
    fi
}

# 收集测试文件
echo "收集测试文件..."
TEST_FILES=""

# fuzzy_scripts_27 目录
for dir in "$SCRIPT_DIR/fuzzy_scripts_27" "$SCRIPT_DIR/fuzzy_scripts_27/failed"; do
    if [ -d "$dir" ]; then
        for f in "$dir"/test_*.php; do
            if [ -f "$f" ]; then
                TEST_FILES="$TEST_FILES $f"
            fi
        done
    fi
done

# fuzzy_scripts 目录
for dir in "$SCRIPT_DIR/fuzzy_scripts" "$SCRIPT_DIR/fuzzy_scripts/failed"; do
    if [ -d "$dir" ]; then
        for f in "$dir"/test_*.php; do
            if [ -f "$f" ]; then
                TEST_FILES="$TEST_FILES $f"
            fi
        done
    fi
done

# 排序并去重
TEST_FILES=$(echo $TEST_FILES | tr ' ' '\n' | sort -u | tr '\n' ' ')

TOTAL_FILES=$(echo $TEST_FILES | wc -w | tr -d ' ')
echo "找到 $TOTAL_FILES 个测试文件"
echo "开始测试..."
echo "========================================"

# 测试每个文件
count=0
for file in $TEST_FILES; do
    if [ -f "$file" ]; then
        count=$((count + 1))
        # 确定目录名
        if [[ "$file" == *"fuzzy_scripts_27"* ]]; then
            dir_name="fuzzy_scripts_27"
        else
            dir_name="fuzzy_scripts"
        fi
        test_file "$file" "$dir_name"
        
        # 每20个显示进度
        if [ $((count % 20)) -eq 0 ]; then
            echo ""
            echo "进度: $count/$TOTAL_FILES - 通过:$PASSED 编译失败:$COMPILE_FAIL 输出不一致:$MISMATCH 运行时错误:$RUNTIME_FAIL"
            echo ""
        fi
    fi
done

echo ""
echo "========================================"
echo "生成报告..."

# 写入汇总
echo "" >> "$REPORT_FILE"
echo "## 测试结果汇总" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| 类型 | 数量 | 说明 |" >> "$REPORT_FILE"
echo "|------|------|------|" >> "$REPORT_FILE"
echo "| **PASS** | $PASSED | AOT执行结果与PHP一致 |" >> "$REPORT_FILE"
echo "| **MISMATCH** | $MISMATCH | AOT与PHP输出结果不一致 |" >> "$REPORT_FILE"
echo "| **COMPILE_FAIL** | $COMPILE_FAIL | AOT编译失败 |" >> "$REPORT_FILE"
echo "| **RUNTIME_FAIL** | $RUNTIME_FAIL | AOT运行时失败 |" >> "$REPORT_FILE"
echo "| **PHP_FAIL** | $PHP_FAIL | PHP原生执行失败 |" >> "$REPORT_FILE"
echo "| **SKIP** | $SKIPPED | 跳过测试 |" >> "$REPORT_FILE"

# 计算通过率
VALID_TOTAL=$((TOTAL - SKIPPED - PHP_FAIL))
if [ $VALID_TOTAL -gt 0 ]; then
    PASS_RATE=$((PASSED * 100 / VALID_TOTAL))
    echo "" >> "$REPORT_FILE"
    echo "**通过率**: ${PASS_RATE}% (排除PHP失败和跳过)" >> "$REPORT_FILE"
fi

# 写入问题详情
echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## 问题详细列表" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 编译失败
if grep -q "^COMPILE_FAIL" "$ISSUES_FILE" 2>/dev/null; then
    echo "### 1. COMPILE_FAIL - 编译失败" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "| 脚本名称 | 目录 | 错误详情 |" >> "$REPORT_FILE"
    echo "|----------|------|----------|" >> "$REPORT_FILE"
    grep "^COMPILE_FAIL" "$ISSUES_FILE" | while IFS='|' read -r type name dir detail; do
        echo "| $name | $dir | ${detail:0:100} |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
fi

# 输出不一致
if grep -q "^MISMATCH" "$ISSUES_FILE" 2>/dev/null; then
    echo "### 2. MISMATCH - 输出不一致" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    grep "^MISMATCH" "$ISSUES_FILE" | while IFS='|' read -r type name dir; do
        echo "#### $name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "**目录**: $dir" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        if [ -f "$SCRIPT_DIR/test_diff/${name}.diff" ]; then
            echo '```' >> "$REPORT_FILE"
            cat "$SCRIPT_DIR/test_diff/${name}.diff" | head -30 >> "$REPORT_FILE"
            echo '```' >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    done
fi

# 运行时错误
if grep -q "^RUNTIME_FAIL" "$ISSUES_FILE" 2>/dev/null; then
    echo "### 3. RUNTIME_FAIL - 运行时错误" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "| 脚本名称 | 目录 | 错误详情 |" >> "$REPORT_FILE"
    echo "|----------|------|----------|" >> "$REPORT_FILE"
    grep "^RUNTIME_FAIL" "$ISSUES_FILE" | while IFS='|' read -r type name dir detail; do
        echo "| $name | $dir | ${detail:0:100} |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
fi

# PHP失败
if grep -q "^PHP_FAIL" "$ISSUES_FILE" 2>/dev/null; then
    echo "### 4. PHP_FAIL - PHP原生执行失败" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "> 以下脚本在原生PHP执行时本身存在错误，不计入AOT问题统计" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "| 脚本名称 | 目录 |" >> "$REPORT_FILE"
    echo "|----------|------|" >> "$REPORT_FILE"
    grep "^PHP_FAIL" "$ISSUES_FILE" | while IFS='|' read -r type name dir; do
        echo "| $name | $dir |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "*报告生成完成于 $(date '+%Y-%m-%d %H:%M:%S')*" >> "$REPORT_FILE"

# 清理
rm -f "$ISSUES_FILE"

# 打印总结
echo ""
echo "========================================"
echo "测试完成!"
echo "总计: $TOTAL"
echo "通过: $PASSED"
echo "编译失败: $COMPILE_FAIL"
echo "输出不一致: $MISMATCH"
echo "运行时错误: $RUNTIME_FAIL"
echo "PHP失败: $PHP_FAIL"
echo "跳过: $SKIPPED"
if [ $VALID_TOTAL -gt 0 ]; then
    echo "通过率: ${PASS_RATE}%"
fi
echo "报告: $REPORT_FILE"
echo "========================================"
