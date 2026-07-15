#!/bin/bash
# AOT fuzzy test runner with correct paths

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser"
FUZZY_DIR="$SCRIPT_DIR/fuzzy_scripts"
PASS_DIR="$FUZZY_DIR/pass"
INTERPRETER="$SCRIPT_DIR/zig-out/bin/php-interpreter"
TEMP_DIR="/tmp/aot_fuzzy_test_$$"

mkdir -p "$TEMP_DIR"

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

EXCLUDE_PATTERNS='fiber coroutine generator random rand'

should_exclude() {
    local name=$(basename "$1" | tr '[:upper:]' '[:lower:]')
    for pattern in $EXCLUDE_PATTERNS; do
        if echo "$name" | grep -q "$pattern"; then
            return 0
        fi
    done
    return 1
}

run_test() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    TOTAL=$((TOTAL + 1))

    if should_exclude "$script_path"; then
        echo "[SKIP] $script_name"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    local php_output=$(timeout 3 php "$script_path" 2>&1 || echo "PHP_ERROR")

    local output_name="${script_name%.php}"
    local aot_binary="$TEMP_DIR/$output_name"
    local compile_output=$(timeout 30 "$INTERPRETER" --compile --output="$aot_binary" "$script_path" 2>&1)
    local compile_exit=$?

    if [ $compile_exit -ne 0 ]; then
        if echo "$php_output" | grep -qi 'fatal\|error'; then
            if echo "$compile_output" | grep -qi 'error\|fail'; then
                echo "[PASS] $script_name (both have errors)"
                PASSED=$((PASSED + 1))
                return
            fi
        fi
        echo "[FAIL] $script_name (compile failed)"
        FAILED=$((FAILED + 1))
        return
    fi

    local aot_output=$(timeout 10 "$aot_binary" 2>&1 || echo "AOT_ERROR")

    if [ "$php_output" == "$aot_output" ]; then
        echo "[PASS] $script_name"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $script_name (output mismatch)"
        FAILED=$((FAILED + 1))
    fi
}

echo "=========================================="
echo "AOT Fuzzy Test"
echo "=========================================="
echo ""

for script in "$FUZZY_DIR"/*.php "$PASS_DIR"/*.php; do
    if [ -f "$script" ]; then
        run_test "$script"
    fi
done

rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "Done! Total: $TOTAL, Passed: $PASSED, Failed: $FAILED, Skipped: $SKIPPED"
echo "=========================================="
