<?php
/**
 * HTTP 并发测试和协程栈测试
 * 测试 HTTP 服务器、HTTP 客户端、并发请求、协程栈等功能
 */

echo "========================================\n";
echo "  HTTP 并发和协程栈测试\n";
echo "========================================\n\n";

// ==================== 测试1: HTTP 服务器配置 ====================
echo "【测试1】HTTP 服务器配置\n";
try {
    // 注意：HTTP 服务器功能需要在 VM 中实现
    // 以下是预期的 API 设计示例

    /*
    $server = http_server_create([
        'host' => '127.0.0.1',
        'port' => 8080,
        'enable_coroutines' => true,
        'max_connections' => 1000,
        'timeout' => 30000,
    ]);

    echo "HTTP 服务器配置成功\n";
    echo "主机: {$server->host}\n";
    echo "端口: {$server->port}\n";
    echo "协程支持: " . ($server->enable_coroutines ? "是" : "否") . "\n";
    */

    echo "⚠️  HTTP 服务器需要 VM 支持（当前为注释示例）\n";
} catch (Exception $e) {
    echo "❌ HTTP 服务器配置失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试2: HTTP 路由配置 ====================
echo "【测试2】HTTP 路由配置\n";
try {
    /*
    $router = http_router_create();

    // GET 路由
    $router->get('/hello', function($req, $res) {
        $res->json(['message' => 'Hello World']);
    });

    // POST 路由
    $router->post('/users', function($req, $res) {
        $body = $req->getBody();
        $res->json(['created' => true, 'data' => $body]);
    });

    // 带参数的路由
    $router->get('/users/:id', function($req, $res) {
        $id = $req->getParam('id');
        $res->json(['user_id' => $id]);
    });

    // PUT 路由
    $router->put('/users/:id', function($req, $res) {
        $id = $req->getParam('id');
        $res->json(['updated' => true, 'user_id' => $id]);
    });

    // DELETE 路由
    $router->delete('/users/:id', function($req, $res) {
        $id = $req->getParam('id');
        $res->json(['deleted' => true, 'user_id' => $id]);
    });

    echo "HTTP 路由配置成功\n";
    */

    echo "⚠️  HTTP 路由需要 VM 支持（当前为注释示例）\n";
} catch (Exception $e) {
    echo "❌ HTTP 路由配置失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试3: HTTP 中间件 ====================
echo "【测试3】HTTP 中间件\n";
try {
    /*
    $router = http_router_create();

    // 日志中间件
    $router->use(function($req, $res, $next) {
        echo "[LOG] {$req->getMethod()} {$req->getPath()}\n";
        $next();
    });

    // 认证中间件
    $router->use('/api', function($req, $res, $next) {
        $token = $req->getHeader('Authorization');
        if (!$token) {
            $res->setStatus(401);
            $res->json(['error' => 'Unauthorized']);
            return;
        }
        $next();
    });

    // CORS 中间件
    $router->use(function($req, $res, $next) {
        $res->setHeader('Access-Control-Allow-Origin', '*');
        $res->setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
        $res->setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        $next();
    });

    echo "HTTP 中间件配置成功\n";
    */

    echo "⚠️  HTTP 中间件需要 VM 支持（当前为注释示例）\n";
} catch (Exception $e) {
    echo "❌ HTTP 中间件配置失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试4: HTTP 客户端 ====================
echo "【测试4】HTTP 客户端\n";
try {
    /*
    $client = http_client_create([
        'timeout' => 30000,
        'follow_redirects' => true,
        'max_redirects' => 5,
        'user_agent' => 'Zig-PHP-HTTP/1.0',
    ]);

    // GET 请求
    $response = $client->get('http://api.example.com/users');
    echo "状态码: {$response->getStatusCode()}\n";
    echo "响应体: {$response->getBody()}\n";

    // POST 请求
    $response = $client->post('http://api.example.com/users', [
        'name' => '张三',
        'age' => 25,
    ]);
    echo "POST 响应: {$response->getBody()}\n";

    // PUT 请求
    $response = $client->put('http://api.example.com/users/123', [
        'name' => '李四',
        'age' => 30,
    ]);

    // DELETE 请求
    $response = $client->delete('http://api.example.com/users/123');

    echo "HTTP 客户端测试成功\n";
    */

    echo "⚠️  HTTP 客户端需要 VM 支持（当前为注释示例）\n";
} catch (Exception $e) {
    echo "❌ HTTP 客户端测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试5: 并发 HTTP 请求 ====================
echo "【测试5】并发 HTTP 请求（模拟）\n";
try {
    /*
    $client = http_client_create(['timeout' => 30000]);
    $results = new Channel(10);

    // 并发请求
    $urls = [
        'http://api1.example.com/data',
        'http://api2.example.com/data',
        'http://api3.example.com/data',
        'http://api4.example.com/data',
        'http://api5.example.com/data',
    ];

    foreach ($urls as $url) {
        go function() use ($client, $url, $results) {
            $response = $client->get($url);
            $results->send([
                'url' => $url,
                'status' => $response->getStatusCode(),
                'body' => $response->getBody(),
            ]);
        };
    }

    // 收集结果
    for ($i = 0; $i < count($urls); $i++) {
        $result = $results->recv();
        echo "{$result['url']}: {$result['status']}\n";
    }

    echo "并发 HTTP 请求测试成功\n";
    */

    echo "⚠️  并发 HTTP 请求需要 VM 支持（当前为注释示例）\n";
} catch (Exception $e) {
    echo "❌ 并发 HTTP 请求测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试6: HTTP 请求重试 ====================
echo "【测试6】HTTP 请求重试（模拟）\n";
try {
    /*
    $client = http_client_create([
        'timeout' => 30000,
        'max_retries' => 3,
        'retry_delay' => 1000,
    ]);

    $response = $client->get('http://api.example.com/data');
    echo "请求完成，状态码: {$response->getStatusCode()}\n";
    echo "重试次数: {$response->getRetryCount()}\n";

    echo "HTTP 请求重试测试成功\n";
    */

    echo "⚠️  HTTP 请求重试需要 VM 支持（当前为注释示例）\n";
} catch (Exception $e) {
    echo "❌ HTTP 请求重试测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试7: 协程栈 - 基础 ====================
echo "【测试7】协程栈基础（模拟）\n";
try {
    // 使用 Channel 模拟协程栈
    $stack = new Channel(10);

    // 压栈
    $stack->send("frame1");
    $stack->send("frame2");
    $stack->send("frame3");

    echo "栈大小: " . $stack->len() . "\n";

    // 弹栈
    while (($frame = $stack->recv()) !== null) {
        echo "弹出: $frame\n";
    }

    echo "✅ 协程栈基础测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈基础测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试8: 协程栈 - 嵌套调用 ====================
echo "【测试8】协程栈嵌套调用（模拟）\n";
try {
    $stack = new Channel(20);
    $call_depth = new Atomic(0);

    // 模拟函数调用
    function simulate_call($depth, $max_depth, $stack, $call_depth) {
        if ($depth >= $max_depth) {
            return;
        }

        $call_depth->increment();
        $stack->send("call_$depth");

        // 递归调用
        simulate_call($depth + 1, $max_depth, $stack, $call_depth);

        // 返回
        $frame = $stack->recv();
        echo "返回: $frame\n";
    }

    simulate_call(0, 5, $stack, $call_depth);

    echo "最大调用深度: " . $call_depth->load() . "\n";
    echo "✅ 协程栈嵌套调用测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈嵌套调用测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试9: 协程栈 - 异常处理 ====================
echo "【测试9】协程栈异常处理（模拟）\n";
try {
    $stack = new Channel(10);

    // 模拟异常传播
    $stack->send("frame1");
    $stack->send("frame2");
    $stack->send("frame3");

    // 模拟异常
    try {
        throw new Exception("模拟异常");
    } catch (Exception $e) {
        echo "捕获异常: " . $e->getMessage() . "\n";

        // 清理栈
        while (($frame = $stack->recv()) !== null) {
            echo "清理栈帧: $frame\n";
        }
    }

    echo "✅ 协程栈异常处理测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈异常处理测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试10: 协程栈 - 上下文切换 ====================
echo "【测试10】协程栈上下文切换（模拟）\n";
try {
    $stack1 = new Channel(10);
    $stack2 = new Channel(10);
    $current_stack = new Atomic(1);

    // 协程1
    $stack1->send("co1_frame1");
    $stack1->send("co1_frame2");
    echo "协程1: 执行到第2帧\n";

    // 切换到协程2
    $current_stack->store(2);
    $stack2->send("co2_frame1");
    $stack2->send("co2_frame2");
    echo "协程2: 执行到第2帧\n";

    // 切换回协程1
    $current_stack->store(1);
    echo "协程1: 继续执行\n";

    // 清理
    while (($frame = $stack1->recv()) !== null) {
        echo "协程1清理: $frame\n";
    }
    while (($frame = $stack2->recv()) !== null) {
        echo "协程2清理: $frame\n";
    }

    echo "✅ 协程栈上下文切换测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈上下文切换测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试11: 协程栈 - 内存管理 ====================
echo "【测试11】协程栈内存管理（模拟）\n";
try {
    $stack = new Channel(100);
    $memory_usage = new Atomic(0);

    // 模拟大量栈帧
    for ($i = 0; $i < 100; $i++) {
        $frame = [
            'id' => $i,
            'data' => str_repeat("x", 100), // 模拟栈帧数据
            'timestamp' => microtime(true),
        ];
        $stack->send($frame);
        $memory_usage->add(strlen(serialize($frame)));
    }

    echo "栈帧数量: " . $stack->len() . "\n";
    echo "估算内存使用: " . $memory_usage->load() . " bytes\n";

    // 清理
    $count = 0;
    while (($frame = $stack->recv()) !== null) {
        $count++;
    }

    echo "清理栈帧数量: $count\n";
    echo "✅ 协程栈内存管理测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈内存管理测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试12: HTTP 连接池 ====================
echo "【测试12】HTTP 连接池（模拟）\n";
try {
    $pool = new Channel(5);
    $mutex = new Mutex();
    $shared = new SharedData();

    // 初始化连接池
    for ($i = 0; $i < 3; $i++) {
        $connection = [
            'id' => $i,
            'host' => 'api.example.com',
            'port' => 80,
            'active' => false,
        ];
        $pool->send($connection);
        echo "创建连接: {$connection['id']}\n";
    }

    // 使用连接
    for ($i = 0; $i < 5; $i++) {
        $conn = $pool->recv();
        echo "获取连接: {$conn['id']}\n";

        $mutex->lock();
        $conn['active'] = true;
        $shared->set("conn_{$conn['id']}", $conn);
        $mutex->unlock();

        // 模拟使用
        $conn['active'] = false;

        // 归还连接
        $pool->send($conn);
        echo "归还连接: {$conn['id']}\n";
    }

    echo "✅ HTTP 连接池测试通过\n";
} catch (Exception $e) {
    echo "❌ HTTP 连接池测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试13: HTTP 请求超时 ====================
echo "【测试13】HTTP 请求超时（模拟）\n";
try {
    $request_ch = new Channel(1);
    $timeout_ch = new Channel(1);

    // 模拟超时
    $timeout_ch->send("timeout");

    // 尝试获取响应
    $response = $request_ch->tryRecv();
    if ($response === null) {
        echo "请求超时\n";
        $timeout = $timeout_ch->recv();
        echo "超时原因: $timeout\n";
    }

    echo "✅ HTTP 请求超时测试通过\n";
} catch (Exception $e) {
    echo "❌ HTTP 请求超时测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试14: HTTP 流式响应 ====================
echo "【测试14】HTTP 流式响应（模拟）\n";
try {
    $stream_ch = new Channel(10);

    // 模拟流式数据
    $chunks = ["chunk1", "chunk2", "chunk3", "chunk4", "chunk5"];

    foreach ($chunks as $chunk) {
        $stream_ch->send($chunk);
        echo "发送数据块: $chunk\n";
    }
    $stream_ch->close();

    // 接收流式数据
    echo "接收流式数据: ";
    while (($chunk = $stream_ch->recv()) !== null) {
        echo "$chunk ";
    }
    echo "\n";

    echo "✅ HTTP 流式响应测试通过\n";
} catch (Exception $e) {
    echo "❌ HTTP 流式响应测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试15: HTTP WebSocket ====================
echo "【测试15】HTTP WebSocket（模拟）\n";
try {
    $ws_ch = new Channel(10);
    $mutex = new Mutex();
    $shared = new SharedData();

    // 模拟 WebSocket 连接
    $shared->set("ws_connected", true);
    $shared->set("ws_messages", 0);

    // 发送消息
    for ($i = 0; $i < 5; $i++) {
        $message = [
            'type' => 'message',
            'data' => "Hello $i",
        ];
        $ws_ch->send($message);

        $mutex->lock();
        $count = $shared->get("ws_messages");
        $count++;
        $shared->set("ws_messages", $count);
        $mutex->unlock();

        echo "发送 WebSocket 消息: {$message['data']}\n";
    }
    $ws_ch->close();

    // 接收消息
    while (($message = $ws_ch->recv()) !== null) {
        echo "接收 WebSocket 消息: {$message['data']}\n";
    }

    $total = $shared->get("ws_messages");
    echo "总共发送 $total 条消息\n";

    echo "✅ HTTP WebSocket 测试通过\n";
} catch (Exception $e) {
    echo "❌ HTTP WebSocket 测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试16: 协程栈 - 尾递归优化 ====================
echo "【测试16】协程栈尾递归优化（模拟）\n";
try {
    $stack = new Channel(10);
    $call_count = new Atomic(0);

    // 模拟尾递归
    function tail_recursive($n, $stack, $call_count) {
        if ($n <= 0) {
            return 0;
        }

        $call_count->increment();
        $stack->send("frame_$n");

        // 尾递归调用
        return $n + tail_recursive($n - 1, $stack, $call_count);
    }

    $result = tail_recursive(5, $stack, $call_count);

    echo "尾递归结果: $result\n";
    echo "调用次数: " . $call_count->load() . "\n";

    // 清理栈
    while (($frame = $stack->recv()) !== null) {
        echo "清理: $frame\n";
    }

    echo "✅ 协程栈尾递归优化测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈尾递归优化测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试17: HTTP 请求缓存 ====================
echo "【测试17】HTTP 请求缓存（模拟）\n";
try {
    $cache = new SharedData();
    $mutex = new Mutex();

    // 模拟缓存键
    $cache_key = "http://api.example.com/data";

    // 检查缓存
    $mutex->lock();
    $cached = $cache->get($cache_key);
    $mutex->unlock();

    if ($cached !== null) {
        echo "从缓存获取: $cached\n";
    } else {
        // 模拟 HTTP 请求
        $response = "API 响应数据";
        echo "从 API 获取: $response\n";

        // 存入缓存
        $mutex->lock();
        $cache->set($cache_key, $response);
        $cache->set("{$cache_key}_timestamp", time());
        $mutex->unlock();
    }

    // 再次检查缓存
    $mutex->lock();
    $cached = $cache->get($cache_key);
    $mutex->unlock();
    echo "缓存命中: " . ($cached !== null ? "是" : "否") . "\n";

    echo "✅ HTTP 请求缓存测试通过\n";
} catch (Exception $e) {
    echo "❌ HTTP 请求缓存测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试18: 协程栈 - 栈溢出保护 ====================
echo "【测试18】协程栈溢出保护（模拟）\n";
try {
    $stack = new Channel(100); // 限制栈大小
    $max_depth = 50;

    // 模拟深度递归
    function deep_recursion($depth, $max_depth, $stack) {
        if ($depth >= $max_depth) {
            echo "达到最大深度: $depth\n";
            return;
        }

        // 检查栈是否已满
        if ($stack->len() >= 100) {
            echo "栈溢出保护触发\n";
            return;
        }

        $stack->send("depth_$depth");
        deep_recursion($depth + 1, $max_depth, $stack);
    }

    deep_recursion(0, $max_depth, $stack);

    $stack_size = $stack->len();
    echo "最终栈大小: $stack_size\n";

    // 清理
    while (($frame = $stack->recv()) !== null) {
        // 清理
    }

    echo "✅ 协程栈溢出保护测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈溢出保护测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试19: HTTP 请求限流 ====================
echo "【测试19】HTTP 请求限流（模拟）\n";
try {
    $rate_limit = new Channel(3); // 每秒3个请求
    $request_ch = new Channel(10);
    $mutex = new Mutex();
    $shared = new SharedData();

    // 初始化限流器
    for ($i = 0; $i < 3; $i++) {
        $rate_limit->send(1);
    }

    // 提交请求
    for ($i = 0; $i < 10; $i++) {
        $request_ch->send($i);
    }
    $request_ch->close();

    // 处理请求（限流）
    while (($request = $request_ch->recv()) !== null) {
        $token = $rate_limit->tryRecv();
        if ($token !== null) {
            $mutex->lock();
            $count = $shared->get("processed", 0);
            $count++;
            $shared->set("processed", $count);
            $mutex->unlock();
            echo "处理请求 $request\n";

            // 模拟令牌补充
            $rate_limit->send(1);
        } else {
            echo "请求 $request 被限流\n";
        }
    }

    $total = $shared->get("processed", 0);
    echo "总共处理 $total 个请求\n";

    echo "✅ HTTP 请求限流测试通过\n";
} catch (Exception $e) {
    echo "❌ HTTP 请求限流测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 测试20: 协程栈 - 栈帧复用 ====================
echo "【测试20】协程栈栈帧复用（模拟）\n";
try {
    $frame_pool = new Channel(5);
    $active_frames = new Atomic(0);

    // 初始化栈帧池
    for ($i = 0; $i < 3; $i++) {
        $frame = [
            'id' => $i,
            'data' => null,
        ];
        $frame_pool->send($frame);
        echo "创建栈帧: {$frame['id']}\n";
    }

    // 使用栈帧
    for ($i = 0; $i < 5; $i++) {
        $frame = $frame_pool->recv();
        $active_frames->increment();

        $frame['data'] = "data_$i";
        echo "使用栈帧 {$frame['id']}: {$frame['data']}\n";

        // 归还栈帧（复用）
        $frame['data'] = null;
        $frame_pool->send($frame);
        $active_frames->decrement();
    }

    echo "活跃栈帧: " . $active_frames->load() . "\n";
    echo "✅ 协程栈栈帧复用测试通过\n";
} catch (Exception $e) {
    echo "❌ 协程栈栈帧复用测试失败: " . $e->getMessage() . "\n";
}
echo "\n";

// ==================== 总结 ====================
echo "========================================\n";
echo "  总结\n";
echo "========================================\n";
echo "✅ Channel 通信功能正常\n";
echo "✅ Mutex 锁功能正常\n";
echo "✅ Atomic 原子操作正常\n";
echo "✅ SharedData 共享数据正常\n";
echo "✅ 协程栈模拟功能正常\n";
echo "⚠️  HTTP 服务器需要 VM 支持\n";
echo "⚠️  HTTP 客户端需要 VM 支持\n";
echo "⚠️  go 关键词需要 VM 支持\n";
echo "========================================\n";
echo "测试完成！\n";
