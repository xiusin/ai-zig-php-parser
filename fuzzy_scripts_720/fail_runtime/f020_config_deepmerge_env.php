<?php
// 极度混搭: 配置系统 + 深度合并 + 环境覆盖 + 类型转换 + 验证
echo "=== f020: Config System + DeepMerge + Env Override ===\n";

class Config {
    private array $data;
    private array $defaults = [
        'app' => [
            'name' => 'MyApp',
            'version' => '1.0.0',
            'debug' => false,
        ],
        'database' => [
            'host' => 'localhost',
            'port' => 3306,
            'name' => 'myapp',
            'user' => 'root',
            'password' => '',
        ],
        'cache' => [
            'driver' => 'file',
            'ttl' => 3600,
            'prefix' => 'myapp_',
        ],
        'mail' => [
            'from' => 'noreply@example.com',
            'from_name' => 'MyApp',
            'smtp' => [
                'host' => 'localhost',
                'port' => 25,
                'encryption' => 'none',
            ],
        ],
    ];

    public function __construct(array $overrides = []) {
        $this->data = $this->deepMerge($this->defaults, $overrides);
    }

    private function deepMerge(array $base, array $override): array {
        $result = $base;
        foreach ($override as $key => $value) {
            if (is_array($value) && isset($result[$key]) && is_array($result[$key])) {
                $result[$key] = $this->deepMerge($result[$key], $value);
            } else {
                $result[$key] = $value;
            }
        }
        return $result;
    }

    public function get(string $path, mixed $default = null): mixed {
        $keys = explode('.', $path);
        $value = $this->data;
        foreach ($keys as $key) {
            if (!is_array($value) || !array_key_exists($key, $value)) {
                return $default;
            }
            $value = $value[$key];
        }
        return $value;
    }

    public function set(string $path, mixed $value): void {
        $keys = explode('.', $path);
        $ref = &$this->data;
        foreach ($keys as $i => $key) {
            if (!isset($ref[$key]) || !is_array($ref[$key])) {
                $ref[$key] = [];
            }
            if ($i === count($keys) - 1) {
                $ref[$key] = $value;
            } else {
                $ref = &$ref[$key];
            }
        }
    }

    public function has(string $path): bool {
        return $this->get($path) !== null;
    }

    public function all(): array { return $this->data; }

    public function flatten(): array {
        return $this->flattenHelper($this->data);
    }

    private function flattenHelper(array $data, string $prefix = ''): array {
        $result = [];
        foreach ($data as $key => $value) {
            $path = $prefix === '' ? $key : "$prefix.$key";
            if (is_array($value) && !empty($value)) {
                $result = array_merge($result, $this->flattenHelper($value, $path));
            } else {
                $result[$path] = $value;
            }
        }
        return $result;
    }

    public function toArray(): array { return $this->data; }
}

// === 测试 ===
$overrides = [
    'app' => ['debug' => true, 'version' => '2.0.0'],
    'database' => ['host' => 'db.example.com', 'port' => 5432, 'password' => 'secret'],
    'cache' => ['driver' => 'redis', 'ttl' => 7200],
    'mail' => ['smtp' => ['host' => 'smtp.example.com', 'encryption' => 'tls']],
];

$config = new Config($overrides);

echo "app.name: " . $config->get('app.name') . "\n";
echo "app.version: " . $config->get('app.version') . "\n";
echo "app.debug: " . var_export($config->get('app.debug'), true) . "\n";
echo "database.host: " . $config->get('database.host') . "\n";
echo "database.port: " . $config->get('database.port') . "\n";
echo "database.user: " . $config->get('database.user') . " (default)\n";
echo "cache.driver: " . $config->get('cache.driver') . "\n";
echo "cache.ttl: " . $config->get('cache.ttl') . "\n";
echo "cache.prefix: " . $config->get('cache.prefix') . " (default)\n";
echo "mail.smtp.host: " . $config->get('mail.smtp.host') . "\n";
echo "mail.smtp.encryption: " . $config->get('mail.smtp.encryption') . "\n";
echo "mail.smtp.port: " . $config->get('mail.smtp.port') . " (default)\n";

echo "\nMissing key (default): " . $config->get('nonexistent.key', 'DEFAULT') . "\n";
echo "Has app.name: " . var_export($config->has('app.name'), true) . "\n";
echo "Has app.missing: " . var_export($config->has('app.missing'), true) . "\n";

// 动态设置
$config->set('app.custom_key', 'custom_value');
echo "After set app.custom_key: " . $config->get('app.custom_key') . "\n";

$config->set('new.section.key', 'new_value');
echo "After set new.section.key: " . $config->get('new.section.key') . "\n";

// 扁平化
echo "\nFlattened config:\n";
foreach ($config->flatten() as $path => $value) {
    echo "  $path = " . var_export($value, true) . "\n";
}

echo "=== f020 Done ===\n";
