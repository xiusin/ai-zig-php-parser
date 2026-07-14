<?php
// 配置系统：支持嵌套配置、点号路径访问、默认值、环境变量覆盖

class Config {
    private static array $items = [];

    public static function load(array $config): void {
        self::$items = $config;
    }

    public static function get(string $key, mixed $default = null): mixed {
        $keys = explode('.', $key);
        $current = self::$items;
        foreach ($keys as $k) {
            if (!is_array($current) || !isset($current[$k])) {
                return $default;
            }
            $current = $current[$k];
        }
        return $current;
    }

    public static function set(string $key, mixed $value): void {
        $keys = explode('.', $key);
        $current = &self::$items;
        foreach ($keys as $i => $k) {
            if ($i === count($keys) - 1) {
                $current[$k] = $value;
            } else {
                if (!isset($current[$k]) || !is_array($current[$k])) {
                    $current[$k] = [];
                }
                $current = &$current[$k];
            }
        }
    }

    public static function has(string $key): bool {
        return self::get($key) !== null;
    }
}

// 加载初始配置
Config::load([
    'app' => [
        'name' => 'MyApp',
        'debug' => true,
        'version' => '1.0.0',
    ],
    'database' => [
        'host' => 'localhost',
        'port' => 3306,
        'name' => 'mydb',
    ],
    'cache' => [
        'driver' => 'redis',
        'redis' => [
            'host' => '127.0.0.1',
            'port' => 6379,
        ],
    ],
]);

// 测试读取配置
echo "app_name: " . Config::get('app.name') . "\n";
echo "app_debug: " . (Config::get('app.debug') ? 'true' : 'false') . "\n";
echo "db_host: " . Config::get('database.host') . "\n";
echo "cache_redis_host: " . Config::get('cache.redis.host') . "\n";

// 测试默认值
echo "missing_with_default: " . Config::get('app.missing', 'default_val') . "\n";

// 测试 has
echo "has_app: " . (Config::has('app.name') ? 'true' : 'false') . "\n";
echo "has_missing: " . (Config::has('app.missing') ? 'true' : 'false') . "\n";

// 测试动态设置
Config::set('app.new_key', 'new_value');
echo "new_key: " . Config::get('app.new_key') . "\n";

Config::set('cache.redis.password', 'secret');
echo "redis_password: " . Config::get('cache.redis.password') . "\n";

// 测试覆盖
Config::set('app.debug', false);
echo "app_debug_updated: " . (Config::get('app.debug') ? 'true' : 'false') . "\n";

// 测试多层嵌套设置
Config::set('services.payment.gateway.url', 'https://pay.example.com');
echo "payment_url: " . Config::get('services.payment.gateway.url') . "\n";

echo "config_count: " . count(Config::get('app')) . "\n";
