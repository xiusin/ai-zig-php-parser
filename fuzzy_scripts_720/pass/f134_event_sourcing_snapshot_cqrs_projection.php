<?php
// 极度混搭: 事件溯源 + 快照 + CQRS + 投影 + 重放
echo "=== f134: EventSourcing + Snapshot + CQRS + Projection ===\n";

class DomainEvent {
    public function __construct(public string $type, public array $data, public float $timestamp = 0, public int $version = 0) {
        if ($this->timestamp === 0) $this->timestamp = microtime(true);
    }
    public function __toString(): string { return "$this->type(v$this->version)"; }
}

class EventStore {
    private array $streams = []; // aggregateId => [events]
    private array $snapshots = [];

    public function append(string $aggregateId, array $events): int {
        if (!isset($this->streams[$aggregateId])) $this->streams[$aggregateId] = [];
        $version = count($this->streams[$aggregateId]);
        foreach ($events as $event) { $event->version = ++$version; $this->streams[$aggregateId][] = $event; }
        return $version;
    }

    public function getEvents(string $aggregateId, int $fromVersion = 0): array {
        $events = $this->streams[$aggregateId] ?? [];
        return array_values(array_filter($events, fn($e) => $e->version > $fromVersion));
    }

    public function saveSnapshot(string $aggregateId, array $state, int $version): void {
        $this->snapshots[$aggregateId] = ['state' => $state, 'version' => $version];
    }

    public function getSnapshot(string $aggregateId): ?array { return $this->snapshots[$aggregateId] ?? null; }

    public function getAllEvents(): array {
        $all = [];
        foreach ($this->streams as $events) $all = array_merge($all, $events);
        return $all;
    }

    public function getAggregateIds(): array { return array_keys($this->streams); }
}

abstract class AggregateRoot {
    protected array $events = [];
    public int $version = 0;

    protected function raise(DomainEvent $event): void { $this->events[] = $event; $this->apply($event); }
    public function getEvents(): array { $events = $this->events; $this->events = []; return $events; }

    public function loadFromHistory(array $events): void {
        foreach ($events as $event) { $this->apply($event); $this->version = $event->version; }
    }

    abstract protected function apply(DomainEvent $event): void;
}

class OrderAggregate extends AggregateRoot {
    public string $status = 'new';
    public float $totalAmount = 0;
    public array $items = [];
    public ?string $customerId = null;

    public function create(string $customerId): void {
        $this->raise(new DomainEvent('OrderCreated', ['customerId' => $customerId]));
    }

    public function addItem(string $productId, int $quantity, float $price): void {
        if ($this->status !== 'new') throw new Exception("Cannot add items to order in status: $this->status");
        $this->raise(new DomainEvent('ItemAdded', ['productId' => $productId, 'quantity' => $quantity, 'price' => $price]));
    }

    public function submit(): void {
        if ($this->status !== 'new') throw new Exception("Cannot submit order in status: $this->status");
        if (empty($this->items)) throw new Exception("Cannot submit empty order");
        $this->raise(new DomainEvent('OrderSubmitted', ['totalAmount' => $this->totalAmount]));
    }

    public function pay(): void {
        if ($this->status !== 'submitted') throw new Exception("Cannot pay order in status: $this->status");
        $this->raise(new DomainEvent('OrderPaid', ['amount' => $this->totalAmount]));
    }

    public function ship(string $trackingNumber): void {
        if ($this->status !== 'paid') throw new Exception("Cannot ship order in status: $this->status");
        $this->raise(new DomainEvent('OrderShipped', ['trackingNumber' => $trackingNumber]));
    }

    public function cancel(string $reason): void {
        if (in_array($this->status, ['shipped', 'delivered'])) throw new Exception("Cannot cancel order in status: $this->status");
        $this->raise(new DomainEvent('OrderCancelled', ['reason' => $reason]));
    }

    protected function apply(DomainEvent $event): void {
        switch ($event->type) {
            case 'OrderCreated':
                $this->customerId = $event->data['customerId']; $this->status = 'new'; break;
            case 'ItemAdded':
                $this->items[] = $event->data;
                $this->totalAmount += $event->data['quantity'] * $event->data['price']; break;
            case 'OrderSubmitted':
                $this->status = 'submitted'; break;
            case 'OrderPaid':
                $this->status = 'paid'; break;
            case 'OrderShipped':
                $this->status = 'shipped'; break;
            case 'OrderCancelled':
                $this->status = 'cancelled'; break;
        }
    }

    public function toArray(): array {
        return ['status' => $this->status, 'totalAmount' => $this->totalAmount, 'items' => count($this->items), 'customerId' => $this->customerId, 'version' => $this->version];
    }
}

class CommandHandler {
    private EventStore $store;

    public function __construct(EventStore $store) { $this->store = $store; }

    public function handle(string $aggregateId, callable $command): void {
        $order = new OrderAggregate();
        $snapshot = $this->store->getSnapshot($aggregateId);
        $fromVersion = 0;
        if ($snapshot) {
            $order->version = $snapshot['version'];
            $fromVersion = $snapshot['version'];
            // 恢复快照状态
            $events = $this->store->getEvents($aggregateId, $fromVersion);
            $order->loadFromHistory($events);
        } else {
            $events = $this->store->getEvents($aggregateId);
            $order->loadFromHistory($events);
        }
        $command($order);
        $newEvents = $order->getEvents();
        if (!empty($newEvents)) {
            $this->store->append($aggregateId, $newEvents);
            // 每5个事件创建快照
            if ($order->version % 5 === 0) $this->store->saveSnapshot($aggregateId, $order->toArray(), $order->version);
        }
    }

    public function loadOrder(string $aggregateId): OrderAggregate {
        $order = new OrderAggregate();
        $events = $this->store->getEvents($aggregateId);
        $order->loadFromHistory($events);
        return $order;
    }
}

class OrderProjection {
    public array $ordersByCustomer = [];
    public array $ordersByStatus = [];
    public float $totalRevenue = 0;
    public int $totalOrders = 0;

    public function project(array $events): void {
        foreach ($events as $event) {
            switch ($event->type) {
                case 'OrderCreated':
                    $this->totalOrders++;
                    $this->ordersByStatus['new'] = ($this->ordersByStatus['new'] ?? 0) + 1;
                    $this->ordersByCustomer[$event->data['customerId']] = ($this->ordersByCustomer[$event->data['customerId']] ?? 0) + 1;
                    break;
                case 'OrderSubmitted':
                    $this->ordersByStatus['new']--; $this->ordersByStatus['submitted'] = ($this->ordersByStatus['submitted'] ?? 0) + 1; break;
                case 'OrderPaid':
                    $this->ordersByStatus['submitted']--; $this->ordersByStatus['paid'] = ($this->ordersByStatus['paid'] ?? 0) + 1;
                    $this->totalRevenue += $event->data['amount']; break;
                case 'OrderShipped':
                    $this->ordersByStatus['paid']--; $this->ordersByStatus['shipped'] = ($this->ordersByStatus['shipped'] ?? 0) + 1; break;
                case 'OrderCancelled':
                    $this->ordersByStatus['new']--; $this->ordersByStatus['cancelled'] = ($this->ordersByStatus['cancelled'] ?? 0) + 1; break;
            }
        }
    }
}

// 测试
echo "--- Event Sourcing: Order Lifecycle ---\n";
$store = new EventStore();
$handler = new CommandHandler($store);

$orderId = 'order-001';
$handler->handle($orderId, fn($o) => $o->create('customer-alice'));
$handler->handle($orderId, fn($o) => $o->addItem('prod-1', 2, 19.99));
$handler->handle($orderId, fn($o) => $o->addItem('prod-2', 1, 49.99));
$handler->handle($orderId, fn($o) => $o->submit());
$handler->handle($orderId, fn($o) => $o->pay());

$order = $handler->loadOrder($orderId);
echo "Order state:\n" . json_encode($order->toArray(), JSON_PRETTY_PRINT) . "\n";

echo "\n--- Event Stream ---\n";
$events = $store->getEvents($orderId);
echo "Events for $orderId (" . count($events) . "):\n";
foreach ($events as $e) echo "  v{$e->version}: $e - " . json_encode($e->data) . "\n";

echo "\n--- Replay from Scratch ---\n";
$replayed = new OrderAggregate();
$replayed->loadFromHistory($store->getEvents($orderId));
echo "Replayed order state:\n" . json_encode($replayed->toArray(), JSON_PRETTY_PRINT) . "\n";
echo "States match: " . var_export($order->toArray() === $replayed->toArray(), true) . "\n";

echo "\n--- Multiple Orders ---\n";
$orders = [
    ['order-002', 'customer-bob', [['prod-3', 1, 99.99]]],
    ['order-003', 'customer-alice', [['prod-1', 3, 19.99], ['prod-4', 2, 29.99]]],
    ['order-004', 'customer-charlie', [['prod-5', 1, 199.99]]],
];
foreach ($orders as [$id, $customer, $items]) {
    $handler->handle($id, fn($o) => $o->create($customer));
    foreach ($items as [$pid, $qty, $price]) $handler->handle($id, fn($o) => $o->addItem($pid, $qty, $price));
    $handler->handle($id, fn($o) => $o->submit());
    $handler->handle($id, fn($o) => $o->pay());
}
$handler->handle('order-002', fn($o) => $o->ship('TRK123'));
$handler->handle('order-004', fn($o) => $o->cancel('Customer request'));

echo "Aggregate IDs: " . implode(', ', $store->getAggregateIds()) . "\n";

echo "\n--- Projections ---\n";
$projection = new OrderProjection();
$projection->project($store->getAllEvents());
echo "Total orders: {$projection->totalOrders}\n";
echo "Total revenue: $" . number_format($projection->totalRevenue, 2) . "\n";
echo "Orders by status:\n";
foreach ($projection->ordersByStatus as $status => $count) echo "  $status: $count\n";
echo "Orders by customer:\n";
foreach ($projection->ordersByCustomer as $customer => $count) echo "  $customer: $count\n";

echo "\n--- Snapshot ---\n";
$store2 = new EventStore();
$handler2 = new CommandHandler($store2);
$handler2->handle('snap-test', fn($o) => $o->create('cust'));
for ($i = 0; $i < 6; $i++) $handler2->handle('snap-test', fn($o) => $o->addItem("prod-$i", 1, 10));
$snapshot = $store2->getSnapshot('snap-test');
echo "Snapshot created: " . var_export($snapshot !== null, true) . "\n";
if ($snapshot) {
    echo "Snapshot version: {$snapshot['version']}\n";
    echo "Snapshot state: " . json_encode($snapshot['state']) . "\n";
}

echo "\n--- CQRS: Command/Query Separation ---\n";
// 查询端
$queryResult = $handler->loadOrder('order-001');
echo "Query order-001: status={$queryResult->status} total=\${$queryResult->totalAmount}\n";

// 命令端: 发货
$handler->handle('order-001', fn($o) => $o->ship('TRK456'));
$shippedOrder = $handler->loadOrder('order-001');
echo "After ship command: status={$shippedOrder->status}\n";

echo "=== f134 Done ===\n";
