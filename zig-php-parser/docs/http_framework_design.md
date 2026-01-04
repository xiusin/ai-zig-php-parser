# 高性能协程安全 HTTP 框架设计文档

## 📋 设计目标

1. **协程安全**：每个请求独立的上下文，避免变量污染
2. **高性能**：参考 Bun 设计，使用对象池、零拷贝等优化
3. **内存安全**：严格的生命周期管理，无内存泄漏
4. **易用性**：简洁的 PHP API，类似 Express/Koa 风格

## 🏗️ 架构设计

### 核心组件

```
┌─────────────────────────────────────────┐
│           PHP Application               │
│  (用户代码，使用 Request/Response 对象)  │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         HTTP Framework Layer            │
│  • Router (路由匹配)                     │
│  • Middleware (中间件链)                 │
│  • Request/Response (PHP 对象)          │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│      Coroutine Context Manager          │
│  • RequestContext (请求上下文池)         │
│  • Context Isolation (上下文隔离)        │
│  • Lifecycle Management (生命周期)       │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         HTTP Server/Client Core         │
│  • HttpServer (TCP 监听/连接处理)        │
│  • HttpClient (HTTP 客户端)              │
│  • Protocol Parser (HTTP 协议解析)       │
└─────────────────────────────────────────┘
```

### 请求处理流程

```
1. TCP 连接到达
   ↓
2. 从上下文池获取 RequestContext
   ↓
3. 解析 HTTP 请求 → HttpRequest
   ↓
4. 创建 HttpResponse
   ↓
5. 绑定到 RequestContext (隔离)
   ↓
6. 在协程中执行处理器
   ↓
7. 发送响应
   ↓
8. 释放 RequestContext 回池
```

## 🔒 协程安全机制

### 1. 请求上下文隔离

每个请求拥有独立的 `RequestContext`：

```zig
pub const RequestContext = struct {
    id: u64,                          // 唯一 ID
    request: ?*const HttpRequest,     // 请求对象（只读）
    response: ?*HttpResponse,         // 响应对象（可写）
    locals: StringHashMap(Value),     // 请求局部变量
    coroutine_id: ?u64,               // 关联的协程 ID
    allocator: Allocator,             // 独立的内存分配器
    parent_vm: *anyopaque,            // 父 VM 引用
};
```

### 2. 对象池管理

使用对象池避免频繁分配：

```zig
request_context_pool: ArrayList(*RequestContext)

fn acquireContext() -> *RequestContext {
    // 从池中获取或新建
}

fn releaseContext(ctx: *RequestContext) {
    // 清理并归还到池
}
```

### 3. 内存安全保证

- **引用计数**：Request/Response 对象使用引用计数
- **生命周期绑定**：上下文与请求生命周期严格绑定
- **自动清理**：defer 确保资源释放

## 📦 PHP API 设计

### HTTP Server

```php
<?php

// 创建服务器
$server = new HttpServer([
    'host' => '127.0.0.1',
    'port' => 8080,
    'enable_coroutines' => true,
]);

// 设置处理器（每个请求在独立协程中执行）
$server->handle(function($req, $res) {
    // $req 和 $res 是请求独立的对象
    // 协程间不会相互污染
    $res->json(['message' => 'Hello']);
});

$server->listen();
```

### Router

```php
<?php

$router = new Router();

// GET 路由
$router->get('/users/:id', function($req, $res) {
    $id = $req->param('id');
    $res->json(['user_id' => $id]);
});

// POST 路由
$router->post('/users', function($req, $res) {
    $body = $req->body();
    $res->json(['created' => true]);
});

// 中间件
$router->use(function($req, $res, $next) {
    echo "Request: {$req->method()} {$req->path()}\n";
    $next();
});

$server->use($router);
```

### Request 对象

```php
<?php

class Request {
    // 获取请求方法
    public function method(): string;
    
    // 获取请求路径
    public function path(): string;
    
    // 获取请求体
    public function body(): string;
    
    // 获取请求头
    public function header(string $name): ?string;
    
    // 获取查询参数
    public function query(string $name): ?string;
    
    // 获取路由参数
    public function param(string $name): ?string;
    
    // 获取所有请求头
    public function headers(): array;
    
    // 解析 JSON 请求体
    public function json(): array;
}
```

### Response 对象

```php
<?php

class Response {
    // 设置状态码
    public function status(int $code): self;
    
    // 设置响应头
    public function header(string $name, string $value): self;
    
    // 发送文本响应
    public function text(string $content): void;
    
    // 发送 JSON 响应
    public function json(array $data): void;
    
    // 发送 HTML 响应
    public function html(string $content): void;
    
    // 发送重定向
    public function redirect(string $url, int $code = 302): void;
}
```

### HTTP Client

```php
<?php

$client = new HttpClient([
    'timeout' => 30000,
    'follow_redirects' => true,
]);

// GET 请求
$response = $client->get('http://api.example.com/users');
echo $response->body();

// POST 请求
$response = $client->post('http://api.example.com/users', [
    'name' => '张三',
    'age' => 25,
]);

// 并发请求（在协程中）
go(function() use ($client) {
    $res1 = $client->get('http://api1.example.com');
    echo "API1: {$res1->body()}\n";
});

go(function() use ($client) {
    $res2 = $client->get('http://api2.example.com');
    echo "API2: {$res2->body()}\n";
});
```

## 🚀 性能优化

### 1. 对象池

- RequestContext 池（预分配 100 个）
- Buffer 池（减少内存分配）
- 连接池（HTTP 客户端）

### 2. 零拷贝

- 请求体直接引用原始 buffer
- 避免不必要的字符串复制

### 3. 协程调度

- 每个请求在独立协程中处理
- 非阻塞 I/O
- 高效的协程切换

## 🔐 安全性

### 1. 内存安全

- 严格的生命周期管理
- 引用计数防止悬垂指针
- 边界检查

### 2. 协程安全

- 上下文隔离
- 无共享状态
- 线程安全的计数器

### 3. 输入验证

- HTTP 协议验证
- 请求大小限制
- 超时保护

## 📊 实现状态

### ✅ 已完成

- [x] HttpServer 基础框架
- [x] HttpRequest 解析
- [x] HttpResponse 构建
- [x] RequestContext 上下文管理
- [x] Router 路由匹配
- [x] HttpClient 基础实现

### 🚧 待完成

- [ ] PHP 内置类注册（Request/Response/Router）
- [ ] VM 中的回调调用机制
- [ ] 协程上下文绑定
- [ ] 中间件链执行
- [ ] 完整的错误处理
- [ ] 性能测试和优化

## 📝 使用示例

完整的服务器示例：

```php
<?php

$server = new HttpServer(['port' => 8080]);
$router = new Router();

// 日志中间件
$router->use(function($req, $res, $next) {
    $start = microtime(true);
    $next();
    $duration = microtime(true) - $start;
    echo "[{$req->method()}] {$req->path()} - {$duration}ms\n";
});

// API 路由
$router->get('/api/users/:id', function($req, $res) {
    $id = $req->param('id');
    $res->json([
        'id' => $id,
        'name' => '用户' . $id,
    ]);
});

$router->post('/api/users', function($req, $res) {
    $data = $req->json();
    // 保存用户...
    $res->status(201)->json([
        'success' => true,
        'data' => $data,
    ]);
});

$server->use($router);
$server->listen();
```

## 🎯 下一步计划

1. 完成 PHP 类的 VM 注册
2. 实现协程上下文绑定
3. 添加完整的测试用例
4. 性能基准测试
5. 文档完善
