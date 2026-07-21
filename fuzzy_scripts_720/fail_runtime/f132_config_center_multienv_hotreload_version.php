<?php
// 极度混搭: 配置中心 + 多环境 + 热更新 + 版本管理 + 合并
echo "=== f132: Config Center + MultiEnv + HotReload + Version ===\n";

class ConfigSource {
    public function __construct(public string $name, public array $data, public int $priority = 0) {}
}

class ConfigManager {
    private array $sources = [];
    private array $config = [];
    private array $history = [];
    private int $version = 0;
    private array $watchers = [];
    private array $envOverrides = [];

    public function addSource(ConfigSource $source): void {
        $this->sources[$source->name] = $source;
        $this->rebuild();
    }

    public function setEnvironment(string $env, array $overrides): void {
        $this->envOverrides[$env] = $overrides;
        $this->rebuild();
    }

    private function rebuild(): void {
        $oldConfig = $this->config;
        // 按优先级排序 (低→高)
        $sorted = $this->sources;
        usort($sorted, fn($a, $b) => $a->priority <=> $b->priority);
        $this->config = [];
        foreach ($sorted as $source) $this->config = $this->deepMerge($this->config, $source->data);
        // 应用环境覆盖
        $env = $this->config['environment'] ?? 'production';
        if (isset($this->envOverrides[$env])) {
            $this->config = $this->deepMerge($this->config, $this->envOverrides[$env]);
        }
        $this->version++;
        $this->history[] = ['version' => $this->version, 'config' => $this->config, 'timestamp' => microtime(true)];
        // 通知 watchers
        foreach ($this->watchers as $key => $watchers) {
            $oldVal = $this->getNestedValue($oldConfig, $key);
            $newVal = $this->getNestedValue($this->config, $key);
            if ($oldVal !== $newVal) {
                foreach ($watchers as $callback) $callback($newVal, $oldVal, $key);
            }
        }
    }

    private function deepMerge(array $base, array $override): array {
        foreach ($override as $key => $value) {
            if (is_array($value) && isset($base[$key]) && is_array($base[$key])) {
                $base[$key] = $this->deepMerge($base[$key], $value);
            } else {
                $base[$key] = $value;
            }
        }
        return $base;
    }

    public function get(string $key, mixed $default = null): mixed {
        return $this->getNestedValue($this->config, $key) ?? $default;
    }

    private function getNestedValue(array $arr, string $key): mixed {
        $keys = explode('.', $key);
        $current = $arr;
        foreach ($keys as $k) {
            if (!is_array($current) || !array_key_exists($k, $current)) return null;
            $current = $current[$k];
        }
        return $current;
    }

    public function set(string $key, mixed $value): void {
        $keys = explode('.', $key);
        $newConfig = $this->config;
        $current = &$newConfig;
        foreach ($keys as $i => $k) {
            if ($i === count($keys) - 1) { $current[$k] = $value; break; }
            if (!isset($current[$k]) || !is_array($current[$k])) $current[$k] = [];
            $current = &$current[$k];
        }
        $this->config = $newConfig;
        $this->version++;
        $this->history[] = ['version' => $this->version, 'config' => $this->config, 'timestamp' => microtime(true)];
    }

    public function watch(string $key, callable $callback): void {
        if (!isset($this->watchers[$key])) $this->watchers[$key] = [];
        $this->watchers[$key][] = $callback;
    }

    public function getVersion(): int { return $this->version; }
    public function getAll(): array { return $this->config; }
    public function getHistory(): array { return $this->history; }

    public function rollback(int $version): bool {
        foreach (array_reverse($this->history) as $entry) {
            if ($entry['version'] === $version) {
                $this->config = $entry['config'];
                $this->version++;
                $this->history[] = ['version' => $this->version, 'config' => $this->config, 'timestamp' => microtime(true)];
                return true;
            }
        }
        return false;
    }

    public function diff(int $v1, int $v2): array {
        $c1 = []; $c2 = [];
        foreach ($this->history as $entry) {
            if ($entry['version'] === $v1) $c1 = $entry['config'];
            if ($entry['version'] === $v2) $c2 = $entry['config'];
        }
        return $this->computeDiff($c1, $c2);
    }

    private function computeDiff(array $a, array $b, string $prefix = ''): array {
        $diff = [];
        foreach ($a as $key => $val) {
            $fullKey = $prefix ? "$prefix.$key" : $key;
            if (!array_key_exists($key, $b)) { $diff[$fullKey] = ['old' => $val, 'new' => null]; continue; }
            if (is_array($val) && is_array($b[$key])) { $diff = array_merge($diff, $this->computeDiff($val, $b[$key], $fullKey)); }
            elseif ($val !== $b[$key]) { $diff[$fullKey] = ['old' => $val, 'new' => $b[$key]]; }
        }
        foreach ($b as $key => $val) {
            $fullKey = $prefix ? "$prefix.$key" : $key;
            if (!array_key_exists($key, $a)) $diff[$fullKey] = ['old' => null, 'new' => $val];
        }
        return $diff;
    }
}

// 测试
echo "--- Setup Config Sources ---\n";
$cm = new ConfigManager();

$defaults = new ConfigSource('defaults', [
    'app' => ['name' => 'MyApp', 'version' => '1.0.0', 'debug' => false],
    'database' => ['host' => 'localhost', 'port' => 3306, 'name' => 'mydb'],
    'cache' => ['driver' => 'file', 'ttl' => 3600],
    'logging' => ['level' => 'info', 'file' => '/var/log/app.log'],
], 0);
$cm->addSource($defaults);

$envConfig = new ConfigSource('env', [
    'app' => ['debug' => true, 'version' => '1.1.0'],
    'database' => ['host' => 'db.production.local', 'port' => 5432],
    'cache' => ['driver' => 'redis', 'redis' => ['host' => 'redis.local', 'port' => 6379]],
], 10);
$cm->addSource($envConfig);

echo "Version: {$cm->getVersion()}\n";
echo "app.name: " . $cm->get('app.name') . "\n";
echo "app.debug: " . var_export($cm->get('app.debug'), true) . "\n";
echo "database.host: " . $cm->get('database.host') . "\n";
echo "cache.driver: " . $cm->get('cache.driver') . "\n";
echo "cache.redis.host: " . $cm->get('cache.redis.host') . "\n";

echo "\n--- Environment Overrides ---\n";
$cm->setEnvironment('production', [
    'app' => ['debug' => false],
    'database' => ['host' => 'prod-db.example.com'],
]);
$cm->set('environment', 'production');
echo "After production override:\n";
echo "  app.debug: " . var_export($cm->get('app.debug'), true) . "\n";
echo "  database.host: " . $cm->get('database.host') . "\n";

$cm->set('environment', 'development');
$cm->setEnvironment('development', ['app' => ['debug' => true]]);
echo "After development override:\n";
echo "  app.debug: " . var_export($cm->get('app.debug'), true) . "\n";

echo "\n--- Hot Reload Watchers ---\n";
$changeLog = [];
$cm->watch('app.debug', function($new, $old, $key) use (&$changeLog) {
    $changeLog[] = "$key: $old → $new";
});
$cm->watch('cache.driver', function($new, $old, $key) use (&$changeLog) {
    $changeLog[] = "$key: $old → $new";
});

$cm->set('app.debug', false);
$cm->set('cache.driver', 'memcached');
echo "Watch notifications:\n";
foreach ($changeLog as $log) echo "  $log\n";

echo "\n--- Version History ---\n";
echo "Current version: {$cm->getVersion()}\n";
$cm->set('app.version', '2.0.0');
$cm->set('cache.ttl', 7200);
echo "After changes: version={$cm->getVersion()}\n";
echo "History entries: " . count($cm->getHistory()) . "\n";

echo "\n--- Rollback ---\n";
$targetVersion = 1;
$rolledBack = $cm->rollback($targetVersion);
echo "Rollback to v$targetVersion: " . var_export($rolledBack, true) . "\n";
echo "Current version after rollback: {$cm->getVersion()}\n";
echo "app.debug after rollback: " . var_export($cm->get('app.debug'), true) . "\n";

echo "\n--- Config Diff ---\n";
// 重新设置以产生版本差异
$cm->set('app.name', 'NewApp');
$cm->set('database.port', 3307);
$v1 = $cm->getVersion() - 2;
$v2 = $cm->getVersion();
$diff = $cm->diff($v1, $v2);
echo "Diff between v$v1 and v$v2:\n";
foreach ($diff as $key => $change) {
    echo "  $key: {$change['old']} → {$change['new']}\n";
}

echo "\n--- Multi-environment Config ---\n";
$multiEnv = new ConfigManager();
$multiEnv->addSource(new ConfigSource('base', [
    'app' => ['name' => 'API', 'timeout' => 30],
    'db' => ['pool' => 10, 'timeout' => 5],
], 0));
$multiEnv->setEnvironment('dev', ['app' => ['timeout' => 60], 'db' => ['pool' => 2]]);
$multiEnv->setEnvironment('staging', ['app' => ['timeout' => 45], 'db' => ['pool' => 5]]);
$multiEnv->setEnvironment('prod', ['app' => ['timeout' => 15], 'db' => ['pool' => 20]]);

foreach (['dev', 'staging', 'prod'] as $env) {
    $multiEnv->set('environment', $env);
    echo "  $env: timeout=" . $multiEnv->get('app.timeout') . " pool=" . $multiEnv->get('db.pool') . "\n";
}

echo "=== f132 Done ===\n";
