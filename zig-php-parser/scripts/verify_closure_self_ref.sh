#!/bin/bash
# 闭包自引用修复验证脚本 (AOT-CLOSURE-SELF-REF-001)
# 用法: bash scripts/verify_closure_self_ref.sh

set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$PROJ_DIR/zig-out/bin/php-interpreter"
PASS=0
FAIL=0
TOTAL=0

run_aot_test() {
    local php_file="$1"
    local expected="$2"
    local label="$3"
    TOTAL=$((TOTAL + 1))

    local tmp="/tmp/zigphp_test_$$"
    if timeout 5 "$BIN" --compile "$php_file" --output="$tmp" >/dev/null 2>&1; then
        local actual
        actual=$(timeout 3 "$tmp" 2>/dev/null || true)
        rm -f "$tmp"
        if [ "$actual" = "$expected" ]; then
            echo "  ✅ $label (got: $actual)"
            PASS=$((PASS + 1))
        else
            echo "  ❌ $label (expected: $expected, got: $actual)"
            FAIL=$((FAIL + 1))
        fi
    else
        rm -f "$tmp"
        echo "  ❌ $label (compile failed)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== 闭包自引用修复验证 ==="
echo ""

# 1. 编译检查
echo "[1/4] 编译检查..."
if (cd "$PROJ_DIR" && zig build >/dev/null 2>&1); then
    echo "  ✅ zig build 通过"
else
    echo "  ❌ zig build 失败"
    exit 1
fi

# 2. 核心测试: test_028 (闭包自引用阶乘)
echo ""
echo "[2/4] 核心测试..."
run_aot_test "$PROJ_DIR/gemini_scripts/failed/test_028.php" "120" "test_028 (闭包自引用阶乘)"

# 3. 额外闭包测试
echo ""
echo "[3/4] 额外闭包测试..."
EXTRA_DIR="$PROJ_DIR/gemini_scripts/closure_tests"
if [ -d "$EXTRA_DIR" ]; then
    for f in "$EXTRA_DIR"/*.php; do
        [ -f "$f" ] || continue
        expected=$(head -5 "$f" | sed -n 's|.*// expect: \(.*\)|\1|p')
        if [ -n "$expected" ]; then
            run_aot_test "$f" "$expected" "$(basename "$f")"
        fi
    done
fi

# 4. 回归测试
echo ""
echo "[4/4] 回归测试 (gemini_scripts/failed/*.php)..."
REGRESS_PASS=0
REGRESS_TOTAL=0
for f in "$PROJ_DIR"/gemini_scripts/failed/*.php; do
    REGRESS_TOTAL=$((REGRESS_TOTAL + 1))
    tmp="/tmp/zigphp_regress_$$"
    if timeout 5 "$BIN" --compile "$f" --output="$tmp" >/dev/null 2>&1 && \
       timeout 3 "$tmp" >/dev/null 2>&1; then
        REGRESS_PASS=$((REGRESS_PASS + 1))
        rm -f "$tmp"
    else
        rm -f "$tmp"
        echo "  ❌ $(basename "$f")"
    fi
done
echo "  回归: $REGRESS_PASS/$REGRESS_TOTAL 通过"

# 汇总
echo ""
echo "=== 验证汇总 ==="
echo "  核心+额外测试: $PASS/$TOTAL 通过, $FAIL 失败"
echo "  回归测试: $REGRESS_PASS/$REGRESS_TOTAL 通过"
if [ "$FAIL" -eq 0 ]; then
    echo "  🎉 所有核心测试通过!"
    exit 0
else
    echo "  ⚠️  有 $FAIL 个测试失败"
    exit 1
fi
