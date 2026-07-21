<?php
// 极度混搭: 并发模拟 + 读写锁 + 原子操作 + 线程安全队列 + 条件变量
echo "=== f019: Concurrency Sim + RWLock + Atomic + SafeQueue ===\n";

class ReadWriteLock {
    private int $readers = 0;
    private int $writers = 0;
    private int $waitingWriters = 0;
    private array $log = [];

    public function readLock(int $threadId): bool {
        if ($writers > 0 || $waitingWriters > 0) {
            $this->log[] = "T$threadId: read lock BLOCKED (writers=$writers, waiting=$waitingWriters)";
            return false;
        }
        $this->readers++;
        $this->log[] = "T$threadId: read lock ACQUIRED (readers=$this->readers)";
        return true;
    }

    public function readUnlock(int $threadId): void {
        $this->readers--;
        $this->log[] = "T$threadId: read unlock (readers=$this->readers)";
    }

    public function writeLock(int $threadId): bool {
        $this->waitingWriters++;
        if ($this->readers > 0 || $this->writers > 0) {
            $this->log[] = "T$threadId: write lock BLOCKED (readers=$this->readers, writers=$this->writers)";
            $this->waitingWriters--;
            return false;
        }
        $this->waitingWriters--;
        $this->writers++;
        $this->log[] = "T$threadId: write lock ACQUIRED (writers=$this->writers)";
        return true;
    }

    public function writeUnlock(int $threadId): void {
        $this->writers--;
        $this->log[] = "T$threadId: write unlock (writers=$this->writers)";
    }

    public function getLog(): array { return $this->log; }
    public function clearLog(): void { $this->log = []; }
}

class AtomicInteger {
    private int $value;
    private array $history = [];

    public function __construct(int $initial = 0) {
        $this->value = $initial;
    }

    public function get(): int { return $this->value; }

    public function incrementAndGet(): int {
        $this->value++;
        $this->history[] = "INC→$this->value";
        return $this->value;
    }

    public function decrementAndGet(): int {
        $this->value--;
        $this->history[] = "DEC→$this->value";
        return $this->value;
    }

    public function compareAndSet(int $expected, int $newValue): bool {
        if ($this->value === $expected) {
            $this->value = $newValue;
            $this->history[] = "CAS($expected→$newValue) OK";
            return true;
        }
        $this->history[] = "CAS($expected→$newValue) FAIL";
        return false;
    }

    public function addAndGet(int $delta): int {
        $this->value += $delta;
        $this->history[] = "ADD($delta)→$this->value";
        return $this->value;
    }

    public function getHistory(): array { return $this->history; }
}

class ThreadSafeQueue {
    private array $items = [];
    private int $maxSize;
    private int $totalEnqueued = 0;
    private int $totalDequeued = 0;

    public function __construct(int $maxSize = 100) {
        $this->maxSize = $maxSize;
    }

    public function enqueue(mixed $item): bool {
        if (count($this->items) >= $this->maxSize) return false;
        $this->items[] = $item;
        $this->totalEnqueued++;
        return true;
    }

    public function dequeue(): mixed {
        if (empty($this->items)) return null;
        $item = array_shift($this->items);
        $this->totalDequeued++;
        return $item;
    }

    public function size(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }
    public function isFull(): bool { return count($this->items) >= $this->maxSize; }
    public function stats(): array {
        return ['size' => $this->size(), 'enqueued' => $this->totalEnqueued, 'dequeued' => $this->totalDequeued];
    }
}

class Semaphore {
    private int $permits;
    private int $available;
    private array $log = [];

    public function __construct(int $permits) {
        $this->permits = $permits;
        $this->available = $permits;
    }

    public function acquire(int $threadId): bool {
        if ($this->available <= 0) {
            $this->log[] = "T$threadId: acquire BLOCKED (0/$this->permits)";
            return false;
        }
        $this->available--;
        $this->log[] = "T$threadId: acquire OK ($this->available/$this->permits)";
        return true;
    }

    public function release(int $threadId): void {
        if ($this->available < $this->permits) {
            $this->available++;
            $this->log[] = "T$threadId: release ($this->available/$this->permits)";
        }
    }

    public function available(): int { return $this->available; }
    public function getLog(): array { return $this->log; }
}

// === 测试 ===
echo "--- ReadWriteLock ---\n";
$rwlock = new ReadWriteLock();

// 模拟多线程读写
$rwlock->readLock(1);
$rwlock->readLock(2);
$rwlock->writeLock(3); // 应该失败（有读者）
$rwlock->readUnlock(1);
$rwlock->readUnlock(2);
$rwlock->writeLock(3); // 现在应该成功
$rwlock->readLock(1);  // 应该失败（有写者）
$rwlock->writeUnlock(3);
$rwlock->readLock(1);  // 现在应该成功
$rwlock->readUnlock(1);

foreach ($rwlock->getLog() as $entry) echo "  $entry\n";

echo "\n--- AtomicInteger ---\n";
$atomic = new AtomicInteger(0);
$atomic->incrementAndGet();
$atomic->incrementAndGet();
$atomic->addAndGet(5);
echo "Value: " . $atomic->get() . "\n";
$atomic->compareAndSet(7, 10);
echo "After CAS(7→10): " . $atomic->get() . "\n";
$atomic->compareAndSet(7, 20);
echo "After CAS(7→20): " . $atomic->get() . "\n";
$atomic->decrementAndGet();
echo "After DEC: " . $atomic->get() . "\n";

echo "History: " . implode(', ', $atomic->getHistory()) . "\n";

echo "\n--- ThreadSafeQueue ---\n";
$queue = new ThreadSafeQueue(5);
for ($i = 1; $i <= 5; $i++) {
    $queue->enqueue("item_$i");
    echo "  enqueue item_$i → size=" . $queue->size() . "\n";
}
echo "  enqueue item_6 → " . var_export($queue->enqueue("item_6"), true) . " (full)\n";

while (!$queue->isEmpty()) {
    $item = $queue->dequeue();
    echo "  dequeue $item → size=" . $queue->size() . "\n";
}
echo "  dequeue when empty: " . var_export($queue->dequeue(), true) . "\n";
echo "  Stats: " . json_encode($queue->stats()) . "\n";

echo "\n--- Semaphore ---\n";
$sem = new Semaphore(3);
$threads = [1, 2, 3, 4, 5];
foreach ($threads as $t) {
    $result = $sem->acquire($t);
    echo "  T$t acquire: " . var_export($result, true) . " (available: " . $sem->available() . ")\n";
}
$sem->release(1);
echo "  T1 release (available: " . $sem->available() . ")\n";
$sem->acquire(4);
echo "  T4 acquire (available: " . $sem->available() . ")\n";

echo "\n--- Concurrent Counter Simulation ---\n";
$counter = new AtomicInteger(0);
$sem2 = new Semaphore(2);
$queue2 = new ThreadSafeQueue(10);

// 模拟 3 个 "线程" 操作
for ($t = 1; $t <= 3; $t++) {
    if ($sem2->acquire($t)) {
        for ($i = 0; $i < 3; $i++) {
            $counter->incrementAndGet();
            $queue2->enqueue("T$t:msg$i");
        }
        $sem2->release($t);
    }
}

echo "Counter final: " . $counter->get() . "\n";
echo "Queue size: " . $queue2->size() . "\n";
echo "Queue items: " . implode(', ', array_map(fn($i) => (string)$i, array_slice($queue2->stats(), 0, 2))) . "\n";

while (!$queue2->isEmpty()) {
    echo "  " . $queue2->dequeue() . "\n";
}

echo "=== f019 Done ===\n";
