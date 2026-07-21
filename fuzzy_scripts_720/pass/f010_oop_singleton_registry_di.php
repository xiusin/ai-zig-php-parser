<?php
// 极度混搭: 单例 + 注册表 + 依赖注入容器 + 接口绑定 + 工厂闭包 + 作用域
echo "=== f010: Singleton + Registry + DI Container ===\n";

interface CacheInterface {
    public function get(string $key): mixed;
    public function set(string $key, mixed $value): void;
    public function has(string $key): bool;
    public function delete(string $key): void;
}

interface LoggerInterface {
    public function log(string $level, string $message): void;
    public function getLogs(): array;
}

class ArrayCache implements CacheInterface {
    private array $data = [];

    public function get(string $key): mixed { return $this->data[$key] ?? null; }
    public function set(string $key, mixed $value): void { $this->data[$key] = $value; }
    public function has(string $key): bool { return isset($this->data[$key]); }
    public function delete(string $key): void { unset($this->data[$key]); }
    public function count(): int { return count($this->data); }
}

class MemoryLogger implements LoggerInterface {
    private array $logs = [];
    public function log(string $level, string $message): void { $this->logs[] = "[$level] $message"; }
    public function getLogs(): array { return $this->logs; }
}

// 依赖注入容器（内联单例模式，不使用 trait）
class Container {
    private static ?Container $instance = null;

    private array $bindings = [];
    private array $instances = [];
    private array $singletons = [];

    public function bind(string $abstract, callable|string $concrete): void {
        $this->bindings[$abstract] = $concrete;
    }

    public function singleton(string $abstract, callable|string $concrete): void {
        $this->bindings[$abstract] = $concrete;
        $this->singletons[$abstract] = true;
    }

    public function make(string $abstract): object {
        // 单例检查
        if (isset($this->singletons[$abstract]) && isset($this->instances[$abstract])) {
            return $this->instances[$abstract];
        }

        $concrete = $this->bindings[$abstract] ?? $abstract;

        if (is_callable($concrete)) {
            $instance = $concrete($this);
        } else {
    if (class_exists($concrete)) {
            $instance = new $concrete();
        } else {
            throw new RuntimeException("Cannot resolve: $abstract");
        }
    }

    if (isset($this->singletons[$abstract])) {
            $this->instances[$abstract] = $instance;
        }

        return $instance;
    }

    public function bound(string $abstract): bool {
        return isset($this->bindings[$abstract]);
    }

    public static function getInstance(): Container {
        return self::$instance ??= new self();
    }

    public function forget(string $abstract): void {
        unset($this->bindings[$abstract], $this->instances[$abstract], $this->singletons[$abstract]);
    }
}

// 服务类
class UserService {
    private CacheInterface $cache;
    private LoggerInterface $logger;

    public function __construct(CacheInterface $cache, LoggerInterface $logger) {
        $this->cache = $cache;
        $this->logger = $logger;
    }

    public function getUser(int $id): array {
        $key = "user:$id";
        if ($this->cache->has($key)) {
            $this->logger->log('DEBUG', "Cache hit for $key");
            return $this->cache->get($key);
        }
        $this->logger->log('INFO', "Cache miss for $key, fetching...");
        $user = ['id' => $id, 'name' => "User$id", 'email' => "user$id@example.com"];
        $this->cache->set($key, $user);
        return $user;
    }
}

class OrderService {
    private UserService $users;
    private LoggerInterface $logger;

    public function __construct(UserService $users, LoggerInterface $logger) {
        $this->users = $users;
        $this->logger = $logger;
    }

    public function createOrder(int $userId, array $items): array {
        $user = $this->users->getUser($userId);
        $total = array_sum(array_map(fn($i) => $i['price'] * $i['qty'], $items));
        $this->logger->log('INFO', "Created order for user {$user['name']}, total=$total");
        return [
            'user' => $user,
            'items' => $items,
            'total' => $total,
        ];
    }
}

// === 测试 ===
$container = Container::getInstance();

// 绑定接口到实现
$container->singleton(CacheInterface::class, fn($c) => new ArrayCache());
$container->singleton(LoggerInterface::class, fn($c) => new MemoryLogger());
$container->bind(UserService::class, fn($c) => new UserService($c->make(CacheInterface::class), $c->make(LoggerInterface::class)));
$container->bind(OrderService::class, fn($c) => new OrderService($c->make(UserService::class), $c->make(LoggerInterface::class)));

// 解析服务
$userService = $container->make(UserService::class);
$user1 = $userService->getUser(1);
echo "User1: " . json_encode($user1) . "\n";

// 第二次获取（缓存命中）
$user1Again = $userService->getUser(1);
echo "User1 (cached): " . json_encode($user1Again) . "\n";

// 新用户
$user2 = $userService->getUser(2);
echo "User2: " . json_encode($user2) . "\n";

// 订单服务
$orderService = $container->make(OrderService::class);
$order = $orderService->createOrder(1, [
    ['name' => 'Widget', 'price' => 10.50, 'qty' => 3],
    ['name' => 'Gadget', 'price' => 25.00, 'qty' => 1],
]);
echo "\nOrder: " . json_encode($order) . "\n";

// 单例验证
$logger1 = $container->make(LoggerInterface::class);
$logger2 = $container->make(LoggerInterface::class);
echo "\nLogger singleton: " . var_export($logger1 === $logger2, true) . "\n";

// 非单例验证
$us1 = $container->make(UserService::class);
$us2 = $container->make(UserService::class);
echo "UserService not singleton: " . var_export($us1 !== $us2, true) . "\n";

// 打印日志
$logger = $container->make(LoggerInterface::class);
echo "\nLogs:\n";
foreach ($logger->getLogs() as $log) {
    echo "  $log\n";
}

// 容器单例验证
$c1 = Container::getInstance();
$c2 = Container::getInstance();
echo "\nContainer singleton: " . var_export($c1 === $c2, true) . "\n";

// 缓存统计
$cache = $container->make(CacheInterface::class);
if ($cache instanceof ArrayCache) {
    echo "Cache entries: " . $cache->count() . "\n";
}

echo "=== f010 Done ===\n";
