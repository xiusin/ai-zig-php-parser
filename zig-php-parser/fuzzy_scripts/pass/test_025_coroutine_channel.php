<?php
// 测试25: 协程与通道模拟测试
class Channel {
    private $buffer = [];
    private $capacity;
    
    public function __construct(int $capacity = 0) {
        $this->capacity = $capacity;
    }
    
    public function send($value): void {
        $this->buffer[] = $value;
    }
    
    public function recv() {
        if (empty($this->buffer)) {
            return null;
        }
        return array_shift($this->buffer);
    }
    
    public function isEmpty(): bool {
        return empty($this->buffer);
    }
    
    public function size(): int {
        return count($this->buffer);
    }
}

class CoroutineScheduler {
    private $coroutines = [];
    private $current = 0;
    
    public function add(callable $fn, ...$args): void {
        $this->coroutines[] = ['fn' => $fn, 'args' => $args, 'done' => false];
    }
    
    public function run(): void {
        while (true) {
            $allDone = true;
            foreach ($this->coroutines as &$coro) {
                if (!$coro['done']) {
                    $allDone = false;
                    $result = ($coro['fn'])(...$coro['args']);
                    if ($result === null) {
                        $coro['done'] = true;
                    }
                }
            }
            if ($allDone) break;
        }
    }
}

// 生产者消费者测试
$channel = new Channel(10);

function producer(Channel $ch, int $id, int $count): callable {
    $sent = 0;
    return function() use ($ch, $id, $count, &$sent) {
        if ($sent < $count) {
            $value = "P$id-Item$sent";
            $ch->send($value);
            echo "Producer $id sent: $value\n";
            $sent++;
            return true;
        }
        return null;
    };
}

function consumer(Channel $ch, int $id, int $count): callable {
    $received = 0;
    return function() use ($ch, $id, $count, &$received) {
        if ($received < $count) {
            $value = $ch->recv();
            if ($value !== null) {
                echo "Consumer $id received: $value\n";
                $received++;
            }
            return true;
        }
        return null;
    };
}

$scheduler = new CoroutineScheduler();
$scheduler->add(producer($channel, 1, 3));
$scheduler->add(producer($channel, 2, 3));
$scheduler->add(consumer($channel, 1, 4));
$scheduler->add(consumer($channel, 2, 2));
$scheduler->run();

echo "Channel size after processing: " . $channel->size() . "\n";

// 协程锁测试
class CoroutineLock {
    private $locked = false;
    private $waitQueue = [];
    
    public function lock(): bool {
        if ($this->locked) {
            return false;
        }
        $this->locked = true;
        return true;
    }
    
    public function unlock(): void {
        $this->locked = false;
    }
    
    public function isLocked(): bool {
        return $this->locked;
    }
}

$lock = new CoroutineLock();
$sharedData = 0;

function lockedIncrement(CoroutineLock $lock, int &$data, int $times): callable {
    $count = 0;
    return function() use ($lock, &$data, $times, &$count) {
        if ($count < $times) {
            if ($lock->lock()) {
                $old = $data;
                $data++;
                echo "Incremented: $old -> $data\n";
                $lock->unlock();
                $count++;
            }
            return true;
        }
        return null;
    };
}

$scheduler2 = new CoroutineScheduler();
$scheduler2->add(lockedIncrement($lock, $sharedData, 5));
$scheduler2->add(lockedIncrement($lock, $sharedData, 5));
$scheduler2->run();

echo "Final shared data: $sharedData\n";
?>