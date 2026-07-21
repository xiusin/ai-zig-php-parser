<?php
// 极度混搭: 配置中心 + 热更新 + 环境隔离 + 版本管理 + 回滚
echo "=== f086: Config Center + Hot Reload + Version ===\n";

class ConfigVersion {
    public function __construct(
        public int $version,
        public array $data,
        public int $timestamp,
        public string $author
    ) {}
}

class ConfigCenter {
    private array $versions = [];
    private int $currentVersion = 0;
    private array $listeners = [];
    private array $envOverrides = [];

    public function __construct(private string $env = 'production') {
        $this->loadDefaults();
    }

    private function loadDefaults(): void {
        $defaults = [
            'production' => [
                'db' => ['host' => 'prod-db', 'port' => 5432, 'pool' => 20],
                'cache' => ['ttl' => 3600, 'driver' => 'redis'],
                'log' => ['level' => 'warning', 'file' => '/var/log/app.log'],
                'feature_flags' => ['new_ui' => false, 'beta' => false],
            ],
            'staging' => [
                'db' => ['host' => 'staging-db', 'port' => 5432, 'pool' => 10],
                'cache' => ['ttl' => 1800, 'driver' => 'redis'],
                'log' => ['level' => 'info', 'file' => '/var/log/staging.log'],
                'feature_flags' => ['new_ui' => true, 'beta' => false],
            ],
            'development' => [
                'db' => ['host' => 'localhost', 'port' => 5432, 'pool' => 5],
                'cache' => ['ttl' => 60, 'driver' => 'array'],
                'log' => ['level' => 'debug', 'file' => 'app.log'],
                'feature_flags' => ['new_ui' => true, 'beta' => true],
            ],
        ];
        $config = $defaults[$this->env] ?? $defaults['production'];
        $this->saveVersion($config, 'system', 'Initial config');
    }

    public function saveVersion(array $data, string $author, string $note = ''): int {
        $this->currentVersion++;
        $version = new ConfigVersion($this->currentVersion, $data, time(), $author);
        $this->versions[$this->currentVersion] = $version;
        $this->notifyListeners($data, $note);
        return $this->currentVersion;
    }

    public function get(string $path = ''): mixed {
        $data = $this->versions[$this->currentVersion]->data;
        // 应用环境覆盖
        foreach ($this->envOverrides as $key => $value) {
            $this->setNestedValue($data, $key, $value);
        }
        if ($path === '') return $data;
        $parts = explode('.', $path);
        $current = $data;
        foreach ($parts as $part) {
            if (!is_array($current) || !array_key_exists($part, $current)) return null;
            $current = $current[$part];
        }
        return $current;
    }

    private function setNestedValue(array &$data, string $path, mixed $value): void {
        $parts = explode('.', $path);
        $current = &$data;
        foreach ($parts as $i => $part) {
            if ($i === count($parts) - 1) { $current[$part] = $value; return; }
            if (!isset($current[$part])) $current[$part] = [];
            $current = &$current[$part];
        }
    }

    public function update(string $path, mixed $value, string $author = 'admin'): int {
        $data = $this->versions[$this->currentVersion]->data;
        $this->setNestedValue($data, $path, $value);
        return $this->saveVersion($data, $author, "Updated $path");
    }

    public function rollback(int $version): bool {
        if (!isset($this->versions[$version])) return false;
        $this->currentVersion = $version;
        $this->notifyListeners($this->versions[$version]->data, "Rollback to v$version");
        return true;
    }

    public function setEnvOverride(string $key, mixed $value): void {
        $this->envOverrides[$key] = $value;
    }

    public function onChange(string $key, callable $callback): void {
        $this->listeners[] = ['key' => $key, 'callback' => $callback];
    }

    private function notifyListeners(array $data, string $note): void {
        foreach ($this->listeners as $listener) {
            $value = $this->getNestedValue($data, $listener['key']);
            ($listener['callback'])($value, $note);
        }
    }

    private function getNestedValue(array $data, string $path): mixed {
        $parts = explode('.', $path);
        $current = $data;
        foreach ($parts as $part) {
            if (!is_array($current) || !array_key_exists($part, $current)) return null;
            $current = $current[$part];
        }
        return $current;
    }

    public function getVersionHistory(): array {
        return array_map(fn($v) => [
            'version' => $v->version, 'author' => $v->author,
            'timestamp' => date('Y-m-d H:i:s', $v->timestamp),
            'keys' => count($v->data, COUNT_RECURSIVE),
        ], $this->versions);
    }

    public function getCurrentVersion(): int { return $this->currentVersion; }
    public function getEnv(): string { return $this->env; }
}

// 测试
echo "--- Config Center (Development) ---\n";
$cc = new ConfigCenter('development');
echo "Env: " . $cc->getEnv() . "\n";
echo "DB host: " . $cc->get('db.host') . "\n";
echo "Cache TTL: " . $cc->get('cache.ttl') . "\n";
echo "Log level: " . $cc->get('log.level') . "\n";
echo "Full config: " . json_encode($cc->get()) . "\n";

echo "\n--- Hot Update ---\n";
$cc->onChange('cache.ttl', function($value, $note) {
    echo "  [Listener] cache.ttl changed to $value ($note)\n";
});
$cc->onChange('db.host', function($value, $note) {
    echo "  [Listener] db.host changed to $value ($note)\n";
});

$cc->update('cache.ttl', 120, 'developer');
$cc->update('db.host', 'new-dev-db', 'developer');
$cc->update('feature_flags.beta', false, 'developer');

echo "\n--- Version History ---\n";
foreach ($cc->getVersionHistory() as $v) {
    echo "  v{$v['version']} by {$v['author']} at {$v['timestamp']} ({$v['keys']} keys)\n";
}

echo "\n--- Rollback ---\n";
echo "Current version: " . $cc->getCurrentVersion() . "\n";
echo "cache.ttl before rollback: " . $cc->get('cache.ttl') . "\n";
$cc->rollback(1);
echo "After rollback to v1, cache.ttl: " . $cc->get('cache.ttl') . "\n";

echo "\n--- Environment Isolation ---\n";
$prod = new ConfigCenter('production');
$staging = new ConfigCenter('staging');
echo "Production DB host: " . $prod->get('db.host') . "\n";
echo "Staging DB host: " . $staging->get('db.host') . "\n";
echo "Production log level: " . $prod->get('log.level') . "\n";
echo "Staging log level: " . $staging->get('log.level') . "\n";

echo "\n--- Env Overrides ---\n";
$prod->setEnvOverride('db.host', 'override-db.example.com');
$prod->setEnvOverride('cache.ttl', 999);
echo "Overridden DB host: " . $prod->get('db.host') . "\n";
echo "Overridden cache.ttl: " . $prod->get('cache.ttl') . "\n";

echo "=== f086 Done ===\n";
