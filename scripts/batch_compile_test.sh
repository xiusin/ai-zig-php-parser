#!/bin/bash
cd /Users/wangjianjun/products/parser
pass=0
fail=0
fail_list=""
total=0
for f in fuzzy_scripts_720/pass/*.php fuzzy_scripts_720/fail_runtime/*.php fuzzy_scripts_720/fail_compile/*.php; do
    if [ -f "$f" ]; then
        total=$((total+1))
        result=$(zig-out/bin/php-interpreter --compile --output=/tmp/aot_regtest "$f" 2>&1 | tail -1)
        if echo "$result" | grep -q "Success"; then
            pass=$((pass+1))
        else
            fail=$((fail+1))
            fail_list="$fail_list\n$(basename $f): $result"
        fi
    fi
done
echo "=== Results ==="
echo "Total: $total"
echo "Pass: $pass"
echo "Fail: $fail"
echo -e "Failed scripts:$fail_list"
