<?php
// 事件驱动架构：事件总线、发布订阅、事件溯源、监听器
echo "=== f163: Event-Driven + PubSub + EventSourcing ===\n";

class Event {
    public function __construct(
        public string $name,
        public array $data = [],
        public float $timestamp = 0.0,
    ) {
        if ($this->timestamp === 0.0) {
            $this->timestamp = microtime(true);
        }
    }

    public function __toString(): string {
        return sprintf('[%s] %s: %s', date('Y-m-d H:i:s', (int)$this->timestamp), $this->name, json_encode($this->data));
    }
}

class EventBus {
    private array $listeners = [];
    private array $eventLog = [];
    private static ?EventBus $instance = null;

    public static function getInstance(): self {
        if (self::$instance === null) self::$instance = new self();
        return self::$instance;
    }

    public function subscribe(string $eventName, callable $listener, int $priority = 0): void {
        if (!isset($this->listeners[$eventName])) {
            $this->listeners[$eventName] = [];
        }
        $this->listeners[$eventName][] = ['callback' => $listener, 'priority' => $priority];
        // 按优先级排序（高优先级先执行）
        usort($this->listeners[$eventName], fn($a, $b) => $b['priority'] <=> $a['priority']);
    }

    public function publish(Event $event): void {
        $this->eventLog[] = $event;
        $listeners = $this->listeners[$event->name] ?? [];
        foreach ($listeners as $listener) {
            $listener['callback']($event);
        }
    }

    public function getEventLog(): array {
        return $this->eventLog;
    }

    public function clearLog(): void {
        $this->eventLog = [];
    }

    public function getListenerCount(string $eventName = ''): int {
        if ($eventName === '') {
            return array_sum(array_map('count', $this->listeners));
        }
        return count($this->listeners[$eventName] ?? []);
    }
}

// 事件溯源
class EventStore {
    private array $events = [];
    private array $snapshots = [];

    public function append(string $aggregateId, Event $event): void {
        $this->events[$aggregateId][] = $event;
    }

    public function getEvents(string $aggregateId): array {
        return $this->events[$aggregateId] ?? [];
    }

    public function saveSnapshot(string $aggregateId, array $state): void {
        $this->snapshots[$aggregateId] = [
            'state' => $state,
            'version' => count($this->events[$aggregateId] ?? []),
        ];
    }

    public function getSnapshot(string $aggregateId): ?array {
        return $this->snapshots[$aggregateId] ?? null;
    }

    public function replay(string $aggregateId, callable $reducer): array {
        $state = [];
        $snapshot = $this->getSnapshot($aggregateId);
        if ($snapshot) {
            $state = $snapshot['state'];
            $events = array_slice($this->events[$aggregateId] ?? [], $snapshot['version']);
        } else {
            $events = $this->events[$aggregateId] ?? [];
        }
        foreach ($events as $event) {
            $state = $reducer($state, $event);
        }
        return $state;
    }
}

// 银行账户聚合根
class BankAccount {
    private static EventStore $store;

    public static function setStore(EventStore $store): void {
        self::$store = $store;
    }

    public static function create(string $accountId, string $owner): void {
        self::$store->append($accountId, new Event('AccountCreated', ['owner' => $owner]));
    }

    public static function deposit(string $accountId, float $amount): void {
        self::$store->append($accountId, new Event('MoneyDeposited', ['amount' => $amount]));
        EventBus::getInstance()->publish(new Event('DepositCompleted', ['account' => $accountId, 'amount' => $amount]));
    }

    public static function withdraw(string $accountId, float $amount): void {
        $state = self::getState($accountId);
        if ($state['balance'] < $amount) {
            EventBus::getInstance()->publish(new Event('WithdrawalFailed', ['account' => $accountId, 'reason' => 'insufficient funds']));
            return;
        }
        self::$store->append($accountId, new Event('MoneyWithdrawn', ['amount' => $amount]));
        EventBus::getInstance()->publish(new Event('WithdrawalCompleted', ['account' => $accountId, 'amount' => $amount]));
    }

    public static function getState(string $accountId): array {
        return self::$store->replay($accountId, function(array $state, Event $event): array {
            switch ($event->name) {
                case 'AccountCreated':
                    $state['owner'] = $event->data['owner'];
                    $state['balance'] = 0;
                    $state['transactions'] = 0;
                    break;
                case 'MoneyDeposited':
                    $state['balance'] += $event->data['amount'];
                    $state['transactions']++;
                    break;
                case 'MoneyWithdrawn':
                    $state['balance'] -= $event->data['amount'];
                    $state['transactions']++;
                    break;
            }
            return $state;
        });
    }
}

// 测试
echo "--- Event Bus Pub/Sub ---\n";
$bus = EventBus::getInstance();

$bus->subscribe('user.created', function(Event $e) {
    echo "  [Email Service] Welcome email sent to {$e->data['name']}\n";
}, 10);

$bus->subscribe('user.created', function(Event $e) {
    echo "  [Analytics] User tracked: {$e->data['name']} from {$e->data['city']}\n";
}, 5);

$bus->subscribe('user.created', function(Event $e) {
    echo "  [Audit] User creation logged: {$e->data['id']}\n";
}, 1);

$bus->subscribe('order.placed', function(Event $e) {
    echo "  [Inventory] Stock reduced for order #{$e->data['orderId']}\n";
}, 5);

$bus->subscribe('order.placed', function(Event $e) {
    echo "  [Shipping] Shipping label created for order #{$e->data['orderId']}\n";
}, 3);

$bus->publish(new Event('user.created', ['id' => 1, 'name' => 'Alice', 'city' => 'Beijing']));
echo "\n";
$bus->publish(new Event('user.created', ['id' => 2, 'name' => 'Bob', 'city' => 'Shanghai']));
echo "\n";
$bus->publish(new Event('order.placed', ['orderId' => 1001, 'total' => 99.99]));

echo "\n--- Event Sourcing (Bank Account) ---\n";
$store = new EventStore();
BankAccount::setStore($store);

BankAccount::create('acc-001', 'Alice');
BankAccount::deposit('acc-001', 1000);
BankAccount::deposit('acc-001', 500);
BankAccount::withdraw('acc-001', 200);
BankAccount::withdraw('acc-001', 5000); // Should fail

$state = BankAccount::getState('acc-001');
echo "  Account: acc-001\n";
echo "  Owner: {$state['owner']}\n";
echo "  Balance: \${$state['balance']}\n";
echo "  Transactions: {$state['transactions']}\n";

echo "\n  Event log:\n";
foreach ($store->getEvents('acc-001') as $event) {
    echo "    $event\n";
}

echo "\n--- Snapshot + Replay ---\n";
$store->saveSnapshot('acc-001', $state);
echo "  Snapshot saved (version: " . count($store->getEvents('acc-001')) . ")\n";

BankAccount::deposit('acc-001', 300);
BankAccount::withdraw('acc-001', 100);

$state2 = BankAccount::getState('acc-001');
echo "  After 2 more transactions:\n";
echo "  Balance: \${$state2['balance']}\n";
echo "  Transactions: {$state2['transactions']}\n";

echo "\n--- Event Log Summary ---\n";
echo "  Total events published: " . count($bus->getEventLog()) . "\n";
echo "  Total listeners: " . $bus->getListenerCount() . "\n";

echo "\n--- Wildcard-like Event Matching ---\n";
$bus2 = new EventBus();
$bus2->subscribe('log.info', fn(Event $e) => print("  [INFO] {$e->data['msg']}\n"));
$bus2->subscribe('log.error', fn(Event $e) => print("  [ERROR] {$e->data['msg']}\n"));
$bus2->subscribe('log.debug', fn(Event $e) => print("  [DEBUG] {$e->data['msg']}\n"));

$bus2->publish(new Event('log.info', ['msg' => 'System started']));
$bus2->publish(new Event('log.error', ['msg' => 'Connection failed']));
$bus2->publish(new Event('log.debug', ['msg' => 'Variable x = 42']));
$bus2->publish(new Event('log.info', ['msg' => 'Task completed']));

echo "=== f163 Done ===\n";
