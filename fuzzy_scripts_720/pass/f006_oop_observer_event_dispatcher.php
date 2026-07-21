<?php
// 极度混搭: 观察者模式 + 事件分发器 + 闭包监听器 + 优先级队列 + 异常隔离
echo "=== f006: Observer + Event Dispatcher + Priority + Exception Isolation ===\n";

interface Event {
    public function getName(): string;
    public function getPayload(): array;
    public function getTimestamp(): int;
}

class GenericEvent implements Event {
    public function __construct(
        private string $name,
        private array $payload,
        private int $timestamp = 0
    ) {
        if ($this->timestamp === 0) {
            $this->timestamp = 1000;
        }
    }

    public function getName(): string { return $this->name; }
    public function getPayload(): array { return $this->payload; }
    public function getTimestamp(): int { return $this->timestamp; }
}

interface EventListener {
    public function handle(Event $event): void;
    public function getPriority(): int;
}

class ClosureListener implements EventListener {
    private \Closure $handler;
    private int $priority;

    public function __construct(callable $handler, int $priority = 0) {
        $this->handler = \Closure::fromCallable($handler);
        $this->priority = $priority;
    }

    public function handle(Event $event): void {
        ($this->handler)($event);
    }

    public function getPriority(): int { return $this->priority; }
}

class EventDispatcher {
    private array $listeners = [];
    private array $log = [];
    private bool $propagationStopped = false;

    public function subscribe(string $eventName, EventListener $listener): void {
        $this->listeners[$eventName][] = $listener;
        // 按优先级排序（高优先级先执行）
        usort($this->listeners[$eventName], fn($a, $b) => $b->getPriority() <=> $a->getPriority());
    }

    public function dispatch(Event $event): void {
        $this->propagationStopped = false;
        $name = $event->getName();
        $this->log[] = "DISPATCH: $name";

        if (!isset($this->listeners[$name])) return;

        foreach ($this->listeners[$name] as $listener) {
            if ($this->propagationStopped) {
                $this->log[] = "  STOPPED";
                break;
            }
            try {
                $listener->handle($event);
                $this->log[] = "  HANDLED by " . get_class($listener) . " (pri={$listener->getPriority()})";
            } catch (\Throwable $e) {
                $this->log[] = "  ERROR: " . $e->getMessage();
                // 异常隔离：继续执行其他监听器
            }
        }
    }

    public function stopPropagation(): void {
        $this->propagationStopped = true;
    }

    public function getLog(): array { return $this->log; }

    public function clearLog(): void { $this->log = []; }
}

// === 测试 ===

$dispatcher = new EventDispatcher();

// 注册监听器（不同优先级）
$dispatcher->subscribe('user.login', new ClosureListener(function(Event $e) {
    $user = $e->getPayload()['user'] ?? 'unknown';
    echo "  [LOG] User $user logged in\n";
}, 10));

$dispatcher->subscribe('user.login', new ClosureListener(function(Event $e) use ($dispatcher) {
    $ip = $e->getPayload()['ip'] ?? '0.0.0.0';
    echo "  [SECURITY] Checking IP: $ip\n";
    if ($ip === 'blocked') {
        echo "  [SECURITY] Blocked! Stopping propagation.\n";
        $dispatcher->stopPropagation();
    }
}, 20)); // 更高优先级，先执行

$dispatcher->subscribe('user.login', new ClosureListener(function(Event $e) {
    // 这个会抛异常
    $data = $e->getPayload();
    if (!isset($data['user'])) {
        throw new RuntimeException("Missing user in payload");
    }
    echo "  [ANALYTICS] Recorded login for {$data['user']}\n";
}, 5));

$dispatcher->subscribe('user.logout', new ClosureListener(function(Event $e) {
    echo "  [LOG] User logged out\n";
}, 0));

// 触发事件
echo "--- Event: user.login (normal) ---\n";
$dispatcher->dispatch(new GenericEvent('user.login', ['user' => 'Alice', 'ip' => '192.168.1.1']));

echo "\n--- Event: user.login (blocked IP) ---\n";
$dispatcher->clearLog();
$dispatcher->dispatch(new GenericEvent('user.login', ['user' => 'Bob', 'ip' => 'blocked']));

echo "\n--- Event: user.login (missing user - exception) ---\n";
$dispatcher->clearLog();
$dispatcher->dispatch(new GenericEvent('user.login', ['ip' => '10.0.0.1']));

echo "\n--- Event: user.logout ---\n";
$dispatcher->dispatch(new GenericEvent('user.logout', ['user' => 'Alice']));

// 查看日志
echo "\n--- Dispatcher Log ---\n";
foreach ($dispatcher->getLog() as $entry) {
    echo "  $entry\n";
}

echo "=== f006 Done ===\n";
