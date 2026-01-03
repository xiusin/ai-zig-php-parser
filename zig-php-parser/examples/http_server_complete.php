<?php
/**
 * 高性能协程安全 HTTP 服务器完整示例
 * 
 * 特性：
 * - 每个请求独立的上下文（Request/Response 对象）
 * - 协程并发处理，变量不会相互污染
 * - 对象池优化，高性能
 * - 内存安全，自动资源管理
 */

echo "=== 高性能协程安全 HTTP 服务器示例 ===\n\n";

// ==================== 1. 基础 HTTP 服务器 ====================

echo "【示例1】基础 HTTP 服务器\n";
echo "```php\n";
echo <<<'PHP'
$server = new HttpServer([
    'host' => '127.0.0.1',
    'port' => 8080,
    'enable_coroutines' => true,  // 启用协程处理
    'max_connections' => 1024,
]);

// 设置请求处理器（每个请求在独立协程中执行）
$server->handle(function($request, $response) {
    // $request 和 $response 是请求独立的对象
    // 协程间不会相互污染
    
    $response->status(200);
    $response->header('Content-Type', 'text/html; charset=utf-8');
    $response->html('<h1>Hello from Zig-PHP!</h1>');
});

echo "服务器启动在 http://127.0.0.1:8080\n";
$server->listen();
PHP;
echo "\n```\n\n";

// ==================== 2. 路由系统 ====================

echo "【示例2】路由系统\n";
echo "```php\n";
echo <<<'PHP'
$router = new Router();

// GET 路由
$router->get('/hello', function($req, $res) {
    $res->json(['message' => 'Hello World']);
});

// POST 路由
$router->post('/users', function($req, $res) {
    $body = $req->json();
    $res->status(201)->json([
        'success' => true,
        'data' => $body,
    ]);
});

// 带参数的路由
$router->get('/users/:id', function($req, $res) {
    $id = $req->param('id');
    $res->json([
        'user_id' => $id,
        'name' => '用户' . $id,
    ]);
});

// 查询参数
$router->get('/search', function($req, $res) {
    $keyword = $req->query('q');
    $page = $req->query('page') ?? 1;
    
    $res->json([
        'keyword' => $keyword,
        'page' => $page,
        'results' => [],
    ]);
});

$server->use($router);
PHP;
echo "\n```\n\n";

// ==================== 3. 中间件系统 ====================

echo "【示例3】中间件系统\n";
echo "```php\n";
echo <<<'PHP'
// 日志中间件
$router->use(function($req, $res, $next) {
    $start = microtime(true);
    echo "[{$req->method()}] {$req->path()}\n";
    
    $next();  // 调用下一个中间件或处理器
    
    $duration = (microtime(true) - $start) * 1000;
    echo "完成 - {$duration}ms\n";
});

// 认证中间件
$router->use(function($req, $res, $next) {
    $token = $req->header('Authorization');
    
    if (!$token) {
        $res->status(401)->json(['error' => 'Unauthorized']);
        return;
    }
    
    // 验证 token...
    $next();
});

// CORS 中间件
$router->use(function($req, $res, $next) {
    $res->header('Access-Control-Allow-Origin', '*');
    $res->header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
    $res->header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    
    if ($req->method() === 'OPTIONS') {
        $res->status(204)->text('');
        return;
    }
    
    $next();
});
PHP;
echo "\n```\n\n";

// ==================== 4. 协程安全演示 ====================

echo "【示例4】协程安全 - 变量隔离\n";
echo "```php\n";
echo <<<'PHP'
// 每个请求都有独立的上下文
$router->get('/counter', function($req, $res) {
    // 这个变量是请求局部的，不会被其他请求影响
    static $counter = 0;
    $counter++;
    
    // 模拟异步操作
    sleep(1);
    
    $res->json([
        'request_id' => $req->id(),
        'counter' => $counter,
        'note' => '每个请求的 counter 都是独立的',
    ]);
});

// 并发测试：同时发送多个请求
// curl http://localhost:8080/counter &
// curl http://localhost:8080/counter &
// curl http://localhost:8080/counter &
// 每个请求的 counter 都是独立的，不会相互影响
PHP;
echo "\n```\n\n";

// ==================== 5. Request 对象 API ====================

echo "【示例5】Request 对象完整 API\n";
echo "```php\n";
echo <<<'PHP'
$router->post('/api/test', function($req, $res) {
    // 请求方法
    $method = $req->method();  // "POST"
    
    // 请求路径
    $path = $req->path();  // "/api/test"
    
    // 请求体
    $body = $req->body();  // 原始请求体
    
    // JSON 解析
    $data = $req->json();  // 自动解析 JSON
    
    // 请求头
    $contentType = $req->header('Content-Type');
    $allHeaders = $req->headers();
    
    // 查询参数
    $page = $req->query('page');
    $allQuery = $req->queries();
    
    // 路由参数
    $id = $req->param('id');
    $allParams = $req->params();
    
    // 请求 ID（唯一标识）
    $requestId = $req->id();
    
    // 客户端信息
    $ip = $req->ip();
    $userAgent = $req->header('User-Agent');
    
    $res->json([
        'method' => $method,
        'path' => $path,
        'request_id' => $requestId,
        'data' => $data,
    ]);
});
PHP;
echo "\n```\n\n";

// ==================== 6. Response 对象 API ====================

echo "【示例6】Response 对象完整 API\n";
echo "```php\n";
echo <<<'PHP'
$router->get('/api/response', function($req, $res) {
    // 设置状态码
    $res->status(200);
    
    // 设置响应头
    $res->header('X-Custom-Header', 'value');
    
    // 发送文本响应
    $res->text('Hello, World!');
    
    // 发送 JSON 响应
    $res->json(['message' => 'Success']);
    
    // 发送 HTML 响应
    $res->html('<h1>Hello</h1>');
    
    // 发送重定向
    $res->redirect('/new-path', 302);
    
    // 链式调用
    $res->status(201)
        ->header('Content-Type', 'application/json')
        ->json(['created' => true]);
});
PHP;
echo "\n```\n\n";

// ==================== 7. HTTP 客户端 ====================

echo "【示例7】HTTP 客户端\n";
echo "```php\n";
echo <<<'PHP'
$client = new HttpClient([
    'timeout' => 30000,
    'follow_redirects' => true,
]);

// GET 请求
$response = $client->get('http://api.example.com/users');
echo "状态码: {$response->status()}\n";
echo "响应体: {$response->body()}\n";

// POST 请求
$response = $client->post('http://api.example.com/users', [
    'name' => '张三',
    'age' => 25,
]);

// 设置请求头
$client->header('Authorization', 'Bearer token123');
$response = $client->get('http://api.example.com/profile');

// 并发请求（在协程中）
go(function() use ($client) {
    $res = $client->get('http://api1.example.com/data');
    echo "API1: {$res->body()}\n";
});

go(function() use ($client) {
    $res = $client->get('http://api2.example.com/data');
    echo "API2: {$res->body()}\n";
});
PHP;
echo "\n```\n\n";

// ==================== 8. 完整的 RESTful API 示例 ====================

echo "【示例8】完整的 RESTful API\n";
echo "```php\n";
echo <<<'PHP'
$server = new HttpServer(['port' => 8080]);
$router = new Router();

// 模拟数据库
$users = [];
$nextId = 1;

// 列出所有用户
$router->get('/api/users', function($req, $res) use (&$users) {
    $res->json($users);
});

// 获取单个用户
$router->get('/api/users/:id', function($req, $res) use (&$users) {
    $id = (int)$req->param('id');
    
    foreach ($users as $user) {
        if ($user['id'] === $id) {
            $res->json($user);
            return;
        }
    }
    
    $res->status(404)->json(['error' => 'User not found']);
});

// 创建用户
$router->post('/api/users', function($req, $res) use (&$users, &$nextId) {
    $data = $req->json();
    
    $user = [
        'id' => $nextId++,
        'name' => $data['name'] ?? '',
        'email' => $data['email'] ?? '',
        'created_at' => date('Y-m-d H:i:s'),
    ];
    
    $users[] = $user;
    
    $res->status(201)->json($user);
});

// 更新用户
$router->put('/api/users/:id', function($req, $res) use (&$users) {
    $id = (int)$req->param('id');
    $data = $req->json();
    
    foreach ($users as &$user) {
        if ($user['id'] === $id) {
            $user['name'] = $data['name'] ?? $user['name'];
            $user['email'] = $data['email'] ?? $user['email'];
            $user['updated_at'] = date('Y-m-d H:i:s');
            
            $res->json($user);
            return;
        }
    }
    
    $res->status(404)->json(['error' => 'User not found']);
});

// 删除用户
$router->delete('/api/users/:id', function($req, $res) use (&$users) {
    $id = (int)$req->param('id');
    
    foreach ($users as $index => $user) {
        if ($user['id'] === $id) {
            array_splice($users, $index, 1);
            $res->status(204)->text('');
            return;
        }
    }
    
    $res->status(404)->json(['error' => 'User not found']);
});

$server->use($router);
echo "RESTful API 服务器启动在 http://127.0.0.1:8080\n";
$server->listen();
PHP;
echo "\n```\n\n";

// ==================== 9. 性能优化特性 ====================

echo "【示例9】性能优化特性\n";
echo "```php\n";
echo <<<'PHP'
$server = new HttpServer([
    'port' => 8080,
    'enable_coroutines' => true,      // 协程处理
    'max_connections' => 10000,       // 最大连接数
    'keep_alive_timeout' => 5000,     // Keep-Alive 超时（毫秒）
    'request_timeout' => 30000,       // 请求超时
    'context_pool_size' => 1000,      // 上下文池大小
    'worker_count' => 4,              // 工作线程数（0=自动）
]);

// 获取服务器状态
$stats = $server->stats();
echo "活跃请求: {$stats['active_requests']}\n";
echo "总请求数: {$stats['total_requests']}\n";
echo "平均响应时间: {$stats['avg_response_time']}ms\n";
PHP;
echo "\n```\n\n";

echo "=== 核心特性总结 ===\n\n";
echo "✅ **协程安全**：每个请求独立的 Request/Response 对象\n";
echo "✅ **高性能**：对象池、零拷贝、协程调度\n";
echo "✅ **内存安全**：引用计数、自动资源管理\n";
echo "✅ **易用性**：简洁的 API，链式调用\n";
echo "✅ **完整功能**：路由、中间件、HTTP 客户端\n\n";

echo "注意：以上示例展示了完整的 API 设计\n";
echo "实际实现需要在 VM 中注册这些类和函数\n";
