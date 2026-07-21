<?php
// 插件系统：钩子注册、插件生命周期、优先级、依赖管理
echo "=== f164: Plugin System + Hooks + Lifecycle ===\n";

interface PluginInterface {
    public function getName(): string;
    public function getVersion(): string;
    public function install(PluginManager $manager): void;
    public function uninstall(PluginManager $manager): void;
}

class PluginManager {
    private array $plugins = [];
    private array $hooks = [];
    private array $config = [];
    private array $dependencies = [];

    public function register(PluginInterface $plugin): bool {
        $name = $plugin->getName();
        if (isset($this->plugins[$name])) return false;
        $this->plugins[$name] = $plugin;
        $plugin->install($this);
        return true;
    }

    public function unregister(string $name): void {
        if (!isset($this->plugins[$name])) return;
        $this->plugins[$name]->uninstall($this);
        // 移除该插件注册的所有钩子
        foreach ($this->hooks as $hookName => &$listeners) {
            $listeners = array_filter($listeners, fn($l) => $l['plugin'] !== $name);
        }
        unset($this->plugins[$name]);
    }

    public function addHook(string $hookName, callable $callback, string $pluginName, int $priority = 10): void {
        if (!isset($this->hooks[$hookName])) $this->hooks[$hookName] = [];
        $this->hooks[$hookName][] = [
            'callback' => $callback,
            'plugin' => $pluginName,
            'priority' => $priority,
        ];
        usort($this->hooks[$hookName], fn($a, $b) => $a['priority'] <=> $b['priority']);
    }

    public function executeHook(string $hookName, mixed $data = null): mixed {
        $listeners = $this->hooks[$hookName] ?? [];
        foreach ($listeners as $listener) {
            $data = $listener['callback']($data);
        }
        return $data;
    }

    public function setConfig(string $key, mixed $value): void { $this->config[$key] = $value; }
    public function getConfig(string $key, mixed $default = null): mixed { return $this->config[$key] ?? $default; }
    public function getPlugins(): array { return $this->plugins; }
    public function getHooks(): array { return $this->hooks; }
}

// 插件实现
class SeoPlugin implements PluginInterface {
    public function getName(): string { return 'seo'; }
    public function getVersion(): string { return '1.0.0'; }

    public function install(PluginManager $manager): void {
        $manager->addHook('page.title', fn($title) => $title . ' | My Site', 'seo', 5);
        $manager->addHook('page.meta', function($meta) {
            $meta['description'] = 'Optimized for search engines';
            $meta['keywords'] = 'php, aot, compiler';
            return $meta;
        }, 'seo', 5);
        $manager->addHook('page.footer', fn($html) => $html . "\n<!-- SEO Plugin Active -->", 'seo', 20);
    }

    public function uninstall(PluginManager $manager): void {
        echo "  [seo] Plugin uninstalled\n";
    }
}

class CachePlugin implements PluginInterface {
    public function getName(): string { return 'cache'; }
    public function getVersion(): string { return '2.1.0'; }

    public function install(PluginManager $manager): void {
        $manager->addHook('page.render', function($html) {
            return "<!-- Cache: HIT -->\n" . $html;
        }, 'cache', 1);
        $manager->addHook('page.title', fn($title) => "[CACHED] " . $title, 'cache', 1);
        $manager->setConfig('cache.ttl', 3600);
    }

    public function uninstall(PluginManager $manager): void {
        echo "  [cache] Plugin uninstalled\n";
    }
}

class AnalyticsPlugin implements PluginInterface {
    public function getName(): string { return 'analytics'; }
    public function getVersion(): string { return '3.0.0'; }

    public function install(PluginManager $manager): void {
        $manager->addHook('page.footer', function($html) {
            return $html . "\n<script>/* Analytics tracking */</script>";
        }, 'analytics', 15);
        $manager->addHook('user.action', function($data) {
            echo "  [analytics] Tracked: {$data['action']} by user {$data['userId']}\n";
            return $data;
        }, 'analytics', 5);
    }

    public function uninstall(PluginManager $manager): void {
        echo "  [analytics] Plugin uninstalled\n";
    }
}

// 测试
echo "--- Register Plugins ---\n";
$manager = new PluginManager();
$manager->register(new SeoPlugin());
$manager->register(new CachePlugin());
$manager->register(new AnalyticsPlugin());

echo "  Registered: " . implode(', ', array_keys($manager->getPlugins())) . "\n";
echo "  Cache TTL: " . $manager->getConfig('cache.ttl') . "s\n";

echo "\n--- Execute Hooks ---\n";
$title = $manager->executeHook('page.title', 'Home Page');
echo "  Title: $title\n";

$meta = $manager->executeHook('page.meta', []);
echo "  Meta: " . json_encode($meta) . "\n";

$html = $manager->executeHook('page.render', '<html><body>Hello</body></html>');
echo "  HTML:\n" . $html . "\n";

$footer = $manager->executeHook('page.footer', '<footer>© 2026</footer>');
echo "  Footer:\n$footer\n";

echo "\n--- User Action Hook ---\n";
$manager->executeHook('user.action', ['action' => 'page_view', 'userId' => 42]);
$manager->executeHook('user.action', ['action' => 'click', 'userId' => 42]);
$manager->executeHook('user.action', ['action' => 'purchase', 'userId' => 42]);

echo "\n--- Unregister Plugin ---\n";
$manager->unregister('cache');
echo "  After unregister cache:\n";
$title2 = $manager->executeHook('page.title', 'Home Page');
echo "  Title: $title2\n";
$html2 = $manager->executeHook('page.render', '<html><body>Hello</body></html>');
echo "  HTML: $html2\n";

echo "\n--- Plugin Info ---\n";
foreach ($manager->getPlugins() as $name => $plugin) {
    echo "  $name v{$plugin->getVersion()}\n";
}
echo "  Hooks registered: " . count($manager->getHooks()) . "\n";
foreach ($manager->getHooks() as $hookName => $listeners) {
    echo "    $hookName: " . count($listeners) . " listener(s)\n";
}

echo "=== f164 Done ===\n";
