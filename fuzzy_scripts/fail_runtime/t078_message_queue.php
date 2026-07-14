<?php
// 消息队列：生产者-消费者模式、优先级队列、延迟队列

class Message {
    public function __construct(
        public string $id,
        public string $content,
        public int $priority = 0,
        public int $timestamp = 0
    ) {}
}

class MessageQueue {
    private array $queue = [];
    private int $maxSize;

    public function __construct(int $maxSize = 100) {
        $this->maxSize = $maxSize;
    }

    public function push(Message $msg): bool {
        if (count($this->queue) >= $this->maxSize) return false;
        $this->queue[] = $msg;
        $this->sortByPriority();
        return true;
    }

    public function pop(): ?Message {
        if (count($this->queue) === 0) return null;
        return array_shift($this->queue);
    }

    public function peek(): ?Message {
        return $this->queue[0] ?? null;
    }

    public function count(): int {
        return count($this->queue);
    }

    public function isEmpty(): bool {
        return count($this->queue) === 0;
    }

    public function clear(): void {
        $this->queue = [];
    }

    private function sortByPriority(): void {
        usort($this->queue, fn($a, $b) => $b->priority <=> $a->priority);
    }
}

class Producer {
    private MessageQueue $queue;
    private int $counter = 0;

    public function __construct(MessageQueue $queue) {
        $this->queue = $queue;
    }

    public function produce(string $content, int $priority = 0): ?Message {
        $this->counter++;
        $msg = new Message("msg_{$this->counter}", $content, $priority, time());
        if ($this->queue->push($msg)) {
            return $msg;
        }
        return null;
    }
}

class Consumer {
    private MessageQueue $queue;
    private array $processed = [];

    public function __construct(MessageQueue $queue) {
        $this->queue = $queue;
    }

    public function consume(): ?Message {
        $msg = $this->queue->pop();
        if ($msg !== null) {
            $this->processed[] = $msg;
        }
        return $msg;
    }

    public function consumeAll(): array {
        $messages = [];
        while (!$this->queue->isEmpty()) {
            $msg = $this->consume();
            if ($msg !== null) $messages[] = $msg;
        }
        return $messages;
    }

    public function processedCount(): int {
        return count($this->processed);
    }
}

// 创建队列
$queue = new MessageQueue(50);
$producer = new Producer($queue);
$consumer = new Consumer($queue);

// 生产消息
$producer->produce("Task A", 1);
$producer->produce("Task B", 3);
$producer->produce("Task C", 2);
$producer->produce("Task D", 5);
$producer->produce("Task E", 1);
$producer->produce("Task F", 4);

echo "pending: " . $queue->count() . "\n";

// 消费消息（按优先级）
$msg = $consumer->consume();
echo "first_consumed: " . $msg->content . " (priority=" . $msg->priority . ")\n";

$msg = $consumer->consume();
echo "second_consumed: " . $msg->content . " (priority=" . $msg->priority . ")\n";

// 消费剩余
$remaining = $consumer->consumeAll();
echo "remaining_count: " . count($remaining) . "\n";
echo "total_processed: " . $consumer->processedCount() . "\n";

// 测试空队列
echo "is_empty: " . ($queue->isEmpty() ? 'true' : 'false') . "\n";
echo "pop_empty: " . ($queue->pop() === null ? 'null' : 'not null') . "\n";

// 测试队列满
$smallQueue = new MessageQueue(2);
$smallQueue->push(new Message("1", "A"));
$smallQueue->push(new Message("2", "B"));
echo "full_push: " . ($smallQueue->push(new Message("3", "C")) ? 'true' : 'false') . "\n";
echo "full_count: " . $smallQueue->count() . "\n";

// 测试优先级排序
$priorityQueue = new MessageQueue(50);
$priorityQueue->push(new Message("low", "Low", 1));
$priorityQueue->push(new Message("high", "High", 10));
$priorityQueue->push(new Message("med", "Medium", 5));

$first = $priorityQueue->pop();
echo "priority_first: " . $first->content . "\n";

$second = $priorityQueue->pop();
echo "priority_second: " . $second->content . "\n";

$third = $priorityQueue->pop();
echo "priority_third: " . $third->content . "\n";
