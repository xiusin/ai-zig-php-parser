<?php
// 并发原语模拟：锁、信号量、读写锁、条件变量
echo "=== f173: Concurrency Primitives Simulation ===\n";

class Mutex {
    private bool $locked = false;
    private int $ownerId = 0;
    private int $lockCount = 0;

    public function lock(int $threadId): bool {
        if ($this->locked && $this->ownerId !== $threadId) {
            return false; // 模拟阻塞失败
        }
        $this->locked = true;
        $this->ownerId = $threadId;
        $this->lockCount++;
        return true;
    }

    public function unlock(int $threadId): bool {
        if (!$this->locked || $this->ownerId !== $threadId) return false;
        $this->lockCount--;
        if ($this->lockCount === 0) {
            $this->locked = false;
            $this->ownerId = 0;
        }
        return true;
    }

    public function tryLock(int $threadId): bool {
        if ($this->locked && $this->ownerId !== $threadId) return false;
        return $this->lock($threadId);
    }

    public function isLocked(): bool { return $this->locked; }
}

class Semaphore {
    private int $permits;
    private int $available;

    public function __construct(int $permits) {
        $this->permits = $permits;
        $this->available = $permits;
    }

    public function acquire(): bool {
        if ($this->available > 0) {
            $this->available--;
            return true;
        }
        return false;
    }

    public function release(): void {
        if ($this->available < $this->permits) {
            $this->available++;
        }
    }

    public function available(): int { return $this->available; }
}

class ReadWriteLock {
    private int $readers = 0;
    private bool $writer = false;
    private int $waitingWriters = 0;

    public function readLock(): bool {
        if ($this->writer || $this->waitingWriters > 0) return false;
        $this->readers++;
        return true;
    }

    public function readUnlock(): void {
        $this->readers--;
    }

    public function writeLock(): bool {
        if ($this->writer || $this->readers > 0) {
            $this->waitingWriters++;
            return false;
        }
        $this->writer = true;
        return true;
    }

    public function writeUnlock(): void {
        $this->writer = false;
        if ($this->waitingWriters > 0) $this->waitingWriters--;
    }

    public function getStatus(): array {
        return ['readers' => $this->readers, 'writer' => $this->writer, 'waiting_writers' => $this->waitingWriters];
    }
}

class AtomicInteger {
    private int $value = 0;
    private array $history = [];

    public function get(): int { return $this->value; }

    public function set(int $val): void {
        $this->history[] = ['op' => 'set', 'from' => $this->value, 'to' => $val];
        $this->value = $val;
    }

    public function increment(): int {
        $this->history[] = ['op' => 'inc', 'from' => $this->value, 'to' => $this->value + 1];
        return ++$this->value;
    }

    public function decrement(): int {
        $this->history[] = ['op' => 'dec', 'from' => $this->value, 'to' => $this->value - 1];
        return --$this->value;
    }

    public function compareAndSet(int $expected, int $new): bool {
        if ($this->value === $expected) {
            $this->history[] = ['op' => 'cas', 'from' => $this->value, 'to' => $new, 'success' => true];
            $this->value = $new;
            return true;
        }
        $this->history[] = ['op' => 'cas', 'from' => $this->value, 'expected' => $expected, 'success' => false];
        return false;
    }

    public function addAndGet(int $delta): int {
        $this->value += $delta;
        $this->history[] = ['op' => 'add', 'from' => $this->value - $delta, 'to' => $this->value];
        return $this->value;
    }

    public function getHistory(): array { return $this->history; }
}

class ConcurrentQueue {
    private array $items = [];
    private Mutex $mutex;

    public function __construct() {
        $this->mutex = new Mutex();
    }

    public function push(mixed $item): bool {
        if (!$this->mutex->tryLock(1)) return false;
        $this->items[] = $item;
        $this->mutex->unlock(1);
        return true;
    }

    public function pop(): mixed {
        if (!$this->mutex->tryLock(1)) return null;
        $item = array_shift($this->items);
        $this->mutex->unlock(1);
        return $item;
    }

    public function size(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }
}

// 测试
echo "--- Mutex ---\n";
$mutex = new Mutex();
echo "  Lock by thread 1: " . ($mutex->lock(1) ? 'OK' : 'FAIL') . "\n";
echo "  Reentrant lock by thread 1: " . ($mutex->lock(1) ? 'OK' : 'FAIL') . "\n";
echo "  Lock by thread 2: " . ($mutex->tryLock(2) ? 'OK' : 'BLOCKED') . "\n";
echo "  Unlock by thread 1: " . ($mutex->unlock(1) ? 'OK' : 'FAIL') . "\n";
echo "  Still locked: " . ($mutex->isLocked() ? 'Y' : 'N') . "\n";
$mutex->unlock(1);
echo "  After second unlock: " . ($mutex->isLocked() ? 'Y' : 'N') . "\n";

echo "\n--- Semaphore ---\n";
$sem = new Semaphore(3);
echo "  Available: " . $sem->available() . "\n";
echo "  Acquire 1: " . ($sem->acquire() ? 'OK' : 'FAIL') . "\n";
echo "  Acquire 2: " . ($sem->acquire() ? 'OK' : 'FAIL') . "\n";
echo "  Acquire 3: " . ($sem->acquire() ? 'OK' : 'FAIL') . "\n";
echo "  Available: " . $sem->available() . "\n";
echo "  Acquire 4: " . ($sem->acquire() ? 'OK' : 'BLOCKED') . "\n";
$sem->release();
echo "  After release, available: " . $sem->available() . "\n";

echo "\n--- ReadWriteLock ---\n";
$rwl = new ReadWriteLock();
echo "  Read lock 1: " . ($rwl->readLock() ? 'OK' : 'FAIL') . "\n";
echo "  Read lock 2: " . ($rwl->readLock() ? 'OK' : 'FAIL') . "\n";
echo "  Write lock (should fail): " . ($rwl->writeLock() ? 'OK' : 'BLOCKED') . "\n";
$rwl->readUnlock();
$rwl->readUnlock();
echo "  Write lock after reads: " . ($rwl->writeLock() ? 'OK' : 'FAIL') . "\n";
echo "  Read lock during write: " . ($rwl->readLock() ? 'OK' : 'BLOCKED') . "\n";
echo "  Status: " . json_encode($rwl->getStatus()) . "\n";
$rwl->writeUnlock();
echo "  Read lock after write unlock: " . ($rwl->readLock() ? 'OK' : 'FAIL') . "\n";

echo "\n--- Atomic Integer ---\n";
$atomic = new AtomicInteger();
echo "  Initial: " . $atomic->get() . "\n";
echo "  Increment: " . $atomic->increment() . "\n";
echo "  Increment: " . $atomic->increment() . "\n";
echo "  Add 10: " . $atomic->addAndGet(10) . "\n";
echo "  CAS(12, 20): " . ($atomic->compareAndSet(12, 20) ? 'OK' : 'FAIL') . "\n";
echo "  CAS(12, 30): " . ($atomic->compareAndSet(12, 30) ? 'OK' : 'FAIL') . "\n";
echo "  Decrement: " . $atomic->decrement() . "\n";
echo "  Current: " . $atomic->get() . "\n";
echo "  History entries: " . count($atomic->getHistory()) . "\n";

echo "\n--- Concurrent Queue ---\n";
$queue = new ConcurrentQueue();
for ($i = 0; $i < 5; $i++) {
    $queue->push("item_$i");
}
echo "  Queue size: " . $queue->size() . "\n";
while (!$queue->isEmpty()) {
    echo "  Popped: " . $queue->pop() . "\n";
}

echo "\n--- Simulated Concurrent Counter ---\n";
$counter = new AtomicInteger();
$counter->set(100);

// 模拟多个 "线程" 并发递增
$threads = 5;
$incrementsPerThread = 20;
for ($t = 0; $t < $threads; $t++) {
    for ($i = 0; $i < $incrementsPerThread; $i++) {
        $counter->increment();
    }
}
echo "  After $threads threads x $incrementsPerThread increments:\n";
echo "  Expected: " . (100 + $threads * $incrementsPerThread) . "\n";
echo "  Actual: " . $counter->get() . "\n";

echo "=== f173 Done ===\n";
