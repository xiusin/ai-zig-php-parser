<?php
// 极度混搭: 适配器模式 + 接口转换 + 第三方库模拟 + 统一API
echo "=== f037: Adapter + Interface Conversion + Unified API ===\n";

interface UnifiedCache {
    public function get(string $key): mixed;
    public function set(string $key, mixed $value, int $ttl = 0): bool;
    public function delete(string $key): bool;
    public function clear(): bool;
    public function keys(): array;
}

// 模拟 Redis 客户端
class RedisClient {
    private array $store = [];
    public function redisGet(string $key): mixed { return $this->store[$key] ?? null; }
    public function redisSet(string $key, mixed $val): void { $this->store[$key] = $val; }
    public function redisSetex(string $key, int $ttl, mixed $val): void { $this->store[$key] = $val; }
    public function redisDel(string $key): int { unset($this->store[$key]); return 1; }
    public function redisFlushAll(): void { $this->store = []; }
    public function redisKeys(string $pattern): array {
        $pattern = str_replace('*', '.*', $pattern);
        $result = [];
        foreach (array_keys($this->store) as $k) {
            if (preg_match("/^$pattern$/", $k)) $result[] = $k;
        }
        return $result;
    }
}

class RedisAdapter implements UnifiedCache {
    private RedisClient $redis;

    public function __construct() { $this->redis = new RedisClient(); }

    public function get(string $key): mixed { return $this->redis->redisGet($key); }
    public function set(string $key, mixed $value, int $ttl = 0): bool {
        if ($ttl > 0) $this->redis->redisSetex($key, $ttl, $value);
        else $this->redis->redisSet($key, $value);
        return true;
    }
    public function delete(string $key): bool { return $this->redis->redisDel($key) > 0; }
    public function clear(): bool { $this->redis->redisFlushAll(); return true; }
    public function keys(): array { return $this->redis->redisKeys('*'); }
}

// 模拟 Memcached 客户端
class MemcachedClient {
    private array $store = [];
    public function mcGet(string $key): mixed { return $this->store[$key] ?? false; }
    public function mcSet(string $key, mixed $val, int $ttl = 0): bool { $this->store[$key] = $val; return true; }
    public function mcDelete(string $key): bool { unset($this->store[$key]); return true; }
    public function mcFlush(): void { $this->store = []; }
    public function mcGetAllKeys(): array { return array_keys($this->store); }
}

class MemcachedAdapter implements UnifiedCache {
    private MemcachedClient $mc;
    public function __construct() { $this->mc = new MemcachedClient(); }
    public function get(string $key): mixed { return $this->mc->mcGet($key) ?: null; }
    public function set(string $key, mixed $value, int $ttl = 0): bool { return $this->mc->mcSet($key, $value, $ttl); }
    public function delete(string $key): bool { return $this->mc->mcDelete($key); }
    public function clear(): bool { $this->mc->mcFlush(); return true; }
    public function keys(): array { return $this->mc->mcGetAllKeys(); }
}

// 文件缓存
class FileCacheAdapter implements UnifiedCache {
    private array $store = [];
    public function get(string $key): mixed { return $this->store[$key] ?? null; }
    public function set(string $key, mixed $value, int $ttl = 0): bool { $this->store[$key] = $value; return true; }
    public function delete(string $key): bool { unset($this->store[$key]); return true; }
    public function clear(): bool { $this->store = []; return true; }
    public function keys(): array { return array_keys($this->store); }
}

// 缓存管理器（统一接口）
class CacheManager {
    private array $adapters = [];
    private ?string $default = null;

    public function addAdapter(string $name, UnifiedCache $adapter, bool $default = false): self {
        $this->adapters[$name] = $adapter;
        if ($default || $this->default === null) $this->default = $name;
        return $this;
    }

    public function getCache(string $name = ''): UnifiedCache {
        $name = $name ?: $this->default;
        return $this->adapters[$name] ?? throw new RuntimeException("Unknown cache: $name");
    }

    public function get(string $key, string $cache = ''): mixed {
        return $this->getCache($cache)->get($key);
    }

    public function set(string $key, mixed $value, int $ttl = 0, string $cache = ''): bool {
        return $this->getCache($cache)->set($key, $value, $ttl);
    }
}

// 测试
$manager = new CacheManager();
$manager->addAdapter('redis', new RedisAdapter(), true);
$manager->addAdapter('memcached', new MemcachedAdapter());
$manager->addAdapter('file', new FileCacheAdapter());

// 使用不同后端
$manager->set('user:1', ['name' => 'Alice'], 3600, 'redis');
$manager->set('user:2', ['name' => 'Bob'], 3600, 'memcached');
$manager->set('user:3', ['name' => 'Charlie'], 3600, 'file');

echo "Redis user:1: " . json_encode($manager->get('user:1', 'redis')) . "\n";
echo "Memcached user:2: " . json_encode($manager->get('user:2', 'memcached')) . "\n";
echo "File user:3: " . json_encode($manager->get('user:3', 'file')) . "\n";

// 默认后端
$manager->set('default_key', 'default_value');
echo "Default: " . $manager->get('default_key') . "\n";

// 直接操作适配器
$redis = $manager->getCache('redis');
$redis->set('a', 1);
$redis->set('b', 2);
$redis->set('c', 3);
echo "Redis keys: " . implode(', ', $redis->keys()) . "\n";
$redis->delete('b');
echo "After delete b: " . implode(', ', $redis->keys()) . "\n";

// 跨后端对比
echo "\n--- Cross-backend test ---\n";
foreach (['redis', 'memcached', 'file'] as $name) {
    $cache = $manager->getCache($name);
    $cache->set('test_key', "value_for_$name");
    echo "  $name: get='{$cache->get('test_key')}', keys=" . count($cache->keys()) . "\n";
    $cache->clear();
    echo "  $name after clear: keys=" . count($cache->keys()) . "\n";
}

echo "=== f037 Done ===\n";
