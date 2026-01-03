<?php

echo "=== HTTP基础功能测试 ===\n\n";

// 测试1: 简单的HTTP响应
echo "1. 测试HTTP响应函数:\n";

function handleRequest() {
    echo "HTTP/1.1 200 OK\n";
    echo "Content-Type: text/plain\n";
    echo "\n";
    echo "Hello from PHP HTTP Server!\n";
}

// 模拟调用
echo "调用handleRequest:\n";
handleRequest();
echo "\n";

// 测试2: JSON响应
echo "2. 测试JSON响应:\n";

function jsonResponse($data) {
    echo "HTTP/1.1 200 OK\n";
    echo "Content-Type: application/json\n";
    echo "\n";
    echo json_encode($data);
    echo "\n";
}

$response_data = array("status" => "success", "message" => "Hello World");
echo "调用jsonResponse:\n";
jsonResponse($response_data);
echo "\n";

// 测试3: 路由处理
echo "3. 测试路由处理:\n";

function router($path) {
    if ($path == "/") {
        echo "首页\n";
    } else if ($path == "/about") {
        echo "关于页面\n";
    } else if ($path == "/api/users") {
        echo "用户API\n";
    } else {
        echo "404 Not Found\n";
    }
}

echo "路由测试:\n";
router("/");
router("/about");
router("/api/users");
router("/unknown");
echo "\n";

echo "=== HTTP基础功能测试完成 ===\n";

?>
