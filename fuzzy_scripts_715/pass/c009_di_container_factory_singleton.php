<?php
// 极度混搭: 依赖注入容器 + 反射模式 + 工厂模式 + 单例 + 延迟绑定
echo "=== c009: DI Container + Factory + Singleton + Deferred Binding ===\n\n";

interface LoggerInterface {
    public function log(string $level, string $message, array $context = []): void;
}

interface CacheInterface {
    public function get(string $key): mixed;
    public function set(string $key, mixed $value, int $ttl = 0): bool;
    public function delete(string $key): bool;
}

class ConsoleLogger implements LoggerInterface {
    private array $logs = [];

    public function log(string $level, string $message, array $context = []): void {
        $ctx = empty($context) ? "" : " " . json_encode($context);
        echo "  [$level] $message$ctx\n";
        $this->logs[] = ['level' => $level, 'message' => $message, 'context' => $context];
    }

    public function getLogs(): array {
        return $this->logs;
    }

    public function countByLevel(string $level): int {
        return count(array_filter($this->logs, fn($l) => $l['level'] === $level));
    }
}

class MemoryCache implements CacheInterface {
    private array $store = [];
    private array $ttls = [];

    public function get(string $key): mixed {
        if (!isset($this->store[$key])) return null;
        return $this->store[$key];
    }

    public function set(string $key, mixed $value, int $ttl = 0): bool {
        $this->store[$key] = $value;
        $this->ttls[$key] = $ttl;
        return true;
    }

    public function delete(string $key): bool {
        unset($this->store[$key], $this->ttls[$key]);
        return true;
    }

    public function keys(): array {
        return array_keys($this->store);
    }
}

class DIContainer {
    private array $bindings = [];
    private array $instances = [];
    private array $singletons = [];

    public function bind(string $abstract, string|callable $concrete): self {
        $this->bindings[$abstract] = $concrete;
        return $this;
    }

    public function singleton(string $abstract, string|callable $concrete): self {
        $this->singletons[$abstract] = true;
        $this->bindings[$abstract] = $concrete;
        return $this;
    }

    public function make(string $abstract): object {
        if (isset($this->instances[$abstract])) {
            return $this->instances[$abstract];
        }

        $concrete = $this->bindings[$abstract] ?? $abstract;

        if (is_callable($concrete)) {
            $instance = $concrete($this);
        } else {
            // Simple resolution: instantiate with container-resolved dependencies
            $instance = $this->resolveClass($concrete);
        }

        if (isset($this->singletons[$abstract])) {
            $this->instances[$abstract] = $instance;
        }

        return $instance;
    }

    private function resolveClass(string $class): object {
        return new $class();
    }

    public function has(string $abstract): bool {
        return isset($this->bindings[$abstract]);
    }

    public function getBindings(): array {
        return array_keys($this->bindings);
    }
}

class UserService {
    private LoggerInterface $logger;
    private CacheInterface $cache;

    public function __construct(LoggerInterface $logger, CacheInterface $cache) {
        $this->logger = $logger;
        $this->cache = $cache;
    }

    public function getUser(int $id): array {
        $cacheKey = "user:$id";
        $cached = $this->cache->get($cacheKey);
        if ($cached !== null) {
            $this->logger->log('debug', "Cache hit for user $id");
            return $cached;
        }

        $this->logger->log('info', "Fetching user $id from source");
        $user = ['id' => $id, 'name' => "User$id", 'email' => "user{$id}@example.com"];
        $this->cache->set($cacheKey, $user);
        return $user;
    }

    public function deleteUser(int $id): bool {
        $this->cache->delete("user:$id");
        $this->logger->log('warning', "Deleted user $id");
        return true;
    }
}

class OrderService {
    private LoggerInterface $logger;
    private UserService $users;

    public function __construct(LoggerInterface $logger, UserService $users) {
        $this->logger = $logger;
        $this->users = $users;
    }

    public function createOrder(int $userId, array $items): array {
        $user = $this->users->getUser($userId);
        $total = array_sum(array_map(fn($i) => $i['price'] * $i['qty'], $items));
        $order = [
            'id' => array_sum(array_map(fn($i) => $i['price'] * $i['qty'] * 1000, $items)) + $userId,
            'userId' => $userId,
            'userName' => $user['name'],
            'items' => $items,
            'total' => $total,
        ];
        $this->logger->log('info', "Order created for user $userId, total=$total");
        return $order;
    }
}

// === 测试 ===

echo "--- DI Container Setup ---\n";
$container = new DIContainer();

// 绑定接口到实现
$container->singleton(LoggerInterface::class, function() {
    return new ConsoleLogger();
});
$container->bind(CacheInterface::class, function() {
    return new MemoryCache();
});
$container->bind(UserService::class, function($c) {
    return new UserService($c->make(LoggerInterface::class), $c->make(CacheInterface::class));
});
$container->bind(OrderService::class, function($c) {
    return new OrderService($c->make(LoggerInterface::class), $c->make(UserService::class));
});

echo "Bindings: " . implode(", ", $container->getBindings()) . "\n";

echo "\n--- Service Resolution ---\n";
$logger = $container->make(LoggerInterface::class);
$logger->log('info', "Container initialized");

$userService = $container->make(UserService::class);

echo "\n--- First Access (cache miss) ---\n";
$user1 = $userService->getUser(42);
echo "User: " . json_encode($user1) . "\n";

echo "\n--- Second Access (cache hit) ---\n";
$user2 = $userService->getUser(42);
echo "User: " . json_encode($user2) . "\n";

echo "\n--- Singleton Test ---\n";
$logger1 = $container->make(LoggerInterface::class);
$logger2 = $container->make(LoggerInterface::class);
echo "Same logger instance: " . ($logger1 === $logger2 ? "YES" : "NO") . "\n";

echo "\n--- Order Service ---\n";
$orderService = $container->make(OrderService::class);
$order = $orderService->createOrder(42, [
    ['sku' => 'ITEM001', 'price' => 10.50, 'qty' => 2],
    ['sku' => 'ITEM002', 'price' => 25.00, 'qty' => 1],
    ['sku' => 'ITEM003', 'price' => 5.75, 'qty' => 4],
]);
echo "Order: " . json_encode($order) . "\n";

echo "\n--- Logger Summary ---\n";
echo "Info logs: " . $logger1->countByLevel('info') . "\n";
echo "Debug logs: " . $logger1->countByLevel('debug') . "\n";
echo "Warning logs: " . $logger1->countByLevel('warning') . "\n";

echo "\n--- Delete User ---\n";
$userService->deleteUser(42);
// After delete, should cache miss again
echo "User after delete: " . json_encode($userService->getUser(42)) . "\n";

echo "\n=== c009 Done ===\n";
