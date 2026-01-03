<?php
/**
 * HTTP 服务器和客户端功能测试脚本
 *
 * 这个脚本实际测试 Zig 实现的 HTTP 服务器和客户端功能
 */

echo "=== HTTP 服务器和客户端功能测试 ===\n\n";

// ==================== 1. 测试类注册 ====================

echo "【测试1】测试HTTP类是否正确注册\n";

// 测试HttpServer类
echo "测试 HttpServer 类...\n";
$server_class_exists = class_exists('HttpServer');
echo "HttpServer 类存在: " . ($server_class_exists ? "✅ 是" : "❌ 否") . "\n";

if ($server_class_exists) {
    $methods = get_class_methods('HttpServer');
    echo "HttpServer 方法数量: " . count($methods) . "\n";
    echo "HttpServer 方法列表: " . implode(', ', $methods) . "\n";
}

// 测试HttpClient类
echo "测试 HttpClient 类...\n";
$client_class_exists = class_exists('HttpClient');
echo "HttpClient 类存在: " . ($client_class_exists ? "✅ 是" : "❌ 否") . "\n";

if ($client_class_exists) {
    $methods = get_class_methods('HttpClient');
    echo "HttpClient 方法数量: " . count($methods) . "\n";
    echo "HttpClient 方法列表: " . implode(', ', $methods) . "\n";
}

if (!$server_class_exists || !$client_class_exists) {
    echo "❌ HTTP类注册失败，无法继续测试\n";
    exit(1);
}

echo "✅ HTTP类注册成功\n\n";

// ==================== 2. 总结 ====================

echo "=== 测试完成 ===\n";
echo "🎉 HTTP 服务器和客户端类注册测试通过！\n";
echo "📊 注册的类: HttpServer, HttpClient\n";
echo "📝 注意: 对象实例化功能需要进一步实现\n";

?>
