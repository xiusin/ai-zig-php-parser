<?php
class Registry {
    private static ?Registry $instance = null;
    private array $services = [];

    private function __construct() {}

    public static function getInstance(): self {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function set(string $key, mixed $value): void {
        $this->services[$key] = $value;
    }

    public function get(string $key): mixed {
        return $this->services[$key] ?? null;
    }

    public function has(string $key): bool {
        return isset($this->services[$key]);
    }

    public function remove(string $key): void {
        unset($this->services[$key]);
    }

    public function clear(): void {
        $this->services = [];
    }
}

$registry = Registry::getInstance();
$registry->set('db', 'mysql:host=localhost');
$registry->set('cache', 'redis://localhost');

echo $registry->get('db') . "\n";
echo $registry->has('cache') ? 'true' : 'false' . "\n";
echo $registry->has('session') ? 'true' : 'false' . "\n";

$registry2 = Registry::getInstance();
echo $registry2->get('db') . "\n";

$registry->remove('db');
echo $registry->has('db') ? 'true' : 'false' . "\n";
echo "OK\n";
