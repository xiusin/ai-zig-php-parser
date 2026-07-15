<?php
// 极度混搭: 信号处理 + 协程调度模拟 + 通道通信 + select模拟 + 超时
echo "=== c030: Signal Handling + Coroutine Sim + Channel + Select ===\n\n";

class Signal {
    private int $count = 0;
    private array $waiters = [];

    public function signal(int $n = 1): void {
        $this->count += $n;
        $woken = array_slice($this->waiters, 0, $n);
        $this->waiters = array_slice($this->waiters, $n);
        foreach ($woken as $w) {
            $w['woken'] = true;
        }
    }

    public function wait(): bool {
        if ($this->count > 0) {
            $this->count--;
            return true;
        }
        $this->waiters[] = ['woken' => false];
        return false;
    }

    public function getCount(): int {
        return $this->count;
    }

    public function getWaiterCount(): int {
        return count($this->waiters);
    }
}

class Channel {
    private array $buffer = [];
    private int $capacity;
    private bool $closed = false;
    private array $sendQueue = [];
    private array $recvQueue = [];

    public function __construct(int $capacity = 0) {
        $this->capacity = $capacity;
    }

    public function send(mixed $value): bool {
        if ($this->closed) return false;
        if (count($this->buffer) >= $this->capacity) {
            $this->sendQueue[] = $value;
            return false;
        }
        $this->buffer[] = $value;
        return true;
    }

    public function receive(): mixed {
        if (!empty($this->buffer)) {
            return array_shift($this->buffer);
        }
        if (!empty($this->sendQueue)) {
            $val = array_shift($this->sendQueue);
            $this->buffer[] = $val;
            return array_shift($this->buffer);
        }
        return null;
    }

    public function close(): void {
        $this->closed = true;
    }

    public function isClosed(): bool {
        return $this->closed;
    }

    public function size(): int {
        return count($this->buffer) + count($this->sendQueue);
    }

    public function pendingSend(): int {
        return count($this->sendQueue);
    }
}

class Coroutine {
    private static int $nextId = 1;
    public readonly int $id;
    private $resumeFn;
    private string $state = 'created';
    private mixed $yielded = null;

    public function __construct(callable $fn) {
        $this->id = self::$nextId++;
        $this->resumeFn = $fn;
    }

    public function start(mixed $initial = null): mixed {
        $this->state = 'running';
        $result = ($this->resumeFn)($initial);
        $this->state = 'suspended';
        $this->yielded = $result;
        return $result;
    }

    public function resume(mixed $value = null): mixed {
        $this->state = 'running';
        $result = ($this->resumeFn)($value);
        $this->state = 'suspended';
        $this->yielded = $result;
        return $result;
    }

    public function getState(): string {
        return $this->state;
    }

    public function getYielded(): mixed {
        return $this->yielded;
    }
}

class Scheduler {
    private array $coroutines = [];
    private array $ready = [];
    private int $tick = 0;

    public function add(Coroutine $co): self {
        $this->coroutines[$co->id] = $co;
        $this->ready[] = $co->id;
        return $this;
    }

    public function run(int $maxTicks = 100): void {
        while (!empty($this->ready) && $this->tick < $maxTicks) {
            $this->tick++;
            $coId = array_shift($this->ready);
            $co = $this->coroutines[$coId] ?? null;
            if ($co === null) continue;

            $result = $co->start($this->tick);
            echo "  [tick={$this->tick}] Coroutine #{$co->id} yielded: " . var_export($result, true) . "\n";

            if ($co->getState() !== 'done') {
                $this->ready[] = $coId;
            }
        }
    }

    public function getCoroutineCount(): int {
        return count($this->coroutines);
    }

    public function getTick(): int {
        return $this->tick;
    }
}

// === 测试 ===

echo "--- Signal (Counting Semaphore) ---\n";
$sig = new Signal();
echo "Initial count: " . $sig->getCount() . "\n";
$sig->signal(3);
echo "After signal(3): " . $sig->getCount() . "\n";
echo "Wait: " . var_export($sig->wait(), true) . "\n";
echo "Wait: " . var_export($sig->wait(), true) . "\n";
echo "After 2 waits: " . $sig->getCount() . "\n";
echo "Wait: " . var_export($sig->wait(), true) . "\n";
echo "After 3 waits: " . $sig->getCount() . "\n";

echo "\n--- Channel (Buffered) ---\n";
$ch = new Channel(3);
$ch->send('msg1');
$ch->send('msg2');
$ch->send('msg3');
echo "Buffer size: " . $ch->size() . "\n";
echo "Receive: " . $ch->receive() . "\n";
echo "Receive: " . $ch->receive() . "\n";
echo "Buffer size: " . $ch->size() . "\n";

echo "\n--- Channel (Unbuffered) ---\n";
$unbufCh = new Channel(0);
$unbufCh->send('data1');
echo "Pending send: " . $unbufCh->pendingSend() . "\n";
echo "Receive: " . $unbufCh->receive() . "\n";
$unbufCh->close();
echo "Closed: " . var_export($unbufCh->isClosed(), true) . "\n";

echo "\n--- Coroutine Simulation ---\n";
$co1 = new Coroutine(function($tick) {
    return "tick=$tick from CO1";
});
$co2 = new Coroutine(function($tick) {
    return "tick=$tick from CO2";
});

$result1 = $co1->start(1);
echo "CO1 first run: $result1\n";
$result2 = $co2->start(1);
echo "CO2 first run: $result2\n";
$result3 = $co1->start(2);
echo "CO1 resume: $result3\n";

echo "\n--- Scheduler Round-Robin ---\n";
$sched = new Scheduler();
$sched->add(new Coroutine(function($tick) { return "A:$tick"; }));
$sched->add(new Coroutine(function($tick) { return "B:$tick"; }));
$sched->add(new Coroutine(function($tick) { return "C:$tick"; }));
$sched->run(9);
echo "Total ticks: " . $sched->getTick() . "\n";
echo "Coroutines: " . $sched->getCoroutineCount() . "\n";

echo "\n--- Producer-Consumer Pattern ---\n";
$buffer = new Channel(5);
$produced = [];
for ($i = 1; $i <= 5; $i++) {
    $buffer->send("item-$i");
    $produced[] = "item-$i";
}
echo "Produced: " . implode(", ", $produced) . "\n";
$consumed = [];
while (($item = $buffer->receive()) !== null) {
    $consumed[] = $item;
}
echo "Consumed: " . implode(", ", $consumed) . "\n";
echo "Match: " . var_export($produced === $consumed, true) . "\n";

echo "\n=== c030 Done ===\n";
