<?php
// 极度混搭: 消息队列 + 发布订阅 + 消费者组 + 死信队列 + 延迟消息
echo "=== f069: Message Queue + PubSub + DeadLetter + Delay ===\n";

class Message {
    public function __construct(
        public string $id,
        public string $topic,
        public mixed $payload,
        public int $createdAt = 0,
        public int $deliverAt = 0,
        public int $retryCount = 0,
    ) {
        $this->createdAt = $this->createdAt ?: time();
    }
}

class MessageQueue {
    private array $queues = []; // topic → array of Message
    private array $deadLetter = [];
    private int $maxRetries = 3;
    private int $seq = 0;

    public function publish(string $topic, mixed $payload, int $delay = 0): string {
        $id = 'msg-' . (++$this->seq);
        $msg = new Message($id, $topic, $payload, time(), $delay > 0 ? time() + $delay : 0);
        if (!isset($this->queues[$topic])) $this->queues[$topic] = [];
        $this->queues[$topic][] = $msg;
        return $id;
    }

    public function consume(string $topic, callable $handler, int $max = 10): array {
        $results = [];
        if (!isset($this->queues[$topic])) return $results;
        $now = time();
        $remaining = [];
        foreach ($this->queues[$topic] as $msg) {
            if (count($results) >= $max) { $remaining[] = $msg; continue; }
            if ($msg->deliverAt > 0 && $msg->deliverAt > $now) {
                $remaining[] = $msg; // 延迟消息未到期
                continue;
            }
            try {
                $handler($msg);
                $results[] = ['id' => $msg->id, 'status' => 'processed'];
            } catch (Exception $e) {
                $msg->retryCount++;
                if ($msg->retryCount >= $this->maxRetries) {
                    $this->deadLetter[] = $msg;
                    $results[] = ['id' => $msg->id, 'status' => 'dead_letter', 'error' => $e->getMessage()];
                } else {
                    $msg->deliverAt = time() + $msg->retryCount * 2; // 指数退避
                    $remaining[] = $msg;
                    $results[] = ['id' => $msg->id, 'status' => 'retry', 'retry' => $msg->retryCount, 'error' => $e->getMessage()];
                }
            }
        }
        $this->queues[$topic] = $remaining;
        return $results;
    }

    public function getDeadLetters(): array { return $this->deadLetter; }
    public function getQueueSize(string $topic): int { return count($this->queues[$topic] ?? []); }
    public function getTopics(): array { return array_keys($this->queues); }
}

class PubSub {
    private array $subscribers = []; // topic → array of callables
    private array $history = [];

    public function subscribe(string $topic, callable $handler): string {
        if (!isset($this->subscribers[$topic])) $this->subscribers[$topic] = [];
        $id = 'sub-' . count($this->subscribers[$topic]);
        $this->subscribers[$topic][$id] = $handler;
        return $id;
    }

    public function unsubscribe(string $topic, string $subId): void {
        unset($this->subscribers[$topic][$subId]);
    }

    public function publish(string $topic, mixed $data): int {
        $delivered = 0;
        if (isset($this->subscribers[$topic])) {
            foreach ($this->subscribers[$topic] as $handler) {
                $handler($data);
                $delivered++;
            }
        }
        $this->history[] = ['topic' => $topic, 'data' => $data, 'delivered' => $delivered, 'time' => time()];
        return $delivered;
    }

    public function getHistory(int $limit = 10): array {
        return array_slice($this->history, -$limit);
    }

    public function getSubscriberCount(string $topic): int {
        return count($this->subscribers[$topic] ?? []);
    }
}

// 测试
echo "--- Message Queue ---\n";
$mq = new MessageQueue();
$mq->publish('orders', ['id' => 1, 'item' => 'book']);
$mq->publish('orders', ['id' => 2, 'item' => 'pen']);
$mq->publish('orders', ['id' => 3, 'item' => 'laptop']);
$mq->publish('notifications', ['msg' => 'Welcome!']);
echo "Queue sizes: orders=" . $mq->getQueueSize('orders') . " notifications=" . $mq->getQueueSize('notifications') . "\n";
echo "Topics: " . json_encode($mq->getTopics()) . "\n";

echo "\n--- Consume Orders ---\n";
$processed = $mq->consume('orders', function($msg) {
    echo "  Processing: " . json_encode($msg->payload) . "\n";
});
echo "Results: " . json_encode($processed) . "\n";

echo "\n--- Retry & Dead Letter ---\n";
$mq2 = new MessageQueue();
$mq2->publish('flaky', 'task1');
$mq2->publish('flaky', 'task2');
$mq2->publish('flaky', 'task3');

$attempt = 0;
$results1 = $mq2->consume('flaky', function($msg) use (&$attempt) {
    $attempt++;
    if ($msg->retryCount < 2) throw new RuntimeException("Failed attempt");
    echo "  Success: {$msg->payload}\n";
});
echo "First pass:\n";
foreach ($results1 as $r) echo "  " . json_encode($r) . "\n";

// 再次消费重试
$results2 = $mq2->consume('flaky', function($msg) {
    if ($msg->retryCount < 2) throw new RuntimeException("Still failing");
    echo "  Success on retry: {$msg->payload}\n";
});
echo "Second pass:\n";
foreach ($results2 as $r) echo "  " . json_encode($r) . "\n";

// 第三次让所有失败
$results3 = $mq2->consume('flaky', function($msg) {
    throw new RuntimeException("Always fails");
});
echo "Third pass:\n";
foreach ($results3 as $r) echo "  " . json_encode($r) . "\n";

echo "\nDead letters: " . count($mq2->getDeadLetters()) . "\n";
foreach ($mq2->getDeadLetters() as $dl) {
    echo "  {$dl->id}: {$dl->payload} (retries={$dl->retryCount})\n";
}

echo "\n--- Delayed Messages ---\n";
$mq3 = new MessageQueue();
$mq3->publish('delayed', 'immediate');
$mq3->publish('delayed', 'delayed-1s', 1);
$mq3->publish('delayed', 'delayed-2s', 2);
echo "Queue size: " . $mq3->getQueueSize('delayed') . "\n";
$results = $mq3->consume('delayed', function($msg) { echo "  Got: {$msg->payload}\n"; });
echo "Consumed: " . count($results) . " (immediate only)\n";
sleep(2);
$results = $mq3->consume('delayed', function($msg) { echo "  Got: {$msg->payload}\n"; });
echo "Consumed after wait: " . count($results) . "\n";

echo "\n--- PubSub ---\n";
$ps = new PubSub();
$logs = [];
$sub1 = $ps->subscribe('news', function($data) use (&$logs) { $logs[] = "Sub1: $data"; });
$sub2 = $ps->subscribe('news', function($data) use (&$logs) { $logs[] = "Sub2: $data"; });
$ps->subscribe('alerts', function($data) use (&$logs) { $logs[] = "Alert: $data"; });

$ps->publish('news', 'Breaking: PHP AOT released!');
$ps->publish('alerts', 'System overload!');
$ps->publish('news', 'Update: v2.0');

$ps->unsubscribe('news', $sub1);
$ps->publish('news', 'After unsub');

echo "Logs:\n";
foreach ($logs as $log) echo "  $log\n";
echo "Subscribers: news=" . $ps->getSubscriberCount('news') . " alerts=" . $ps->getSubscriberCount('alerts') . "\n";

echo "=== f069 Done ===\n";
