<?php
// 极度混搭: 观察者模式 + 消息队列 + 发布订阅 + 过滤链 + 异步模拟
echo "=== c015: Observer + PubSub + MessageQueue + FilterChain ===\n\n";

interface Observer {
    public function update(string $event, mixed $data): void;
    public function getId(): string;
}

class EventBus {
    private array $subscribers = [];
    private array $messageQueue = [];
    private array $filters = [];
    private bool $processing = false;

    public function subscribe(string $topic, Observer $observer): self {
        if (!isset($this->subscribers[$topic])) {
            $this->subscribers[$topic] = [];
        }
        $this->subscribers[$topic][$observer->getId()] = $observer;
        return $this;
    }

    public function unsubscribe(string $topic, string $observerId): self {
        unset($this->subscribers[$topic][$observerId]);
        return $this;
    }

    public function addFilter(string $topic, callable $filter): self {
        if (!isset($this->filters[$topic])) {
            $this->filters[$topic] = [];
        }
        $this->filters[$topic][] = $filter;
        return $this;
    }

    public function publish(string $topic, mixed $data): self {
        $this->messageQueue[] = ['topic' => $topic, 'data' => $data];
        if (!$this->processing) {
            $this->processQueue();
        }
        return $this;
    }

    private function processQueue(): void {
        $this->processing = true;
        while (!empty($this->messageQueue)) {
            $msg = array_shift($this->messageQueue);
            $this->dispatch($msg['topic'], $msg['data']);
        }
        $this->processing = false;
    }

    private function dispatch(string $topic, mixed $data): void {
        foreach ($this->filters[$topic] ?? [] as $filter) {
            $data = $filter($data);
            if ($data === null) return;
        }

        $subscribers = $this->subscribers[$topic] ?? [];
        foreach ($subscribers as $observer) {
            try {
                $observer->update($topic, $data);
            } catch (Exception $e) {
                echo "  [ERROR] Observer {$observer->getId()} failed: {$e->getMessage()}\n";
            }
        }
    }

    public function getSubscriberCount(string $topic): int {
        return count($this->subscribers[$topic] ?? []);
    }

    public function getTopics(): array {
        return array_keys($this->subscribers);
    }
}

class LogObserver implements Observer {
    private string $id;
    private array $log = [];

    public function __construct(string $id) {
        $this->id = $id;
    }

    public function update(string $event, mixed $data): void {
        $entry = "[$event] " . json_encode($data);
        $this->log[] = $entry;
        echo "  {$this->id}: $entry\n";
    }

    public function getId(): string {
        return $this->id;
    }

    public function getLog(): array {
        return $this->log;
    }
}

class MetricsObserver implements Observer {
    private string $id;
    private array $counters = [];
    private array $values = [];

    public function __construct(string $id) {
        $this->id = $id;
    }

    public function update(string $event, mixed $data): void {
        if (!isset($this->counters[$event])) $this->counters[$event] = 0;
        $this->counters[$event]++;
        $this->values[$event] = $data;
    }

    public function getId(): string {
        return $this->id;
    }

    public function getCount(string $event): int {
        return $this->counters[$event] ?? 0;
    }

    public function getLastValue(string $event): mixed {
        return $this->values[$event] ?? null;
    }

    public function getAllCounts(): array {
        return $this->counters;
    }
}

class NestedObserver implements Observer {
    private string $id;
    private int $depth = 0;
    private ?EventBus $busRef = null;

    public function __construct(string $id) {
        $this->id = $id;
    }

    public function setBus(EventBus $bus): void {
        $this->busRef = $bus;
    }

    public function update(string $event, mixed $data): void {
        $this->depth++;
        echo "  [nested] depth={$this->depth} event=$event data=" . json_encode($data) . "\n";
        if ($this->depth < 3 && $data > 0) {
            $this->busRef->publish('chain', $data - 1);
        }
        $this->depth--;
    }

    public function getId(): string {
        return $this->id;
    }
}

// === 测试 ===

echo "--- Basic PubSub ---\n";
$bus = new EventBus();
$logObserver = new LogObserver("logger");
$metrics = new MetricsObserver("metrics");

$bus->subscribe('user.action', $logObserver);
$bus->subscribe('user.action', $metrics);
$bus->subscribe('system.error', $logObserver);

$bus->publish('user.action', ['action' => 'login', 'user' => 'Alice']);
$bus->publish('user.action', ['action' => 'logout', 'user' => 'Bob']);
$bus->publish('system.error', ['code' => 500, 'message' => 'DB timeout']);

echo "\nSubscriber count (user.action): " . $bus->getSubscriberCount('user.action') . "\n";
echo "Topics: " . implode(", ", $bus->getTopics()) . "\n";

echo "\n--- Metrics Summary ---\n";
foreach ($metrics->getAllCounts() as $event => $count) {
    echo "  $event: $count times, last=" . json_encode($metrics->getLastValue($event)) . "\n";
}

echo "\n--- Filter Chain ---\n";
$bus2 = new EventBus();
$bus2->addFilter('data.transform', function($data) {
    $data['filtered'] = true;
    return $data;
});
$bus2->addFilter('data.transform', function($data) {
    $data['timestamp'] = count($data);
    return $data;
});
$bus2->addFilter('data.transform', function($data) {
    if (isset($data['block']) && $data['block']) return null;
    $data['final'] = true;
    return $data;
});
$bus2->subscribe('data.transform', $logObserver);

$bus2->publish('data.transform', ['raw' => 'input1']);
$bus2->publish('data.transform', ['raw' => 'input2', 'block' => true]);

echo "\n--- Nested Publish (reentrancy) ---\n";
$bus3 = new EventBus();
$nestedObserver = new NestedObserver('nested');
$nestedObserver->setBus($bus3);
$bus3->subscribe('chain', $nestedObserver);
$bus3->publish('chain', 3);

echo "\n--- Unsubscribe ---\n";
$bus->unsubscribe('user.action', 'logger');
$bus->publish('user.action', ['action' => 'search', 'user' => 'Charlie']);
echo "After unsubscribe, logger log count: " . count($logObserver->getLog()) . "\n";

echo "\n=== c015 Done ===\n";
