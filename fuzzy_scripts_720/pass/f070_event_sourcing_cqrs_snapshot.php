<?php
// 极度混搭: 事件溯源 + 快照 + CQRS分离 + 事件回放
echo "=== f070: Event Sourcing + Snapshot + CQRS ===\n";

class Event {
    public function __construct(
        public string $type,
        public array $data,
        public int $version,
        public int $timestamp = 0,
    ) {
        $this->timestamp = $this->timestamp ?: time();
    }
}

class EventStore {
    private array $events = []; // aggregateId → Event[]
    private array $snapshots = []; // aggregateId → [version, state]

    public function append(string $aggregateId, Event $event): void {
        if (!isset($this->events[$aggregateId])) $this->events[$aggregateId] = [];
        $this->events[$aggregateId][] = $event;
    }

    public function getEvents(string $aggregateId, int $fromVersion = 0): array {
        $events = $this->events[$aggregateId] ?? [];
        if ($fromVersion === 0) return $events;
        return array_values(array_filter($events, fn($e) => $e->version > $fromVersion));
    }

    public function saveSnapshot(string $aggregateId, int $version, array $state): void {
        $this->snapshots[$aggregateId] = ['version' => $version, 'state' => $state];
    }

    public function getSnapshot(string $aggregateId): ?array {
        return $this->snapshots[$aggregateId] ?? null;
    }

    public function getVersion(string $aggregateId): int {
        $events = $this->events[$aggregateId] ?? [];
        return empty($events) ? 0 : end($events)->version;
    }

    public function replay(string $aggregateId, callable $reducer, ?array $initialState = null): array {
        $snapshot = $this->getSnapshot($aggregateId);
        if ($snapshot !== null) {
            $state = $snapshot['state'];
            $fromVersion = $snapshot['version'];
        } else {
            $state = $initialState ?? [];
            $fromVersion = 0;
        }
        $events = $this->getEvents($aggregateId, $fromVersion);
        foreach ($events as $event) {
            $state = $reducer($state, $event);
        }
        return $state;
    }
}

class BankAccount {
    private string $id;
    private EventStore $store;
    public array $state;

    public function __construct(string $id, EventStore $store) {
        $this->id = $id;
        $this->store = $store;
        $this->state = $this->store->replay($this->id, [$this, 'reduce'], ['balance' => 0, 'transactions' => []]);
    }

    public function deposit(float $amount): void {
        $version = $this->store->getVersion($this->id) + 1;
        $this->store->append($this->id, new Event('deposited', ['amount' => $amount], $version));
        $this->state = $this->refresh();
    }

    public function withdraw(float $amount): bool {
        if ($this->state['balance'] < $amount) return false;
        $version = $this->store->getVersion($this->id) + 1;
        $this->store->append($this->id, new Event('withdrawn', ['amount' => $amount], $version));
        $this->state = $this->refresh();
        return true;
    }

    public function transfer(BankAccount $to, float $amount): bool {
        if ($this->state['balance'] < $amount) return false;
        $this->withdraw($amount);
        $to->deposit($amount);
        $version = $this->store->getVersion($this->id) + 1;
        $this->store->append($this->id, new Event('transferred_out', ['to' => $to->id, 'amount' => $amount], $version));
        return true;
    }

    public function reduce(array $state, Event $event): array {
        return match($event->type) {
            'deposited' => [
                'balance' => $state['balance'] + $event->data['amount'],
                'transactions' => array_merge($state['transactions'], [['type' => 'deposit', 'amount' => $event->data['amount']]]),
            ],
            'withdrawn' => [
                'balance' => $state['balance'] - $event->data['amount'],
                'transactions' => array_merge($state['transactions'], [['type' => 'withdraw', 'amount' => $event->data['amount']]]),
            ],
            'transferred_out' => [
                'balance' => $state['balance'], // already adjusted by withdraw
                'transactions' => array_merge($state['transactions'], [['type' => 'transfer_out', 'to' => $event->data['to'], 'amount' => $event->data['amount']]]),
            ],
            default => $state,
        };
    }

    private function refresh(): array {
        return $this->store->replay($this->id, [$this, 'reduce'], ['balance' => 0, 'transactions' => []]);
    }

    public function saveSnapshot(): void {
        $this->store->saveSnapshot($this->id, $this->store->getVersion($this->id), $this->state);
    }

    public function getBalance(): float { return $this->state['balance']; }
    public function getTransactions(): array { return $this->state['transactions']; }
}

// 测试
echo "--- Event Sourcing: Bank Account ---\n";
$store = new EventStore();
$acc1 = new BankAccount('acc-001', $store);
$acc2 = new BankAccount('acc-002', $store);

echo "Initial balances: acc1=" . $acc1->getBalance() . " acc2=" . $acc2->getBalance() . "\n";

$acc1->deposit(1000);
echo "After deposit 1000: acc1=" . $acc1->getBalance() . "\n";

$acc1->deposit(500);
echo "After deposit 500: acc1=" . $acc1->getBalance() . "\n";

$acc1->withdraw(200);
echo "After withdraw 200: acc1=" . $acc1->getBalance() . "\n";

echo "Withdraw 2000 (insufficient): " . var_export($acc1->withdraw(2000), true) . "\n";
echo "Balance: " . $acc1->getBalance() . "\n";

$acc1->transfer($acc2, 300);
echo "After transfer 300 to acc2: acc1=" . $acc1->getBalance() . " acc2=" . $acc2->getBalance() . "\n";

echo "\n--- Transactions (acc1) ---\n";
foreach ($acc1->getTransactions() as $t) echo "  " . json_encode($t) . "\n";

echo "\n--- Events (acc1) ---\n";
$events = $store->getEvents('acc-001');
foreach ($events as $e) echo "  v{$e->version}: {$e->type} " . json_encode($e->data) . "\n";

echo "\n--- Snapshot ---\n";
$acc1->saveSnapshot();
echo "Snapshot saved at version " . $store->getVersion('acc-001') . "\n";

$acc1->deposit(100);
echo "After deposit 100 (post-snapshot): acc1=" . $acc1->getBalance() . "\n";

// 重新创建账号（使用快照）
$acc1Rebuilt = new BankAccount('acc-001', $store);
echo "Rebuilt acc1 balance: " . $acc1Rebuilt->getBalance() . " (should match)\n";

echo "\n--- CQRS: Read Model ---\n";
class AccountReadModel {
    private array $projections = [];

    public function project(EventStore $store, string $aggregateId): void {
        $events = $store->getEvents($aggregateId);
        $balance = 0; $count = 0;
        foreach ($events as $e) {
            if ($e->type === 'deposited') { $balance += $e->data['amount']; $count++; }
            elseif ($e->type === 'withdrawn') { $balance -= $e->data['amount']; $count++; }
        }
        $this->projections[$aggregateId] = ['balance' => $balance, 'tx_count' => $count];
    }

    public function getProjection(string $id): ?array {
        return $this->projections[$id] ?? null;
    }
}

$readModel = new AccountReadModel();
$readModel->project($store, 'acc-001');
$readModel->project($store, 'acc-002');
echo "acc-001 projection: " . json_encode($readModel->getProjection('acc-001')) . "\n";
echo "acc-002 projection: " . json_encode($readModel->getProjection('acc-002')) . "\n";

echo "=== f070 Done ===\n";
