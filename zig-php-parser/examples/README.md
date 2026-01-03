# Zig-PHP HTTP 服务器示例

这个目录包含了完整的HTTP服务器使用示例，展示了协程安全、路由、中间件等核心特性。

## 示例文件

### http_server_demo.zig

完整的HTTP服务器演示程序，展示以下特性：

- **协程安全**：每个请求独立的上下文，不会相互污染
- **路由系统**：支持GET/POST等HTTP方法和路径参数
- **中间件支持**：请求处理链，支持日志记录等
- **并发处理**：协程隔离演示
- **RESTful API**：完整的CRUD操作示例

### http_server_demo.php

PHP版本的完整HTTP服务器演示，展示相同的特性：

- **协程安全**：每个请求独立的上下文，不会相互污染
- **路由系统**：支持GET/POST等HTTP方法和路径参数
- **中间件支持**：请求处理链，支持日志记录等
- **并发处理**：协程隔离演示
- **RESTful API**：完整的CRUD操作示例
- **性能优化**：对象池、零拷贝、协程调度

## 运行示例

### 1. 编译和运行 Zig 示例

```bash
# 编译示例
zig build -Dexample=http_server_demo

# 或者直接运行
zig run examples/http_server_demo.zig
```

### 2. 运行 PHP 示例

```bash
# 使用PHP解释器运行（需要Zig-PHP运行时）
php examples/http_server_demo.php
```

## 测试服务器

### 基础功能测试

```bash
# 协程安全计数器演示
curl http://127.0.0.1:8080/counter

# 获取用户列表
curl http://127.0.0.1:8080/api/users

# 创建新用户
curl -X POST http://127.0.0.1:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"张三","email":"zhangsan@example.com"}'

# 获取单个用户
curl http://127.0.0.1:8080/api/users/1

# 更新用户
curl -X PUT http://127.0.0.1:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"李四","email":"lisi@example.com"}'

# 删除用户
curl -X DELETE http://127.0.0.1:8080/api/users/1
```

### 并发测试

测试协程隔离特性：

```bash
# 同时发送多个请求，观察计数器是否独立
for i in {1..5}; do
    curl http://127.0.0.1:8080/counter &
done
```

## 核心特性说明

### 1. 协程安全上下文

每个HTTP请求都在独立的协程中处理，变量和状态完全隔离：

```php
// PHP版本
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
```

```zig
// Zig版本
fn counterHandler(vm: *vm_mod.VM, args: []const types.Value) anyerror!types.Value {
    // 这里的状态对其他请求不可见
    var counter = getRequestLocalCounter();
    counter += 1;
    // ...
}
```

### 2. 路由系统

支持灵活的路由匹配：

```php
$router->get('/users/:id', function($req, $res) {
    $id = $req->param('id');
    $res->json(['user_id' => $id]);
});
```

### 3. 中间件链

请求处理中间件，支持日志、认证等：

```php
$router->use(function($req, $res, $next) {
    $start = microtime(true);
    echo "[{$req->method()}] {$req->path()}\n";

    // 调用下一个中间件或处理器
    $next();

    $duration = (microtime(true) - $start) * 1000;
    echo "完成 - {$duration}ms\n";
});
```

### 4. 性能优化

- **对象池**：复用请求上下文，减少GC压力
- **协程调度**：高效的协程切换
- **零拷贝**：优化内存使用

## PHP API 说明

### HttpServer 类

```php
$server = new HttpServer([
    'host' => '127.0.0.1',
    'port' => 8080,
    'enable_coroutines' => true,
    'max_connections' => 1024,
    'context_pool_size' => 100,
]);
```

### Router 类

```php
$router = new Router();

// 路由注册
$router->get('/path', $handler);
$router->post('/path', $handler);
$router->put('/path', $handler);
$router->delete('/path', $handler);

// 中间件
$router->use($middleware);
```

### Request 对象

```php
// 请求信息
$method = $req->method();
$path = $req->path();
$body = $req->body();
$data = $req->json();

// 路由参数
$id = $req->param('id');

// 查询参数
$page = $req->query('page');

// 请求头
$contentType = $req->header('Content-Type');
```

### Response 对象

```php
// 设置状态
$res->status(200);

// 设置头
$res->header('Content-Type', 'application/json');

// 发送响应
$res->json(['data' => 'value']);
$res->html('<h1>Hello</h1>');
$res->text('Hello World');

// 链式调用
$res->status(201)->json(['created' => true]);
```

## 架构优势

- ✅ **内存安全**：Zig的编译时内存安全保证
- ✅ **协程隔离**：每个请求独立上下文，无状态污染
- ✅ **高性能**：协程调度 + 对象池优化
- ✅ **易扩展**：模块化设计，易于添加新功能
- ✅ **跨语言**：支持PHP和Zig两种开发方式

## 更多示例

查看 `examples/` 目录中的其他文件，了解更多PHP特性的使用方法。

## AOT 编译示例

详细的 AOT 编译文档请参阅 [AOT_EXAMPLES.md](AOT_EXAMPLES.md)。

以下示例专门用于演示 AOT (Ahead-of-Time) 编译功能：

| 文件 | 说明 | 演示特性 |
|------|------|----------|
| `aot_hello.php` | Hello World | 基本输出、变量、字符串 |
| `aot_functions.php` | 函数示例 | 函数定义、递归、默认参数 |
| `aot_arrays.php` | 数组操作 | 索引数组、关联数组、foreach |
| `aot_strings.php` | 字符串操作 | 连接、插值、内置函数 |
| `aot_classes.php` | 面向对象 | 类、继承、方法 |
| `aot_control_flow.php` | 控制流 | if/else、循环、break/continue |

### 快速开始

```bash
# 编译 Hello World 示例
./zig-out/bin/php-interpreter --compile examples/aot_hello.php

# 运行编译后的二进制
./aot_hello
```

### 编译选项

| 选项 | 说明 |
|------|------|
| `--compile` | 启用 AOT 编译模式 |
| `--output=<file>` | 指定输出文件名 |
| `--optimize=debug` | 调试模式（默认） |
| `--optimize=release-safe` | 安全优化模式 |
| `--optimize=release-fast` | 最快执行速度 |
| `--optimize=release-small` | 最小二进制体积 |
| `--static` | 生成完全静态链接的可执行文件 |
| `--target=<triple>` | 交叉编译到指定平台 |
| `--dump-ir` | 输出生成的 IR |
| `--dump-ast` | 输出解析的 AST |
| `--dump-zig` | 输出生成的 Zig 代码 |
| `--verbose` | 详细输出编译过程 |

### 编译示例

```bash
# 基本编译
./zig-out/bin/php-interpreter --compile examples/aot_hello.php

# 优化编译
./zig-out/bin/php-interpreter --compile --optimize=release-fast examples/aot_functions.php

# 静态链接
./zig-out/bin/php-interpreter --compile --static examples/aot_hello.php

# 交叉编译到 Linux
./zig-out/bin/php-interpreter --compile --target=x86_64-linux-gnu examples/aot_hello.php
```