const std = @import("std");
const http_server = @import("../src/runtime/http_server.zig");
const concurrency = @import("../src/runtime/concurrency.zig");
const types = @import("../src/runtime/types.zig");

test "HTTP server concurrent request handling" {
    const allocator = std.testing.allocator;

    var server = try http_server.HttpServer.init(allocator, .{
        .host = "127.0.0.1",
        .port = 8888,
        .enable_coroutines = true,
        .context_pool_size = 10,
    }, undefined);
    defer server.deinit();

    // 验证上下文池已预分配
    try std.testing.expect(server.request_context_pool.items.len == 10);

    // 验证活跃请求计数初始为0
    try std.testing.expect(server.getActiveRequestCount() == 0);
}

test "RequestContext isolation" {
    const allocator = std.testing.allocator;

    var ctx1 = http_server.HttpServer.RequestContext.init(allocator, 1, undefined);
    defer ctx1.deinit();

    var ctx2 = http_server.HttpServer.RequestContext.init(allocator, 2, undefined);
    defer ctx2.deinit();

    // 设置不同的局部变量
    const value1 = types.Value.initInteger(100);
    const value2 = types.Value.initInteger(200);

    try ctx1.setLocal("counter", value1);
    try ctx2.setLocal("counter", value2);

    // 验证上下文隔离
    const ctx1_val = ctx1.getLocal("counter").?;
    const ctx2_val = ctx2.getLocal("counter").?;

    try std.testing.expect(ctx1_val.data.integer == 100);
    try std.testing.expect(ctx2_val.data.integer == 200);
}

test "PHPMutex concurrent access" {
    const allocator = std.testing.allocator;
    var mutex = concurrency.PHPMutex.init(allocator);
    defer mutex.deinit();

    var counter: i32 = 0;
    const thread_count = 10;
    const iterations = 100;

    const ThreadContext = struct {
        mutex_ptr: *concurrency.PHPMutex,
        counter_ptr: *i32,
        iterations_val: i32,
    };

    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            var i: i32 = 0;
            while (i < ctx.iterations_val) : (i += 1) {
                ctx.mutex_ptr.lock();
                ctx.counter_ptr.* += 1;
                ctx.mutex_ptr.unlock();
            }
        }
    }.run;

    var threads: [thread_count]std.Thread = undefined;
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .mutex_ptr = &mutex,
            .counter_ptr = &counter,
            .iterations_val = iterations,
        }});
    }

    for (threads) |thread| {
        thread.join();
    }

    // 验证计数正确（无竞争条件）
    try std.testing.expect(counter == thread_count * iterations);
}

test "PHPAtomic concurrent operations" {
    const allocator = std.testing.allocator;
    var atomic = concurrency.PHPAtomic.init(allocator, 0);
    defer atomic.deinit();

    const thread_count = 10;
    const iterations = 100;

    const ThreadContext = struct {
        atomic_ptr: *concurrency.PHPAtomic,
        iterations_val: i32,
    };

    const threadFunc = struct {
        fn run(ctx: ThreadContext) void {
            var i: i32 = 0;
            while (i < ctx.iterations_val) : (i += 1) {
                _ = ctx.atomic_ptr.increment();
            }
        }
    }.run;

    var threads: [thread_count]std.Thread = undefined;
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .atomic_ptr = &atomic,
            .iterations_val = iterations,
        }});
    }

    for (threads) |thread| {
        thread.join();
    }

    // 验证原子操作正确
    try std.testing.expect(atomic.load() == thread_count * iterations);
}

test "PHPSharedData concurrent access" {
    const allocator = std.testing.allocator;
    var shared = concurrency.PHPSharedData.init(allocator);
    defer shared.deinit();

    const thread_count = 5;
    const iterations = 20;

    const ThreadContext = struct {
        shared_ptr: *concurrency.PHPSharedData,
        thread_id: usize,
        iterations_val: i32,
    };

    const threadFunc = struct {
        fn run(ctx: ThreadContext) !void {
            var i: i32 = 0;
            while (i < ctx.iterations_val) : (i += 1) {
                var key_buf: [32]u8 = undefined;
                const key = try std.fmt.bufPrint(&key_buf, "thread_{d}_key_{d}", .{ ctx.thread_id, i });

                const value = types.Value.initInteger(@as(i64, @intCast(ctx.thread_id * 1000 + i)));
                try ctx.shared_ptr.set(key, value);

                // 验证可以读取
                if (ctx.shared_ptr.get(key)) |val| {
                    defer val.release(std.testing.allocator);
                    std.debug.assert(val.tag == .integer);
                }
            }
        }
    }.run;

    var threads: [thread_count]std.Thread = undefined;
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, threadFunc, .{ThreadContext{
            .shared_ptr = &shared,
            .thread_id = i,
            .iterations_val = iterations,
        }});
    }

    for (threads) |thread| {
        thread.join();
    }

    // 验证所有数据都已存储
    try std.testing.expect(shared.size() == thread_count * iterations);
    try std.testing.expect(shared.getAccessCount() >= thread_count * iterations * 2);
}

test "PHPRWLock concurrent read/write" {
    const allocator = std.testing.allocator;
    var rwlock = concurrency.PHPRWLock.init(allocator);
    defer rwlock.deinit();

    var shared_value: i64 = 0;
    const reader_count = 5;
    const writer_count = 2;

    const ReaderContext = struct {
        rwlock_ptr: *concurrency.PHPRWLock,
        value_ptr: *i64,
    };

    const WriterContext = struct {
        rwlock_ptr: *concurrency.PHPRWLock,
        value_ptr: *i64,
        increment: i64,
    };

    const readerFunc = struct {
        fn run(ctx: ReaderContext) void {
            var i: i32 = 0;
            while (i < 10) : (i += 1) {
                ctx.rwlock_ptr.lockRead();
                _ = ctx.value_ptr.*;
                ctx.rwlock_ptr.unlockRead();
                std.Thread.sleep(1000000); // 1ms
            }
        }
    }.run;

    const writerFunc = struct {
        fn run(ctx: WriterContext) void {
            var i: i32 = 0;
            while (i < 5) : (i += 1) {
                ctx.rwlock_ptr.lockWrite();
                ctx.value_ptr.* += ctx.increment;
                ctx.rwlock_ptr.unlockWrite();
                std.Thread.sleep(2000000); // 2ms
            }
        }
    }.run;

    var readers: [reader_count]std.Thread = undefined;
    var writers: [writer_count]std.Thread = undefined;

    // 启动读者
    var i: usize = 0;
    while (i < reader_count) : (i += 1) {
        readers[i] = try std.Thread.spawn(.{}, readerFunc, .{ReaderContext{
            .rwlock_ptr = &rwlock,
            .value_ptr = &shared_value,
        }});
    }

    // 启动写者
    i = 0;
    while (i < writer_count) : (i += 1) {
        writers[i] = try std.Thread.spawn(.{}, writerFunc, .{WriterContext{
            .rwlock_ptr = &rwlock,
            .value_ptr = &shared_value,
            .increment = 10,
        }});
    }

    // 等待所有线程完成
    for (readers) |thread| {
        thread.join();
    }
    for (writers) |thread| {
        thread.join();
    }

    // 验证写入正确
    try std.testing.expect(shared_value == writer_count * 5 * 10);
}

test "HTTP request parsing" {
    const allocator = std.testing.allocator;

    const raw_request = "GET /api/users?page=1&limit=10 HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "User-Agent: TestClient/1.0\r\n" ++
        "Content-Type: application/json\r\n" ++
        "\r\n";

    const request = try http_server.HttpRequest.parse(allocator, raw_request);
    defer request.deinit(allocator);

    try std.testing.expect(request.method == .GET);
    try std.testing.expectEqualStrings("/api/users", request.path);
    try std.testing.expectEqualStrings("1", request.getQueryParam("page").?);
    try std.testing.expectEqualStrings("10", request.getQueryParam("limit").?);
    try std.testing.expectEqualStrings("localhost:8080", request.getHeader("Host").?);
}

test "HTTP response building" {
    const allocator = std.testing.allocator;

    var response = http_server.HttpResponse.init(allocator);
    defer response.deinit();

    response.setStatus(200);
    try response.setHeader("Content-Type", "application/json");
    try response.setBody("{\"status\":\"ok\"}");

    const bytes = try response.toBytes();
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Content-Type: application/json") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "{\"status\":\"ok\"}") != null);
}

test "Router path matching" {
    const allocator = std.testing.allocator;

    var router = http_server.Router.init(allocator);
    defer router.deinit();

    const dummy_handler = types.Value.initNull();
    try router.addRoute(.GET, "/users/:id", dummy_handler);
    try router.addRoute(.POST, "/users", dummy_handler);

    // 测试路由匹配
    const route1 = router.match(.GET, "/users/123");
    try std.testing.expect(route1 != null);
    try std.testing.expectEqualStrings("/users/:id", route1.?.path);

    const route2 = router.match(.POST, "/users");
    try std.testing.expect(route2 != null);

    const route3 = router.match(.DELETE, "/users/123");
    try std.testing.expect(route3 == null);
}
