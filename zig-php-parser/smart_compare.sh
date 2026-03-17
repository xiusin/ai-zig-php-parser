#!/usr/bin/env bash
# 智能对比：忽略环境差异（内存、时间、文件数量等）

if [ $# -ne 2 ]; then
    echo "Usage: $0 <php_output> <aot_output>"
    exit 1
fi

php_out="$1"
aot_out="$2"

# 过滤环境相关的行
filter_env() {
    sed -E \
        -e 's/Memory usage: [0-9]+ bytes/Memory usage: XXX bytes/' \
        -e 's/Execution time: [0-9.]+ seconds/Execution time: XXX seconds/' \
        -e 's/Peak memory: [0-9]+ bytes/Peak memory: XXX bytes/' \
        -e 's/Current memory: [0-9]+ bytes/Current memory: XXX bytes/' \
        -e 's/Files in temp dir: [0-9]+/Files in temp dir: XXX/' \
        -e 's/microtime: [0-9.]+/microtime: XXX/' \
        -e 's/time: [0-9]+/time: XXX/'
}

php_filtered=$(filter_env < "$php_out")
aot_filtered=$(filter_env < "$aot_out")

if [ "$php_filtered" = "$aot_filtered" ]; then
    echo "PASS (环境差异已忽略)"
    exit 0
else
    echo "FAIL"
    diff <(echo "$php_filtered") <(echo "$aot_filtered") | head -20
    exit 1
fi
