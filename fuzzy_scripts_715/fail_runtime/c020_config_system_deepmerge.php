<?php
// 极度混搭: 配置系统 + 类型推导 + 环境覆盖 + 深度合并 + 序列化
echo "=== c020: ConfigSystem + TypeCoerce + DeepMerge + Serialization ===\n\n";

class ConfigSchema {
    private array $rules = [];

    public function define(string $key, string $type, mixed $default = null, ?array $enum = null): self {
        $this->rules[$key] = [
            'type' => $type,
            'default' => $default,
            'enum' => $enum,
        ];
        return $this;
    }

    public function validate(mixed $value, string $type): bool {
        return match($type) {
            'string' => is_string($value),
            'int' => is_int($value),
            'float' => is_float($value) || is_int($value),
            'bool' => is_bool($value),
            'array' => is_array($value),
            'mixed' => true,
            default => true,
        };
    }

    public function coerce(mixed $value, string $type): mixed {
        return match($type) {
            'string' => (string)$value,
            'int' => (int)$value,
            'float' => (float)$value,
            'bool' => (bool)$value,
            'array' => is_array($value) ? $value : [$value],
            'mixed' => $value,
            default => $value,
        };
    }

    public function getRules(): array {
        return $this->rules;
    }
}

class Config {
    private array $data;
    private ConfigSchema $schema;
    private array $envOverrides = [];

    public function __construct(array $data = [], ?ConfigSchema $schema = null) {
        $this->schema = $schema ?? new ConfigSchema();
        $this->data = $data;
    }

    public function set(string $key, mixed $value): self {
        $parts = explode('.', $key);
        $current = &$this->data;
        foreach ($parts as $i => $part) {
            if ($i === count($parts) - 1) {
                $current[$part] = $value;
            } else {
                if (!isset($current[$part]) || !is_array($current[$part])) {
                    $current[$part] = [];
                }
                $current = &$current[$part];
            }
        }
        return $this;
    }

    public function get(string $key, mixed $default = null): mixed {
        $parts = explode('.', $key);
        $current = $this->data;
        foreach ($parts as $part) {
            if (!is_array($current) || !array_key_exists($part, $current)) {
                return $this->envOverrides[$key] ?? $default;
            }
            $current = $current[$part];
        }
        return $this->envOverrides[$key] ?? $current;
    }

    public function has(string $key): bool {
        $parts = explode('.', $key);
        $current = $this->data;
        foreach ($parts as $part) {
            if (!is_array($current) || !array_key_exists($part, $current)) {
                return isset($this->envOverrides[$key]);
            }
            $current = $current[$part];
        }
        return true;
    }

    public function setEnvOverride(string $key, mixed $value): self {
        $this->envOverrides[$key] = $value;
        return $this;
    }

    public static function deepMerge(array $base, array $override): array {
        $result = $base;
        foreach ($override as $key => $value) {
            if (is_array($value) && isset($result[$key]) && is_array($result[$key])) {
                $result[$key] = self::deepMerge($result[$key], $value);
            } else {
                $result[$key] = $value;
            }
        }
        return $result;
    }

    public function merge(array $override): self {
        $this->data = self::deepMerge($this->data, $override);
        return $this;
    }

    public function flatten(string $prefix = ''): array {
        return $this->flattenArray($this->data, $prefix);
    }

    private function flattenArray(array $arr, string $prefix): array {
        $result = [];
        foreach ($arr as $key => $value) {
            $fullKey = $prefix === '' ? $key : "$prefix.$key";
            if (is_array($value) && !empty($value)) {
                $result = array_merge($result, $this->flattenArray($value, $fullKey));
            } else {
                $result[$fullKey] = $value;
            }
        }
        return $result;
    }

    public function all(): array {
        return $this->data;
    }

    public function toJson(): string {
        return json_encode($this->data, JSON_PRETTY_PRINT);
    }

    public static function fromJson(string $json): self {
        $data = json_decode($json, true) ?? [];
        return new self($data);
    }
}

// === 测试 ===

echo "--- Schema Definition ---\n";
$schema = new ConfigSchema();
$schema->define('app.name', 'string', 'MyApp')
    ->define('app.version', 'string', '1.0.0')
    ->define('app.debug', 'bool', false)
    ->define('database.host', 'string', 'localhost')
    ->define('database.port', 'int', 3306)
    ->define('database.pool_size', 'int', 10)
    ->define('cache.enabled', 'bool', true)
    ->define('cache.ttl', 'int', 3600);

echo "Schema rules: " . count($schema->getRules()) . "\n";

echo "\n--- Config Creation ---\n";
$config = new Config([
    'app' => [
        'name' => 'TestApp',
        'version' => '2.0.0',
        'debug' => true,
    ],
    'database' => [
        'host' => 'db.example.com',
        'port' => 5432,
    ],
    'cache' => [
        'enabled' => true,
        'ttl' => 1800,
    ],
]);

echo "app.name: " . $config->get('app.name') . "\n";
echo "app.version: " . $config->get('app.version') . "\n";
echo "app.debug: " . var_export($config->get('app.debug'), true) . "\n";
echo "database.host: " . $config->get('database.host') . "\n";
echo "database.port: " . $config->get('database.port') . "\n";

echo "\n--- Nested Set ---\n";
$config->set('database.pool_size', 20);
$config->set('logging.level', 'debug');
$config->set('logging.format', 'json');
$config->set('feature.flags.new_ui', true);

echo "database.pool_size: " . $config->get('database.pool_size') . "\n";
echo "logging.level: " . $config->get('logging.level') . "\n";
echo "feature.flags.new_ui: " . var_export($config->get('feature.flags.new_ui'), true) . "\n";

echo "\n--- Default Values ---\n";
echo "nonexistent.key (default): " . $config->get('nonexistent.key', 'fallback') . "\n";
echo "has(app.name): " . var_export($config->has('app.name'), true) . "\n";
echo "has(nonexistent): " . var_export($config->has('nonexistent'), true) . "\n";

echo "\n--- Env Overrides ---\n";
$config->setEnvOverride('database.host', 'override.example.com');
$config->setEnvOverride('app.debug', false);
echo "database.host (override): " . $config->get('database.host') . "\n";
echo "app.debug (override): " . var_export($config->get('app.debug'), true) . "\n";

echo "\n--- Deep Merge ---\n";
$base = [
    'app' => ['name' => 'Base', 'debug' => false],
    'db' => ['host' => 'localhost', 'port' => 3306],
    'cache' => ['ttl' => 3600],
];
$override = [
    'app' => ['debug' => true, 'version' => '2.0'],
    'db' => ['host' => 'remote'],
    'logging' => ['level' => 'info'],
];
$merged = Config::deepMerge($base, $override);
echo "Merged: " . json_encode($merged) . "\n";

echo "\n--- Flatten ---\n";
$flat = $config->flatten();
ksort($flat);
foreach (array_slice($flat, 0, 10, true) as $k => $v) {
    echo "  $k = " . var_export($v, true) . "\n";
}
echo "  ... (" . count($flat) . " total keys)\n";

echo "\n--- JSON Serialization ---\n";
$json = $config->toJson();
echo "JSON length: " . strlen($json) . "\n";
$config2 = Config::fromJson($json);
echo "Roundtrip app.name: " . $config2->get('app.name') . "\n";
echo "Roundtrip cache.ttl: " . $config2->get('cache.ttl') . "\n";

echo "\n--- Type Coercion ---\n";
echo "String to int: " . $schema->coerce("42", 'int') . "\n";
echo "Int to string: " . $schema->coerce(42, 'string') . "\n";
echo "String to bool: " . var_export($schema->coerce("1", 'bool'), true) . "\n";
echo "Int to array: " . json_encode($schema->coerce(42, 'array')) . "\n";

echo "\n=== c020 Done ===\n";
