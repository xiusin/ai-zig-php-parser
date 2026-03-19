<?php
// 测试27: 线程安全与并发数据结构
// 模拟原子操作
class AtomicCounter {
    private $value = 0;
    private $lock = false;
    
    public function increment(): int {
        while ($this->lock) {
            usleep(1);
        }
        $this->lock = true;
        $this->value++;
        $result = $this->value;
        $this->lock = false;
        return $result;
    }
    
    public function decrement(): int {
        while ($this->lock) {
            usleep(1);
        }
        $this->lock = true;
        $this->value--;
        $result = $this->value;
        $this->lock = false;
        return $result;
    }
    
    public function get(): int {
        return $this->value;
    }
    
    public function compareAndSwap(int $expected, int $new): bool {
        while ($this->lock) {
            usleep(1);
        }
        $this->lock = true;
        if ($this->value === $expected) {
            $this->value = $new;
            $this->lock = false;
            return true;
        }
        $this->lock = false;
        return false;
    }
}

// 测试原子计数器
$counter = new AtomicCounter();
$results = [];
for ($i = 0; $i < 10; $i++) {
    $results[] = $counter->increment();
}
echo "Atomic increments: " . implode(", ", $results) . "\n";
echo "Final value: " . $counter->get() . "\n";

// 线程安全队列
class ThreadSafeQueue {
    private $queue = [];
    private $lock = false;
    
    private function acquireLock(): void {
        while ($this->lock) {
            usleep(1);
        }
        $this->lock = true;
    }
    
    private function releaseLock(): void {
        $this->lock = false;
    }
    
    public function enqueue($item): void {
        $this->acquireLock();
        $this->queue[] = $item;
        $this->releaseLock();
    }
    
    public function dequeue() {
        $this->acquireLock();
        if (empty($this->queue)) {
            $this->releaseLock();
            return null;
        }
        $item = array_shift($this->queue);
        $this->releaseLock();
        return $item;
    }
    
    public function size(): int {
        $this->acquireLock();
        $size = count($this->queue);
        $this->releaseLock();
        return $size;
    }
}

$queue = new ThreadSafeQueue();
for ($i = 0; $i < 5; $i++) {
    $queue->enqueue("item-$i");
}
echo "Queue size: " . $queue->size() . "\n";
while (($item = $queue->dequeue()) !== null) {
    echo "Dequeued: $item\n";
}

// 读写锁模拟
class ReadWriteLock {
    private $readers = 0;
    private $writer = false;
    private $writerWaiting = 0;
    
    public function acquireRead(): void {
        while ($this->writer || $this->writerWaiting > 0) {
            usleep(1);
        }
        $this->readers++;
    }
    
    public function releaseRead(): void {
        $this->readers--;
    }
    
    public function acquireWrite(): void {
        $this->writerWaiting++;
        while ($this->readers > 0 || $this->writer) {
            usleep(1);
        }
        $this->writerWaiting--;
        $this->writer = true;
    }
    
    public function releaseWrite(): void {
        $this->writer = false;
    }
}

$rwLock = new ReadWriteLock();
$sharedResource = "initial";

// 模拟读操作
$rwLock->acquireRead();
echo "Reading: $sharedResource\n";
$rwLock->releaseRead();

// 模拟写操作
$rwLock->acquireWrite();
$sharedResource = "modified";
echo "Writing: $sharedResource\n";
$rwLock->releaseWrite();

echo "Final resource: $sharedResource\n";
?>
