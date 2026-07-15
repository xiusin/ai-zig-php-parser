<?php
// 极度混搭: 插件架构 + 钩子系统 + 扩展点 + 生命周期 + 沙箱隔离
echo "=== c026: Plugin Architecture + Hooks + Extensions + Lifecycle ===\n\n";

interface PluginInterface {
    public function getName(): string;
    public function getVersion(): string;
    public function onLoad(PluginManager $manager): void;
    public function onUnload(): void;
    public function getHooks(): array;
}

class PluginManager {
    private array $plugins = [];
    private array $hooks = [];
    private array $context = [];
    private bool $loaded = false;

    public function registerPlugin(PluginInterface $plugin): bool {
        $name = $plugin->getName();
        if (isset($this->plugins[$name])) {
            return false;
        }
        $this->plugins[$name] = ['instance' => $plugin, 'active' => false];
        return true;
    }

    public function loadAll(): void {
        foreach ($this->plugins as $name => &$info) {
            if (!$info['active']) {
                $info['instance']->onLoad($this);
                $info['active'] = true;
            }
        }
        $this->loaded = true;
    }

    public function unloadAll(): void {
        foreach ($this->plugins as $name => &$info) {
            if ($info['active']) {
                $info['instance']->onUnload();
                $info['active'] = false;
            }
        }
    }

    public function registerHook(string $hook, callable $callback, int $priority = 0): void {
        if (!isset($this->hooks[$hook])) {
            $this->hooks[$hook] = [];
        }
        $this->hooks[$hook][] = [
            'callback' => $callback,
            'priority' => $priority,
            'plugin' => '',
        ];
        usort($this->hooks[$hook], fn($a, $b) => $b['priority'] <=> $a['priority']);
    }

    public function triggerHook(string $hook, array $args = []): array {
        $results = [];
        foreach ($this->hooks[$hook] ?? [] as $entry) {
            $results[] = ($entry['callback'])($args, $this);
        }
        return $results;
    }

    public function setContext(string $key, mixed $value): void {
        $this->context[$key] = $value;
    }

    public function getContext(string $key, mixed $default = null): mixed {
        return $this->context[$key] ?? $default;
    }

    public function getPluginNames(): array {
        return array_keys($this->plugins);
    }

    public function isPluginActive(string $name): bool {
        return $this->plugins[$name]['active'] ?? false;
    }

    public function getHookCount(string $hook): int {
        return count($this->hooks[$hook] ?? []);
    }
}

// --- 插件实现 ---

class LoggerPlugin implements PluginInterface {
    private array $logBuffer = [];

    public function getName(): string { return 'logger'; }
    public function getVersion(): string { return '1.0.0'; }

    public function onLoad(PluginManager $manager): void {
        $manager->setContext('log.enabled', true);
        $manager->registerHook('log.write', function($args) {
            $level = $args['level'] ?? 'info';
            $msg = $args['message'] ?? '';
            $this->logBuffer[] = "[$level] $msg";
            return true;
        });
    }

    public function onUnload(): void {
        $this->logBuffer = [];
    }

    public function getHooks(): array {
        return ['log.write'];
    }

    public function getLogs(): array {
        return $this->logBuffer;
    }
}

class CachePlugin implements PluginInterface {
    private array $cache = [];
    private int $hits = 0;
    private int $misses = 0;

    public function getName(): string { return 'cache'; }
    public function getVersion(): string { return '2.1.0'; }

    public function onLoad(PluginManager $manager): void {
        $manager->registerHook('cache.get', function($args) {
            $key = $args['key'] ?? '';
            if (isset($this->cache[$key])) {
                $this->hits++;
                return $this->cache[$key];
            }
            $this->misses++;
            return null;
        });

        $manager->registerHook('cache.set', function($args) {
            $key = $args['key'] ?? '';
            $value = $args['value'] ?? null;
            $this->cache[$key] = $value;
            return true;
        }, 10);

        $manager->registerHook('cache.stats', function($args) {
            return ['hits' => $this->hits, 'misses' => $this->misses, 'size' => count($this->cache)];
        });
    }

    public function onUnload(): void {
        $this->cache = [];
        $this->hits = 0;
        $this->misses = 0;
    }

    public function getHooks(): array {
        return ['cache.get', 'cache.set', 'cache.stats'];
    }
}

class MetricsPlugin implements PluginInterface {
    private array $counters = [];
    private array $timers = [];

    public function getName(): string { return 'metrics'; }
    public function getVersion(): string { return '0.5.0'; }

    public function onLoad(PluginManager $manager): void {
        $manager->registerHook('metrics.increment', function($args) {
            $name = $args['name'] ?? 'default';
            if (!isset($this->counters[$name])) $this->counters[$name] = 0;
            $this->counters[$name]++;
            return $this->counters[$name];
        });

        $manager->registerHook('metrics.report', function($args) {
            return $this->counters;
        });
    }

    public function onUnload(): void {
        $this->counters = [];
    }

    public function getHooks(): array {
        return ['metrics.increment', 'metrics.report'];
    }
}

// === 测试 ===

echo "--- Plugin Registration ---\n";
$pm = new PluginManager();
$logger = new LoggerPlugin();
$cache = new CachePlugin();
$metrics = new MetricsPlugin();

$pm->registerPlugin($logger);
$pm->registerPlugin($cache);
$pm->registerPlugin($metrics);

echo "Registered: " . implode(", ", $pm->getPluginNames()) . "\n";
echo "Logger active: " . var_export($pm->isPluginActive('logger'), true) . "\n";

echo "\n--- Load All Plugins ---\n";
$pm->loadAll();
echo "Logger active: " . var_export($pm->isPluginActive('logger'), true) . "\n";
echo "Cache active: " . var_export($pm->isPluginActive('cache'), true) . "\n";
echo "Metrics active: " . var_export($pm->isPluginActive('metrics'), true) . "\n";

echo "log.write hooks: " . $pm->getHookCount('log.write') . "\n";
echo "cache.get hooks: " . $pm->getHookCount('cache.get') . "\n";
echo "metrics.increment hooks: " . $pm->getHookCount('metrics.increment') . "\n";

echo "\n--- Trigger Hooks ---\n";
$pm->triggerHook('log.write', ['level' => 'info', 'message' => 'System started']);
$pm->triggerHook('log.write', ['level' => 'warning', 'message' => 'Low memory']);
$pm->triggerHook('cache.set', ['key' => 'user:1', 'value' => ['name' => 'Alice']]);
$pm->triggerHook('cache.set', ['key' => 'user:2', 'value' => ['name' => 'Bob']]);

$getResult = $pm->triggerHook('cache.get', ['key' => 'user:1']);
echo "Cache get user:1: " . json_encode($getResult[0] ?? null) . "\n";

$getResult2 = $pm->triggerHook('cache.get', ['key' => 'user:999']);
echo "Cache get user:999: " . json_encode($getResult2[0] ?? null) . "\n";

$pm->triggerHook('metrics.increment', ['name' => 'requests']);
$pm->triggerHook('metrics.increment', ['name' => 'requests']);
$pm->triggerHook('metrics.increment', ['name' => 'errors']);

$report = $pm->triggerHook('metrics.report');
echo "Metrics report: " . json_encode($report[0] ?? []) . "\n";

$stats = $pm->triggerHook('cache.stats');
echo "Cache stats: " . json_encode($stats[0] ?? []) . "\n";

echo "\n--- Logger Output ---\n";
foreach ($logger->getLogs() as $log) {
    echo "  $log\n";
}

echo "\n--- Context Sharing ---\n";
$pm->setContext('app.version', '3.0.0');
echo "app.version: " . $pm->getContext('app.version') . "\n";
echo "log.enabled: " . var_export($pm->getContext('log.enabled'), true) . "\n";
echo "nonexistent: " . var_export($pm->getContext('nonexistent', 'default'), true) . "\n";

echo "\n--- Unload ---\n";
$pm->unloadAll();
echo "Logger active after unload: " . var_export($pm->isPluginActive('logger'), true) . "\n";

echo "\n=== c026 Done ===\n";
