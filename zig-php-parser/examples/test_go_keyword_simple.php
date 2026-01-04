<?php
echo "=== 测试 go 关键词（简单版） ===\n\n";

// 测试1: go function()
echo "【测试1】go function()\n";
go function() {
    echo "Coroutine 1 started\n";
    echo "Coroutine 1 completed\n";
};
echo "Main continues\n\n";

// 测试2: go 闭包
echo "【测试2】go 闭包\n";
$message = "Hello from coroutine";
go function() use ($message) {
    echo "$message\n";
};
echo "Main continues\n\n";

// 测试3: 多个协程
echo "【测试3】多个协程\n";
go function() { echo "Coroutine A\n"; };
go function() { echo "Coroutine B\n"; };
go function() { echo "Coroutine C\n"; };
echo "All coroutines spawned\n\n";

echo "✅ go 关键词测试完成\n";
