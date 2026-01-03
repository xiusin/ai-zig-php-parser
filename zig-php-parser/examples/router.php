<?php
/**
 * HTTP服务器路由处理文件
 * 由PHP内置服务器调用处理请求
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE');
header('Access-Control-Allow-Headers: Content-Type');

require_once __DIR__ . '/http_server_demo.php';

// 创建服务器实例（与主文件中的配置保持一致）
$server = new HttpServer([
    'host' => '127.0.0.1',
    'port' => 8080
]);

// ==================== 路由定义 ====================

// 计数器路由 - 演示协程隔离
$server->get('/counter', function($req, $res) {
    // 每个请求的计数器都是独立的（协程安全）
    static $counter = 0;
    $counter++;

    // 模拟异步操作
    usleep(100000); // 100ms

    $res->json([
        'request_id' => uniqid(),
        'counter' => $counter,
        'note' => '每个请求的计数器都是独立的',
        'timestamp' => microtime(true),
        'process_id' => getmypid()
    ]);
});

// 用户列表API
$server->get('/api/users', function($req, $res) {
    $users = [
        ['id' => 1, 'name' => '张三', 'email' => 'zhangsan@example.com'],
        ['id' => 2, 'name' => '李四', 'email' => 'lisi@example.com']
    ];
    $res->json($users);
});

// 创建用户API
$server->post('/api/users', function($req, $res) {
    $data = json_decode(file_get_contents('php://input'), true);

    if (!$data) {
        $res->status(400)->json(['error' => 'Invalid JSON data']);
        return;
    }

    $newUser = [
        'id' => rand(100, 999),
        'name' => $data['name'] ?? '未知',
        'email' => $data['email'] ?? '',
        'created_at' => date('Y-m-d H:i:s')
    ];

    $res->status(201)->json($newUser);
});

// 协程隔离演示
$server->get('/isolation', function($req, $res) {
    $res->json([
        'fiber_id' => rand(1, 1000),
        'timestamp' => microtime(true),
        'isolation_demo' => '每个协程的变量都是隔离的',
        'process_id' => getmypid(),
        'memory_usage' => memory_get_usage(true)
    ]);
});

// 服务器状态信息
$server->get('/status', function($req, $res) {
    $res->json([
        'status' => 'running',
        'server' => 'SimpleHttpServer',
        'version' => '1.0.0',
        'uptime' => time(),
        'routes' => ['/counter', '/api/users', '/isolation', '/status']
    ]);
});

// ==================== 请求处理 ====================

$method = $_SERVER['REQUEST_METHOD'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// 简化的请求/响应对象
$req = (object)[
    'method' => $method,
    'path' => $path,
    'query' => $_GET,
    'headers' => getallheaders()
];

$res = new HttpResponse();

try {
    // 路由分发
    $handled = false;

    if (isset($server->routes[$method][$path])) {
        $handler = $server->routes[$method][$path];
        call_user_func($handler, $req, $res);
        $handled = true;
    }

    // 处理根路径
    if (!$handled && $path === '/') {
        $res->html('
        <!DOCTYPE html>
        <html>
        <head>
            <title>Zig-PHP HTTP服务器演示</title>
            <meta charset="utf-8">
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                .demo { background: #f5f5f5; padding: 20px; margin: 20px 0; border-radius: 5px; }
                .code { background: #2d3748; color: #e2e8f0; padding: 10px; border-radius: 3px; font-family: monospace; }
                button { background: #3182ce; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; margin: 5px; }
                button:hover { background: #2c5282; }
            </style>
        </head>
        <body>
            <h1>🚀 Zig-PHP HTTP服务器演示</h1>

            <div class="demo">
                <h2>协程隔离计数器测试</h2>
                <button onclick="testCounter()">测试计数器</button>
                <button onclick="testCounterConcurrent()">并发测试</button>
                <div id="counter-result"></div>
            </div>

            <div class="demo">
                <h2>用户API测试</h2>
                <button onclick="testUsersAPI()">获取用户列表</button>
                <button onclick="testCreateUser()">创建新用户</button>
                <div id="users-result"></div>
            </div>

            <div class="demo">
                <h2>协程隔离测试</h2>
                <button onclick="testIsolation()">测试协程隔离</button>
                <div id="isolation-result"></div>
            </div>

            <div class="demo">
                <h2>服务器状态</h2>
                <button onclick="testStatus()">查看状态</button>
                <div id="status-result"></div>
            </div>

            <script>
                async function testCounter() {
                    const result = document.getElementById("counter-result");
                    result.innerHTML = "请求中...";
                    try {
                        const response = await fetch("/counter");
                        const data = await response.json();
                        result.innerHTML = `<pre>${JSON.stringify(data, null, 2)}</pre>`;
                    } catch (e) {
                        result.innerHTML = `错误: ${e.message}`;
                    }
                }

                async function testCounterConcurrent() {
                    const result = document.getElementById("counter-result");
                    result.innerHTML = "并发请求中...";

                    const promises = [];
                    for (let i = 0; i < 5; i++) {
                        promises.push(fetch("/counter").then(r => r.json()));
                    }

                    try {
                        const results = await Promise.all(promises);
                        result.innerHTML = "<h3>5个并发请求结果:</h3>" +
                            results.map((data, i) => `<div>请求${i+1}: counter=${data.counter}</div>`).join("");
                    } catch (e) {
                        result.innerHTML = `错误: ${e.message}`;
                    }
                }

                async function testUsersAPI() {
                    const result = document.getElementById("users-result");
                    result.innerHTML = "请求中...";
                    try {
                        const response = await fetch("/api/users");
                        const data = await response.json();
                        result.innerHTML = `<pre>${JSON.stringify(data, null, 2)}</pre>`;
                    } catch (e) {
                        result.innerHTML = `错误: ${e.message}`;
                    }
                }

                async function testCreateUser() {
                    const result = document.getElementById("users-result");
                    result.innerHTML = "创建用户中...";
                    try {
                        const response = await fetch("/api/users", {
                            method: "POST",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({
                                name: "王五",
                                email: "wangwu@example.com"
                            })
                        });
                        const data = await response.json();
                        result.innerHTML = `<pre>创建成功: ${JSON.stringify(data, null, 2)}</pre>`;
                    } catch (e) {
                        result.innerHTML = `错误: ${e.message}`;
                    }
                }

                async function testIsolation() {
                    const result = document.getElementById("isolation-result");
                    result.innerHTML = "测试中...";
                    try {
                        const response = await fetch("/isolation");
                        const data = await response.json();
                        result.innerHTML = `<pre>${JSON.stringify(data, null, 2)}</pre>`;
                    } catch (e) {
                        result.innerHTML = `错误: ${e.message}`;
                    }
                }

                async function testStatus() {
                    const result = document.getElementById("status-result");
                    result.innerHTML = "获取状态中...";
                    try {
                        const response = await fetch("/status");
                        const data = await response.json();
                        result.innerHTML = `<pre>${JSON.stringify(data, null, 2)}</pre>`;
                    } catch (e) {
                        result.innerHTML = `错误: ${e.message}`;
                    }
                }
            </script>
        </body>
        </html>');
    }

    // 404处理
    if (!$handled && $path !== '/') {
        $res->status(404)->json([
            'error' => 'Not Found',
            'path' => $path,
            'method' => $method,
            'available_routes' => array_keys($server->routes[$method] ?? [])
        ]);
    }

} catch (Exception $e) {
    $res->status(500)->json([
        'error' => 'Internal Server Error',
        'message' => $e->getMessage()
    ]);
}
?>
