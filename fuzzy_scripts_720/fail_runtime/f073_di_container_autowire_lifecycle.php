<?php
// 极度混搭: 依赖注入容器 + 自动装配 + 生命周期 + 工厂
echo "=== f073: DI Container + Autowire + Lifecycle ===\n";

interface LoggerInterface {
    public function log(string $msg): void;
}

class ConsoleLogger implements LoggerInterface {
    private array $logs = [];
    public function log(string $msg): void { $this->logs[] = $msg; echo "  [LOG] $msg\n"; }
    public function getLogs(): array { return $this->logs; }
}

class FileLogger implements LoggerInterface {
    private array $logs = [];
    public function __construct(private string $filename = 'app.log') {}
    public function log(string $msg): void { $this->logs[] = "[$this->filename] $msg"; echo "  [FILE:$this->filename] $msg\n"; }
    public function getLogs(): array { return $this->logs; }
}

interface CacheInterface {
    public function get(string $key): mixed;
    public function set(string $key, mixed $value): void;
}

class MemoryCache implements CacheInterface {
    private array $data = [];
    public function get(string $key): mixed { return $this->data[$key] ?? null; }
    public function set(string $key, mixed $value): void { $this->data[$key] = $value; }
}

class UserService {
    public function __construct(
        private LoggerInterface $logger,
        private CacheInterface $cache
    ) {}

    public function getUser(int $id): array {
        $cacheKey = "user_$id";
        $cached = $this->cache->get($cacheKey);
        if ($cached !== null) {
            $this->logger->log("Cache hit for user $id");
            return $cached;
        }
        $this->logger->log("Cache miss, fetching user $id");
        $user = ['id' => $id, 'name' => "User$id", 'email' => "user$id@example.com"];
        $this->cache->set($cacheKey, $user);
        return $user;
    }
}

class AuthService {
    private array $tokens = [];
    public function __construct(private UserService $users, private LoggerInterface $logger) {}

    public function login(int $userId): string {
        $user = $this->users->getUser($userId);
        $token = bin2hex(random_bytes(8));
        $this->tokens[$token] = $userId;
        $this->logger->log("User {$user['name']} logged in with token $token");
        return $token;
    }

    public function validate(string $token): ?int {
        return $this->tokens[$token] ?? null;
    }
}

class DIContainer {
    private array $bindings = [];
    private array $instances = [];
    private array $singletons = [];

    public function bind(string $abstract, mixed $concrete): void {
        $this->bindings[$abstract] = $concrete;
    }

    public function singleton(string $abstract, mixed $concrete): void {
        $this->singletons[$abstract] = $concrete;
    }

    public function make(string $abstract): mixed {
        // 单例检查
        if (isset($this->instances[$abstract])) return $this->instances[$abstract];

        $concrete = $this->bindings[$abstract] ?? $this->singletons[$abstract] ?? $abstract;

        if (is_callable($concrete)) {
            $instance = $concrete($this);
        } elseif (is_string($concrete) && class_exists($concrete)) {
            $instance = $this->autowire($concrete);
        } else {
            $instance = $concrete;
        }

        if (isset($this->singletons[$abstract])) {
            $this->instances[$abstract] = $instance;
        }
        return $instance;
    }

    private function autowire(string $class): object {
        $ref = new ReflectionClass($class);
        $constructor = $ref->getConstructor();
        if ($constructor === null) return new $class();

        $params = [];
        foreach ($constructor->getParameters() as $param) {
            $type = $param->getType();
            if ($type && !$type->isBuiltin()) {
                $typeName = $type->getName();
                $params[] = $this->make($typeName);
            } elseif ($param->isDefaultValueAvailable()) {
                $params[] = $param->getDefaultValue();
            } else {
                $params[] = null;
            }
        }
        return $ref->newInstanceArgs($params);
    }

    public function has(string $abstract): bool {
        return isset($this->bindings[$abstract]) || isset($this->singletons[$abstract]) || class_exists($abstract);
    }
}

// 测试
$container = new DIContainer();

// 绑定接口
$container->singleton(LoggerInterface::class, fn($c) => new ConsoleLogger());
$container->singleton(CacheInterface::class, fn($c) => new MemoryCache());

echo "--- Resolve UserService ---\n";
$userService = $container->make(UserService::class);
$user1 = $userService->getUser(1);
echo "User1: " . json_encode($user1) . "\n";
$user1Again = $userService->getUser(1);
echo "User1 again: " . json_encode($user1Again) . "\n";

echo "\n--- Resolve AuthService ---\n";
$authService = $container->make(AuthService::class);
$token = $authService->login(2);
echo "Token: $token\n";
$userId = $authService->validate($token);
echo "Validated user: $userId\n";
$invalid = $authService->validate('invalid');
echo "Invalid token: " . var_export($invalid, true) . "\n";

echo "\n--- Singleton Check ---\n";
$logger1 = $container->make(LoggerInterface::class);
$logger2 = $container->make(LoggerInterface::class);
echo "Logger is singleton: " . var_export($logger1 === $logger2, true) . "\n";

echo "\n--- Switch Logger ---\n";
$container2 = new DIContainer();
$container2->singleton(LoggerInterface::class, fn($c) => new FileLogger('test.log'));
$container2->singleton(CacheInterface::class, fn($c) => new MemoryCache());
$auth2 = $container2->make(AuthService::class);
$auth2->login(3);

echo "\n--- Factory Pattern ---\n";
$container3 = new DIContainer();
$container3->bind(LoggerInterface::class, fn($c) => new ConsoleLogger());
$container3->bind(CacheInterface::class, fn($c) => new MemoryCache());
// 每次make都创建新实例
$svc1 = $container3->make(UserService::class);
$svc2 = $container3->make(UserService::class);
echo "UserService is singleton (bind): " . var_export($svc1 === $svc2, true) . " (should be false)\n";

echo "=== f073 Done ===\n";
