<?php

// 测试HTTP服务器功能（协程处理）

echo "=== 测试HTTP服务器 ===\n";

// 创建HTTP服务器配置
// 注意：这是扩展语法示例，展示预期的API设计

// 简单的HTTP服务器
// $server = http_server_create([
//     'host' => '127.0.0.1',
//     'port' => 8080,
//     'enable_coroutines' => true,
// ]);

// 设置请求处理器
// http_server_set_handler($server, function($request, $response) {
//     $response->setStatus(200);
//     $response->setHeader('Content-Type', 'text/html; charset=utf-8');
//     $response->setBody('<h1>Hello from Zig-PHP!</h1>');
// });

// 路由示例
// $router = http_router_create();

// GET路由
// $router->get('/hello', function($req, $res) {
//     $res->json(['message' => 'Hello World']);
// });

// POST路由
// $router->post('/users', function($req, $res) {
//     $body = $req->getBody();
//     $res->json(['created' => true, 'data' => $body]);
// });

// 带参数的路由
// $router->get('/users/:id', function($req, $res) {
//     $id = $req->getParam('id');
//     $res->json(['user_id' => $id]);
// });

// 中间件示例
// $router->use(function($req, $res, $next) {
//     echo "请求: " . $req->getMethod() . " " . $req->getPath() . "\n";
//     $next();
// });

// 启动服务器（在协程中处理每个请求）
// echo "服务器启动在 http://127.0.0.1:8080\n";
// http_server_start($server);

echo "\n=== HTTP客户端测试 ===\n";

// HTTP客户端请求
// $client = http_client_create([
//     'timeout' => 30000,
//     'follow_redirects' => true,
// ]);

// GET请求
// $response = $client->get('http://api.example.com/users');
// echo "状态码: " . $response->getStatusCode() . "\n";
// echo "响应体: " . $response->getBody() . "\n";

// POST请求
// $response = $client->post('http://api.example.com/users', [
//     'name' => '张三',
//     'age' => 25,
// ]);

// 带请求头
// $client->setHeader('Authorization', 'Bearer token123');
// $response = $client->get('http://api.example.com/profile');

// 协程并发请求示例
// go function() use ($client) {
//     $response = $client->get('http://api1.example.com/data');
//     echo "API1响应: " . $response->getBody() . "\n";
// };

// go function() use ($client) {
//     $response = $client->get('http://api2.example.com/data');
//     echo "API2响应: " . $response->getBody() . "\n";
// };

echo "\n=== HTTP测试完成 ===\n";
echo "注意: 带注释的代码需要在VM中实现HTTP服务器和客户端支持\n";
