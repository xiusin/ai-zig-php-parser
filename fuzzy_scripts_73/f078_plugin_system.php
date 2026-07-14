<?php
// f078: 插件系统 (Plugin System)
echo "=== Plugin System ===\n\n";

interface PluginInterface {
    public function getName(): string;
    public function getVersion(): string;
    public function onEnable(): void;
    public function onDisable(): void;
    public function getHooks(): array;
}

interface HookHandler {
    public function execute(array $context): mixed;
}

class SimpleHandler implements HookHandler {
    private string $name;
    private \Closure $callback;

    public function __construct(string $name, callable $callback) {
        $this->name = $name;
        $this->callback = \Closure::fromCallable($callback);
    }

    public function execute(array $context): mixed {
        return ($this->callback)($context);
    }
}

class PluginManager {
    private array $plugins = [];
    private array $hooks = [];
    private array $enabled = [];

    public function register(PluginInterface $plugin): void {
        $name = $plugin->getName();
        $this->plugins[$name] = $plugin;
        echo "  Registered: $name v{$plugin->getVersion()}\n";
    }

    public function enable(string $name): bool {
        if (!isset($this->plugins[$name])) return false;
        if (isset($this->enabled[$name])) return true;

        $plugin = $this->plugins[$name];
        $plugin->onEnable();
        $this->enabled[$name] = true;

        foreach ($plugin->getHooks() as $hookName => $handler) {
            if (!isset($this->hooks[$hookName])) {
                $this->hooks[$hookName] = [];
            }
            $this->hooks[$hookName][] = ['plugin' => $name, 'handler' => $handler];
        }
        return true;
    }

    public function disable(string $name): bool {
        if (!isset($this->enabled[$name])) return false;
        $this->plugins[$name]->onDisable();
        unset($this->enabled[$name]);

        foreach ($this->hooks as $hookName => &$handlers) {
            $handlers = array_values(array_filter($handlers, fn($h) => $h['plugin'] !== $name));
        }
        return true;
    }

    public function trigger(string $hookName, array $context = []): array {
        $results = [];
        if (!isset($this->hooks[$hookName])) return $results;

        foreach ($this->hooks[$hookName] as $entry) {
            $results[] = $entry['handler']->execute($context);
        }
        return $results;
    }

    public function getEnabledPlugins(): array {
        return array_keys($this->enabled);
    }

    public function getRegisteredPlugins(): array {
        return array_keys($this->plugins);
    }
}

// 插件实现
class LoggerPlugin implements PluginInterface {
    private array $logs = [];

    public function getName(): string { return 'Logger'; }
    public function getVersion(): string { return '1.0.0'; }

    public function onEnable(): void {
        echo "  Logger plugin enabled\n";
    }

    public function onDisable(): void {
        echo "  Logger plugin disabled\n";
    }

    public function getHooks(): array {
        return [
            'before_request' => new SimpleHandler('log_before', function (array $ctx) {
                $this->logs[] = "BEFORE: {$ctx['path']}";
                return true;
            }),
            'after_request' => new SimpleHandler('log_after', function (array $ctx) {
                $this->logs[] = "AFTER: {$ctx['path']} status={$ctx['status']}";
                return true;
            }),
        ];
    }

    public function getLogs(): array {
        return $this->logs;
    }
}

class CachePlugin implements PluginInterface {
    private array $cache = [];
    private int $hits = 0;
    private int $misses = 0;

    public function getName(): string { return 'Cache'; }
    public function getVersion(): string { return '2.1.0'; }

    public function onEnable(): void {
        echo "  Cache plugin enabled\n";
    }

    public function onDisable(): void {
        echo "  Cache plugin disabled\n";
    }

    public function getHooks(): array {
        return [
            'before_request' => new SimpleHandler('cache_check', function (array $ctx) {
                $key = $ctx['path'];
                if (isset($this->cache[$key])) {
                    $this->hits++;
                    return ['cached' => true, 'data' => $this->cache[$key]];
                }
                $this->misses++;
                return ['cached' => false];
            }),
            'after_request' => new SimpleHandler('cache_store', function (array $ctx) {
                $this->cache[$ctx['path']] = $ctx['response'] ?? '';
                return true;
            }),
        ];
    }

    public function getStats(): array {
        return ['hits' => $this->hits, 'misses' => $this->misses, 'size' => count($this->cache)];
    }
}

class SecurityPlugin implements PluginInterface {
    private array $blocked = [];

    public function getName(): string { return 'Security'; }
    public function getVersion(): string { return '0.9.5'; }

    public function onEnable(): void {
        echo "  Security plugin enabled\n";
    }

    public function onDisable(): void {
        echo "  Security plugin disabled\n";
    }

    public function getHooks(): array {
        return [
            'before_request' => new SimpleHandler('security_check', function (array $ctx) {
                $path = $ctx['path'];
                if (str_contains($path, '../') || str_contains($path, 'etc/passwd')) {
                    $this->blocked[] = $path;
                    return ['blocked' => true];
                }
                return ['blocked' => false];
            }),
        ];
    }

    public function getBlocked(): array {
        return $this->blocked;
    }
}

// 测试
echo "--- Registration ---\n";
$manager = new PluginManager();
$logger = new LoggerPlugin();
$cache = new CachePlugin();
$security = new SecurityPlugin();

$manager->register($logger);
$manager->register($cache);
$manager->register($security);

echo "\n--- Enable ---\n";
$manager->enable('Logger');
$manager->enable('Cache');
$manager->enable('Security');

echo "\n--- Trigger Requests ---\n";
$paths = ['/api/users', '/api/users', '/api/items', '/etc/passwd', '/api/users'];
foreach ($paths as $path) {
    echo "  Request: $path\n";
    $beforeResults = $manager->trigger('before_request', ['path' => $path]);
    foreach ($beforeResults as $result) {
        if (isset($result['cached']) && $result['cached']) {
            echo "    Cache HIT\n";
        }
        if (isset($result['blocked']) && $result['blocked']) {
            echo "    Security BLOCKED\n";
        }
    }
    $manager->trigger('after_request', ['path' => $path, 'status' => 200, 'response' => 'data_' . $path]);
}

echo "\n--- Stats ---\n";
echo "Logger logs:\n";
foreach ($logger->getLogs() as $log) {
    echo "  $log\n";
}

echo "Cache stats:\n";
$stats = $cache->getStats();
echo "  hits: {$stats['hits']}, misses: {$stats['misses']}, size: {$stats['size']}\n";

echo "Security blocked:\n";
foreach ($security->getBlocked() as $blocked) {
    echo "  $blocked\n";
}

echo "\n--- Disable Cache ---\n";
$manager->disable('Cache');
echo "Enabled plugins: " . implode(', ', $manager->getEnabledPlugins()) . "\n";

echo "\n--- After Disable ---\n";
$manager->trigger('before_request', ['path' => '/api/users']);
echo "Cache stats after disable:\n";
$stats2 = $cache->getStats();
echo "  hits: {$stats2['hits']}, misses: {$stats2['misses']}, size: {$stats2['size']}\n";
