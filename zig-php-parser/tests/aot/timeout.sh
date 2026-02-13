#!/bin/bash
# 简单的超时实现（兼容 macOS）

timeout_duration=$1
shift

# 后台运行命令
"$@" &
pid=$!

# 等待指定时间
( sleep $timeout_duration; kill -9 $pid 2>/dev/null ) &
killer=$!

# 等待命令完成
wait $pid 2>/dev/null
exit_code=$?

# 清理 killer
kill -9 $killer 2>/dev/null
wait $killer 2>/dev/null

exit $exit_code
