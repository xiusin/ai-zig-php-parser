<?php
// 依赖注入容器
class Container {
    private static ?Container $instance = null;
    private array $bindings = [];
    private array $instances = [];
    private array $aliases = [];

    public static function getInstance(): self {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function bind(string $abstract, mixed $concrete): void {
        $this->bindings[$abstract] = $concrete;
    }

    public function singleton(string $abstract, mixed $concrete): void {
        $this->bindings[$abstract] = $concrete;
        $this->aliases[$abstract] = 'singleton';
    }

    public function instance(string $abstract, mixed $instance): void {
        $this->instances[$abstract] = $instance;
    }

    public function make(string $abstract, array $params = []): mixed {
        if (isset($this->instances[$abstract])) {
            return $this->instances[$abstract];
        }

        $concrete = $this->bindings[$abstract] ?? $abstract;

        if (is_callable($concrete)) {
            $object = $concrete($this);
        } elseif (is_string($concrete) && class_exists($concrete)) {
            $object = new $concrete(...$params);
        } else {
            return $concrete;
        }

        if (isset($this->aliases[$abstract]) && $this->aliases[$abstract] === 'singleton') {
            $this->instances[$abstract] = $object;
        }

        return $object;
    }

    public function call(string $class, string $method, array $params = []): mixed {
        $instance = $this->make($class);
        if (!method_exists($instance, $method)) {
            throw new Exception("Method $class::$method not found");
        }
        return $instance->$method(...$params);
    }

    public function has(string $abstract): bool {
        return isset($this->bindings[$abstract]) || isset($this->instances[$abstract]);
    }

    public function flush(): void {
        $this->bindings = [];
        $this->instances = [];
        $this->aliases = [];
    }
}
