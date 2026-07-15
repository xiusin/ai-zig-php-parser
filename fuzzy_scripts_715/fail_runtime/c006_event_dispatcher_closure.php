<?php
// 极度混搭: 事件分发器 + 闭包优先级 + 异常传播 + 优先队列 + 可调用检测
echo "=== c006: Event Dispatcher + Closure Priority + Exception Propagation ===\n\n";

class EventDispatcher {
    private array $listeners = [];
    private array $fired = [];
    private bool $propagationStopped = false;

    public function on(string $event, callable $handler, int $priority = 0): self {
        if (!isset($this->listeners[$event])) {
            $this->listeners[$event] = [];
        }
        $this->listeners[$event][] = [
            'handler' => $handler,
            'priority' => $priority,
            'id' => count($this->listeners[$event]),
        ];
        // 按优先级排序（高优先级先执行）
        usort($this->listeners[$event], fn($a, $b) => $b['priority'] <=> $a['priority']);
        return $this;
    }

    public function off(string $event, ?callable $handler = null): self {
        if ($handler === null) {
            unset($this->listeners[$event]);
        } else {
            $this->listeners[$event] = array_values(array_filter(
                $this->listeners[$event] ?? [],
                fn($l) => $l['handler'] !== $handler
            ));
        }
        return $this;
    }

    public function dispatch(string $event, array $data = []): array {
        $this->propagationStopped = false;
        $results = [];
        $this->fired[] = $event;

        foreach ($this->listeners[$event] ?? [] as $listener) {
            if ($this->propagationStopped) break;

            try {
                $result = ($listener['handler'])($data, $this);
                $results[] = $result;
            } catch (Throwable $e) {
                $results[] = ['error' => $e->getMessage(), 'listener' => $listener['id']];
                $this->propagationStopped = true;
            }
        }

        return $results;
    }

    public function stopPropagation(): void {
        $this->propagationStopped = true;
    }

    public function hasListeners(string $event): bool {
        return !empty($this->listeners[$event]);
    }

    public function getFiredEvents(): array {
        return $this->fired;
    }
}

class EventArgs {
    public function __construct(
        public readonly string $name,
        public readonly array $data = []
    ) {}

    public function get(string $key, mixed $default = null): mixed {
        return $this->data[$key] ?? $default;
    }
}

// === 测试 ===

$dispatcher = new EventDispatcher();

// 1. 基本事件注册与触发
$dispatcher->on('user.login', function($data) {
    $name = $data['name'] ?? 'unknown';
    echo "  [log] User $name logged in\n";
    return "logged:$name";
});

$dispatcher->on('user.login', function($data) {
    $name = $data['name'] ?? 'unknown';
    echo "  [audit] Recording login for $name\n";
    return "audited:$name";
}, 10); // Higher priority

$results = $dispatcher->dispatch('user.login', ['name' => 'Alice']);
echo "Results: " . implode(" | ", $results) . "\n";

// 2. 优先级排序验证
echo "\n--- Priority Order ---\n";
$d2 = new EventDispatcher();
$order = [];
$d2->on('test', function() use (&$order) { $order[] = 'C'; }, 5);
$d2->on('test', function() use (&$order) { $order[] = 'A'; }, 20);
$d2->on('test', function() use (&$order) { $order[] = 'B'; }, 10);
$d2->dispatch('test');
echo "Execution order: " . implode(",", $order) . "\n";

// 3. 传播停止
echo "\n--- Stop Propagation ---\n";
$d3 = new EventDispatcher();
$d3->on('chain', function($data, $dispatcher) {
    echo "  [first] executed\n";
    $dispatcher->stopPropagation();
    return 'first';
});
$d3->on('chain', function($data) {
    echo "  [second] executed\n";
    return 'second';
});
$res = $d3->dispatch('chain');
echo "Results count: " . count($res) . "\n";

// 4. 异常传播
echo "\n--- Exception Handling ---\n";
$d4 = new EventDispatcher();
$d4->on('risky', function() {
    echo "  [safe] running\n";
    return 'safe';
});
$d4->on('risky', function() {
    throw new RuntimeException("Handler failed!");
}, 10); // 高优先级先执行
$res = $d4->dispatch('risky');
echo "Results: " . json_encode($res) . "\n";

// 5. 闭包组合 + 状态累积
echo "\n--- State Accumulation ---\n";
$d5 = new EventDispatcher();
$state = ['count' => 0, 'sum' => 0];
for ($i = 1; $i <= 5; $i++) {
    $d5->on('accumulate', function($data) use (&$state, $i) {
        $state['count']++;
        $state['sum'] += $i * ($data['multiplier'] ?? 1);
        return $i;
    });
}
$d5->dispatch('accumulate', ['multiplier' => 2]);
echo "State: count={$state['count']} sum={$state['sum']}\n";

// 6. 可调用检测 + 动态调用
echo "\n--- Callable Detection ---\n";
function handler_func($data) { return "func:" . $data['val']; }

class HandlerObj {
    public function handle($data) { return "method:" . $data['val']; }
    public static function staticHandle($data) { return "static:" . $data['val']; }
}

$d6 = new EventDispatcher();
$callables = [
    'function' => 'handler_func',
    'method' => [new HandlerObj(), 'handle'],
    'static' => ['HandlerObj', 'staticHandle'],
    'closure' => fn($d) => "closure:" . $d['val'],
    'arrow' => fn($d) => "arrow:" . strtoupper($d['val']),
];

foreach ($callables as $name => $callable) {
    $d6->on('mixed', $callable);
    echo "  is_callable('$name'): " . var_export(is_callable($callable), true) . "\n";
}

$res = $d6->dispatch('mixed', ['val' => 'test']);
echo "Mixed results: " . implode(" | ", $res) . "\n";

// 7. 嵌套事件
echo "\n--- Nested Events ---\n";
$d7 = new EventDispatcher();
$d7->on('outer', function($data) use ($d7) {
    echo "  [outer] triggering inner\n";
    $inner = $d7->dispatch('inner', ['msg' => 'from outer']);
    echo "  [outer] inner returned: " . implode(",", $inner) . "\n";
    return 'outer-done';
});
$d7->on('inner', function($data) {
    echo "  [inner] msg={$data['msg']}\n";
    return 'inner-done';
});
$d7->dispatch('outer');

// 8. Fired events tracking
echo "\n--- Fired Events ---\n";
foreach ($d7->getFiredEvents() as $event) {
    echo "  fired: $event\n";
}

echo "\n=== c006 Done ===\n";
