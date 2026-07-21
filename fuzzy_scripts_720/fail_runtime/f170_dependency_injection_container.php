<?php
// 依赖注入容器：自动注入、标签、别名、装饰器
echo "=== f170: DI Container + AutoWire + Tags ===\n";

class DIContainer {
    private array $definitions = [];
    private array $instances = [];
    private array $tags = [];
    private array $aliases = [];

    public function bind(string $id, mixed $concrete): void {
        $this->definitions[$id] = $concrete;
    }

    public function singleton(string $id, mixed $concrete): void {
        $this->definitions[$id] = $concrete;
        $this->aliases[$id] = 'singleton';
    }

    public function alias(string $alias, string $id): void {
        $this->aliases[$alias] = $id;
    }

    public function tag(string $tag, string $id): void {
        if (!isset($this->tags[$tag])) $this->tags[$tag] = [];
        $this->tags[$tag][] = $id;
    }

    public function tagged(string $tag): array {
        $ids = $this->tags[$tag] ?? [];
        return array_map(fn($id) => $this->make($id), $ids);
    }

    public function make(string $id, array $params = []): mixed {
        // 检查别名
        while (isset($this->aliases[$id]) && $this->aliases[$id] !== 'singleton') {
            $id = $this->aliases[$id];
        }

        // 单例检查
        $isSingleton = isset($this->aliases[$id]) && $this->aliases[$id] === 'singleton';
        if ($isSingleton && isset($this->instances[$id])) {
            return $this->instances[$id];
        }

        // 获取定义
        $concrete = $this->definitions[$id] ?? $id;

        if (is_callable($concrete)) {
            $object = $concrete($this);
        } elseif (is_string($concrete) && class_exists($concrete)) {
            $object = $this->autowire($concrete, $params);
        } else {
            return $concrete;
        }

        if ($isSingleton) {
            $this->instances[$id] = $object;
        }

        return $object;
    }

    private function autowire(string $class, array $params = []): object {
        $ref = new ReflectionClass($class);
        if (!$ref->isInstantiable()) {
            throw new Exception("Class $class is not instantiable");
        }

        $constructor = $ref->getConstructor();
        if ($constructor === null) {
            return new $class();
        }

        $args = [];
        foreach ($constructor->getParameters() as $param) {
            $name = $param->getName();
            if (isset($params[$name])) {
                $args[] = $params[$name];
                continue;
            }

            $type = $param->getType();
            if ($type && !$type->isBuiltin()) {
                $typeName = $type->getName();
                $args[] = $this->make($typeName);
            } elseif ($param->isDefaultValueAvailable()) {
                $args[] = $param->getDefaultValue();
            } elseif ($param->allowsNull()) {
                $args[] = null;
            } else {
                throw new Exception("Cannot resolve parameter \$$name for $class");
            }
        }

        return $ref->newInstanceArgs($args);
    }

    public function call(string $class, string $method, array $params = []): mixed {
        $instance = $this->make($class);
        $ref = new ReflectionMethod($class, $method);
        $args = [];
        foreach ($ref->getParameters() as $param) {
            $name = $param->getName();
            if (isset($params[$name])) {
                $args[] = $params[$name];
            } else {
                $type = $param->getType();
                if ($type && !$type->isBuiltin()) {
                    $args[] = $this->make($type->getName());
                } elseif ($param->isDefaultValueAvailable()) {
                    $args[] = $param->getDefaultValue();
                } else {
                    $args[] = null;
                }
            }
        }
        return $instance->$method(...$args);
    }
}

// 服务类
interface LoggerInterface {
    public function log(string $level, string $msg): void;
}

class FileLogger implements LoggerInterface {
    public function __construct(private string $path = '/var/log') {}
    public function log(string $level, string $msg): void { echo "  [FileLogger:$this->path] $level: $msg\n"; }
}

class ConsoleLogger implements LoggerInterface {
    public function log(string $level, string $msg): void { echo "  [ConsoleLogger] $level: $msg\n"; }
}

interface CacheInterface {
    public function get(string $key): mixed;
    public function set(string $key, mixed $val): void;
}

class ArrayCache implements CacheInterface {
    private array $data = [];
    public function get(string $key): mixed { return $this->data[$key] ?? null; }
    public function set(string $key, mixed $val): void { $this->data[$key] = $val; }
}

class UserRepository {
    public function __construct(private LoggerInterface $logger) {}

    public function find(int $id): array {
        $this->logger->log('info', "Finding user $id");
        return ['id' => $id, 'name' => 'User' . $id];
    }

    public function all(): array {
        $this->logger->log('info', 'Fetching all users');
        return [['id' => 1, 'name' => 'Alice'], ['id' => 2, 'name' => 'Bob']];
    }
}

class UserService {
    public function __construct(
        private UserRepository $repo,
        private LoggerInterface $logger,
        private CacheInterface $cache,
    ) {}

    public function getUser(int $id): array {
        $cacheKey = "user_$id";
        $cached = $this->cache->get($cacheKey);
        if ($cached) {
            $this->logger->log('debug', "Cache hit for user $id");
            return $cached;
        }
        $user = $this->repo->find($id);
        $this->cache->set($cacheKey, $user);
        return $user;
    }

    public function getAllUsers(): array {
        return $this->repo->all();
    }
}

class UserController {
    public function __construct(private UserService $service) {}

    public function show(int $id): string {
        $user = $this->service->getUser($id);
        return json_encode($user);
    }

    public function index(): string {
        $users = $this->service->getAllUsers();
        return json_encode($users);
    }
}

// 测试
echo "--- DI Container Setup ---\n";
$container = new DIContainer();

// 绑定接口到实现
$container->bind(LoggerInterface::class, FileLogger::class);
$container->singleton(CacheInterface::class, ArrayCache::class);
$container->bind(UserRepository::class, UserRepository::class);
$container->bind(UserService::class, UserService::class);
$container->bind(UserController::class, UserController::class);

// 别名
$container->alias('logger', LoggerInterface::class);
$container->alias('cache', CacheInterface::class);

// 标签
$container->tag('loggers', FileLogger::class);
$container->tag('loggers', ConsoleLogger::class);

echo "  Bindings registered\n";

echo "\n--- Auto-Wiring ---\n";
$controller = $container->make(UserController::class);
echo "  Controller created: " . get_class($controller) . "\n";
echo "  Show user 1: " . $controller->show(1) . "\n";
echo "  Show user 1 (cached): " . $controller->show(1) . "\n";
echo "  Index: " . $controller->index() . "\n";

echo "\n--- Singleton Check ---\n";
$cache1 = $container->make(CacheInterface::class);
$cache2 = $container->make(CacheInterface::class);
echo "  Cache singleton: " . ($cache1 === $cache2 ? 'YES' : 'NO') . "\n";

$logger1 = $container->make(LoggerInterface::class);
$logger2 = $container->make(LoggerInterface::class);
echo "  Logger singleton: " . ($logger1 === $logger2 ? 'YES' : 'NO') . "\n";

echo "\n--- Tagged Services ---\n";
$loggers = $container->tagged('loggers');
echo "  Tagged loggers: " . count($loggers) . "\n";
foreach ($loggers as $logger) {
    $logger->log('info', 'Hello from tagged logger');
}

echo "\n--- Method Injection ---\n";
$result = $container->call(UserController::class, 'show', ['id' => 42]);
echo "  Called show(42): $result\n";

echo "\n--- Switch Implementation ---\n";
$container->bind(LoggerInterface::class, ConsoleLogger::class);
$controller2 = $container->make(UserController::class);
echo "  With ConsoleLogger: " . $controller2->show(3) . "\n";

echo "=== f170 Done ===\n";
