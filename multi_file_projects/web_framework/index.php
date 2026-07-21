<?php
// Web 框架入口文件 - 多文件 AOT 测试
// 所有 require_once 路径相对于入口文件所在目录（AOT 依赖解析器 base_dir 规则）

echo "============================================\n";
echo "Web Framework Multi-File AOT Test\n";
echo "============================================\n\n";

// === 加载核心文件 ===
require_once 'core/Request.php';
require_once 'core/Response.php';
require_once 'core/Router.php';
require_once 'core/Container.php';
require_once 'core/Controller.php';
require_once 'core/Middleware.php';
require_once 'core/Validator.php';
require_once 'core/Template.php';
require_once 'core/Database.php';
require_once 'core/ORM.php';
require_once 'core/Logger.php';
require_once 'core/Session.php';
require_once 'core/ExceptionHandler.php';

// === 加载应用文件 ===
require_once 'app/UserModel.php';
require_once 'app/PostModel.php';
require_once 'app/Controllers.php';

// === 初始化容器 ===
$container = Container::getInstance();
$container->singleton('template', function($c) {
    return new TemplateEngine();
});
$container->singleton('logger', function($c) {
    return new Logger();
});
$container->instance('db', Database::getInstance());

// === 注册路由 ===
$router = new Router();

// 首页路由
$router->get('/', [HomeController::class, 'index']);
$router->get('/health', [HomeController::class, 'health']);
$router->get('/home', [HomeController::class, 'renderHome']);

// 用户路由（RESTful + 自定义）
$router->get('/users', [UserController::class, 'index']);
$router->post('/users', [UserController::class, 'create']);
$router->get('/users/{id}', [UserController::class, 'show']);
$router->put('/users/{id}', [UserController::class, 'update']);
$router->delete('/users/{id}', [UserController::class, 'destroy']);
$router->post('/login', [UserController::class, 'login']);

// 认证保护路由组
$router->group(['prefix' => '/api', 'middleware' => [AuthMiddleware::class]], function($r) {
    $r->get('/profile', [UserController::class, 'profile']);
    $r->post('/posts', [PostController::class, 'store']);
    $r->post('/posts/{id}/comments', [PostController::class, 'addComment']);
});

// 文章路由
$router->get('/posts', [PostController::class, 'index']);
$router->get('/posts/{id}', [PostController::class, 'show']);

// CORS + 日志全局中间件
$globalMiddleware = [CorsMiddleware::class, LogMiddleware::class, RateLimitMiddleware::class];

// === HTTP 请求模拟器 ===
class HttpSimulator {
    private Router $router;
    private array $globalMiddleware;
    private ExceptionHandler $exceptionHandler;
    private Logger $logger;

    public function __construct(Router $router, array $globalMiddleware) {
        $this->router = $router;
        $this->globalMiddleware = $globalMiddleware;
        $this->exceptionHandler = new ExceptionHandler();
        $this->logger = new Logger();
    }

    public function dispatch(string $method, string $path, array $query = [], array $body = [], array $headers = []): Response {
        $request = new Request($method, $path, $query, $body, $headers);
        echo "→ {$method} {$path}\n";

        try {
            $matched = $this->router->match($request);
            if ($matched === null) {
                throw new NotFoundException("No route found for {$method} {$path}");
            }

            $route = $matched['route'];
            $request->params = array_merge($request->params, $matched['params']);

            // 构建中间件管道
            $pipeline = new MiddlewarePipeline();
            foreach ($this->globalMiddleware as $mw) {
                $pipeline->add($mw);
            }
            foreach ($route->middleware as $mw) {
                $pipeline->add($mw);
            }

            // 核心处理函数
            $coreHandler = function(Request $req) use ($route) {
                $handler = $route->handler;
                if (is_array($handler)) {
                    $controllerClass = $handler[0];
                    $method = $handler[1];
                    $controller = new $controllerClass();
                    return $controller->$method($req);
                }
                return $handler($req);
            };

            $response = $pipeline->handle($request, $coreHandler);

        } catch (Throwable $e) {
            $this->exceptionHandler->report($e);
            $response = $this->exceptionHandler->render($e);
        }

        echo "← {$response->status} {$response->getStatusText()}\n";
        return $response;
    }
}

// === 测试套件 ===
$simulator = new HttpSimulator($router, $globalMiddleware);

echo "\n--- Test 1: Home Page ---\n";
$resp = $simulator->dispatch('GET', '/');
echo $resp->body . "\n\n";

echo "--- Test 2: Health Check ---\n";
$resp = $simulator->dispatch('GET', '/health');
echo $resp->body . "\n\n";

echo "--- Test 3: Create User ---\n";
$resp = $simulator->dispatch('POST', '/users', [], [
    'name' => 'Alice',
    'email' => 'alice@example.com',
    'password' => 'secret123',
    'role' => 'admin',
]);
echo $resp->body . "\n\n";

echo "--- Test 4: Create Second User ---\n";
$resp = $simulator->dispatch('POST', '/users', [], [
    'name' => 'Bob',
    'email' => 'bob@example.com',
    'password' => 'password456',
    'role' => 'user',
]);
echo $resp->body . "\n\n";

echo "--- Test 5: Login ---\n";
$resp = $simulator->dispatch('POST', '/login', [], [
    'email' => 'alice@example.com',
    'password' => 'secret123',
]);
echo $resp->body . "\n\n";
// 提取 token
$loginData = json_decode($resp->body, true);
$token = $loginData['token'] ?? '';

echo "--- Test 6: List Users ---\n";
$resp = $simulator->dispatch('GET', '/users');
echo $resp->body . "\n\n";

echo "--- Test 7: Get User by ID ---\n";
$resp = $simulator->dispatch('GET', '/users/1');
echo $resp->body . "\n\n";

echo "--- Test 8: Get Non-existent User ---\n";
$resp = $simulator->dispatch('GET', '/users/999');
echo $resp->body . "\n\n";

echo "--- Test 9: Validation Error (missing email) ---\n";
$resp = $simulator->dispatch('POST', '/users', [], [
    'name' => 'Charlie',
    'password' => 'short',
]);
echo $resp->body . "\n\n";

echo "--- Test 10: Duplicate Email ---\n";
$resp = $simulator->dispatch('POST', '/users', [], [
    'name' => 'Alice 2',
    'email' => 'alice@example.com',
    'password' => 'password789',
]);
echo $resp->body . "\n\n";

echo "--- Test 11: Create Post (Auth) ---\n";
$resp = $simulator->dispatch('POST', '/api/posts', [], [
    'title' => 'Hello World',
    'content' => 'This is my first post. It contains enough content to be meaningful.',
], ['authorization' => $token]);
echo $resp->body . "\n\n";

echo "--- Test 12: Create Post Without Auth (should 401) ---\n";
$resp = $simulator->dispatch('POST', '/api/posts', [], [
    'title' => 'Unauthorized Post',
    'content' => 'This should fail.',
]);
echo $resp->body . "\n\n";

echo "--- Test 13: List Posts ---\n";
$resp = $simulator->dispatch('GET', '/posts');
echo $resp->body . "\n\n";

echo "--- Test 14: Show Post ---\n";
$resp = $simulator->dispatch('GET', '/posts/1');
echo $resp->body . "\n\n";

echo "--- Test 15: Add Comment (Auth) ---\n";
$resp = $simulator->dispatch('POST', '/api/posts/1/comments', [], [
    'content' => 'Great post!',
], ['authorization' => $token]);
echo $resp->body . "\n\n";

echo "--- Test 16: Update User ---\n";
$resp = $simulator->dispatch('PUT', '/users/2', [], [
    'name' => 'Bob Updated',
    'status' => 'inactive',
]);
echo $resp->body . "\n\n";

echo "--- Test 17: Delete User ---\n";
$resp = $simulator->dispatch('DELETE', '/users/2');
echo $resp->body . "\n\n";

echo "--- Test 18: 404 Route ---\n";
$resp = $simulator->dispatch('GET', '/nonexistent');
echo $resp->body . "\n\n";

echo "--- Test 19: Template Rendering ---\n";
$resp = $simulator->dispatch('GET', '/home');
echo $resp->body . "\n\n";

echo "--- Test 20: Profile (Auth) ---\n";
$resp = $simulator->dispatch('GET', '/api/profile', [], [], ['authorization' => $token]);
echo $resp->body . "\n\n";

// === 数据库查询日志 ===
echo "=== Database Query Log ===\n";
foreach (Database::getInstance()->getQueryLog() as $query) {
    echo "  $query\n";
}

// === 日志统计 ===
echo "\n=== Logger Stats ===\n";
$logger = Container::getInstance()->make('logger');
echo "  Total log entries: " . $logger->count() . "\n";

echo "\n============================================\n";
echo "Web Framework Test Complete\n";
echo "============================================\n";
