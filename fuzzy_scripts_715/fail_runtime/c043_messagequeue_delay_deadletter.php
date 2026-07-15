<?php
// 极度混搭: 消息队列 + 延迟队列 + 死信队列 + 优先级 + 确认机制
echo "=== c043: MessageQueue + Delay + DeadLetter + Priority + ACK ===\n\n";

class Message {
    public string $id;
    public string $body;
    public int $priority;
    public int $timestamp;
    public int $deliveryCount = 0;
    public int $maxRetries = 3;
    public ?string $consumerId = null;
    public bool $acked = false;
    public ?int $delayUntil = null;

    public function __construct(string $body, int $priority = 0, ?int $delay = null) {
        $this->id = 'msg_' . substr(md5($body . $priority . time()), 0, 8);
        $this->body = $body;
        $this->priority = $priority;
        $this->timestamp = 1;
        if ($delay !== null) {
            $this->delayUntil = 1 + $delay;
        }
    }

    public function isReady(int $now): bool {
        return $this->delayUntil === null || $this->delayUntil <= $now;
    }

    public function canRetry(): bool {
        return $this->deliveryCount < $this->maxRetries;
    }
}

class MessageQueue {
    private array $messages = [];
    private array $processing = [];
    private array $deadLetterQueue = [];
    private array $delayed = [];
    private int $maxSize;
    private array $stats = ['enqueued' => 0, 'delivered' => 0, 'acked' => 0, 'nacked' => 0, 'dead' => 0];

    public function __construct(int $maxSize = 1000) {
        $this->maxSize = $maxSize;
    }

    public function enqueue(Message $msg): bool {
        if (count($this->messages) + count($this->delayed) >= $this->maxSize) {
            return false;
        }
        if ($msg->delayUntil !== null) {
            $this->delayed[] = $msg;
        } else {
            $this->insertByPriority($msg);
        }
        $this->stats['enqueued']++;
        return true;
    }

    private function insertByPriority(Message $msg): void {
        $inserted = false;
        for ($i = count($this->messages) - 1; $i >= 0; $i--) {
            if ($this->messages[$i]->priority >= $msg->priority) {
                array_splice($this->messages, $i + 1, 0, [$msg]);
                $inserted = true;
                break;
            }
        }
        if (!$inserted) {
            array_unshift($this->messages, $msg);
        }
    }

    public function dequeue(?string $consumerId = null, int $now = 1): ?Message {
        $this->processDelayed($now);

        if (empty($this->messages)) return null;

        $msg = array_shift($this->messages);
        $msg->deliveryCount++;
        $msg->consumerId = $consumerId;
        $this->processing[$msg->id] = $msg;
        $this->stats['delivered']++;
        return $msg;
    }

    public function ack(string $messageId): bool {
        if (!isset($this->processing[$messageId])) return false;
        $msg = $this->processing[$messageId];
        $msg->acked = true;
        unset($this->processing[$messageId]);
        $this->stats['acked']++;
        return true;
    }

    public function nack(string $messageId, bool $requeue = true): bool {
        if (!isset($this->processing[$messageId])) return false;
        $msg = $this->processing[$messageId];
        unset($this->processing[$messageId]);
        $this->stats['nacked']++;

        if ($requeue && $msg->canRetry()) {
            $this->insertByPriority($msg);
        } else {
            $this->deadLetterQueue[] = $msg;
            $this->stats['dead']++;
        }
        return true;
    }

    private function processDelayed(int $now): void {
        $remaining = [];
        foreach ($this->delayed as $msg) {
            if ($msg->isReady($now)) {
                $this->insertByPriority($msg);
            } else {
                $remaining[] = $msg;
            }
        }
        $this->delayed = $remaining;
    }

    public function expireProcessing(int $now, int $timeout = 30): int {
        $expired = 0;
        foreach ($this->processing as $id => $msg) {
            if ($now - $msg->timestamp > $timeout) {
                unset($this->processing[$id]);
                if ($msg->canRetry()) {
                    $this->insertByPriority($msg);
                } else {
                    $this->deadLetterQueue[] = $msg;
                    $this->stats['dead']++;
                }
                $expired++;
            }
        }
        return $expired;
    }

    public function getStats(): array {
        return array_merge($this->stats, [
            'pending' => count($this->messages),
            'processing' => count($this->processing),
            'delayed' => count($this->delayed),
            'dead_letter' => count($this->deadLetterQueue),
        ]);
    }

    public function getDeadLetters(): array {
        return $this->deadLetterQueue;
    }
}

class Consumer {
    private string $id;
    private MessageQueue $queue;
    private array $processed = [];

    public function __construct(string $id, MessageQueue $queue) {
        $this->id = $id;
        $this->queue = $queue;
    }

    public function consume(): ?Message {
        $msg = $this->queue->dequeue($this->id);
        if ($msg === null) return null;
        $this->processed[] = $msg;
        return $msg;
    }

    public function acknowledge(string $messageId): void {
        $this->queue->ack($messageId);
    }

    public function reject(string $messageId, bool $requeue = true): void {
        $this->queue->nack($messageId, $requeue);
    }

    public function getProcessedCount(): int {
        return count($this->processed);
    }

    public function getId(): string {
        return $this->id;
    }
}

// === 测试 ===

echo "--- Basic Queue Operations ---\n";
$queue = new MessageQueue(100);

$queue->enqueue(new Message("Task A", 1));
$queue->enqueue(new Message("Task B", 5));
$queue->enqueue(new Message("Task C", 3));
$queue->enqueue(new Message("Task D", 5));
$queue->enqueue(new Message("Task E", 1));

echo "Stats: " . json_encode($queue->getStats()) . "\n";

echo "\n--- Priority Dequeue ---\n";
while (($msg = $queue->dequeue()) !== null) {
    echo "  Dequeued: {$msg->body} (priority={$msg->priority})\n";
    $queue->ack($msg->id);
}
echo "Stats: " . json_encode($queue->getStats()) . "\n";

echo "\n--- ACK/NACK + Retry ---\n";
$queue2 = new MessageQueue(100);
$queue2->enqueue(new Message("Risky Task", 10));

$consumer = new Consumer("worker-1", $queue2);
$msg = $consumer->consume();
echo "Got: {$msg->body} (attempt={$msg->deliveryCount})\n";
$consumer->reject($msg->id, true);

$msg2 = $consumer->consume();
echo "Got: {$msg2->body} (attempt={$msg2->deliveryCount})\n";
$consumer->reject($msg2->id, true);

$msg3 = $consumer->consume();
echo "Got: {$msg3->body} (attempt={$msg3->deliveryCount})\n";
$consumer->reject($msg3->id, true);

$msg4 = $consumer->consume();
echo "Got: " . ($msg4 ? "{$msg4->body} (attempt={$msg4->deliveryCount})" : "null") . "\n";
$consumer->reject($msg4->id, false); // No requeue -> dead letter

echo "Stats: " . json_encode($queue2->getStats()) . "\n";
echo "Dead letters: " . count($queue2->getDeadLetters()) . "\n";

echo "\n--- Delayed Messages ---\n";
$queue3 = new MessageQueue(100);
$queue3->enqueue(new Message("Immediate", 5));
$queue3->enqueue(new Message("Delayed 5", 5, 5));
$queue3->enqueue(new Message("Delayed 10", 5, 10));

echo "At t=1:\n";
$msg = $queue3->dequeue(null, 1);
echo "  Got: " . ($msg ? $msg->body : "none") . "\n";
if ($msg) $queue3->ack($msg->id);

echo "At t=6:\n";
$msg = $queue3->dequeue(null, 6);
echo "  Got: " . ($msg ? $msg->body : "none") . "\n";
if ($msg) $queue3->ack($msg->id);

echo "At t=11:\n";
$msg = $queue3->dequeue(null, 11);
echo "  Got: " . ($msg ? $msg->body : "none") . "\n";
if ($msg) $queue3->ack($msg->id);

echo "Stats: " . json_encode($queue3->getStats()) . "\n";

echo "\n--- Multiple Consumers ---\n";
$queue4 = new MessageQueue(100);
for ($i = 1; $i <= 10; $i++) {
    $queue4->enqueue(new Message("Job-$i", $i % 3 + 1));
}

$c1 = new Consumer("c1", $queue4);
$c2 = new Consumer("c2", $queue4);

while (true) {
    $msg = $c1->consume();
    if ($msg === null) break;
    $c1->ack($msg->id);
    $msg = $c2->consume();
    if ($msg === null) break;
    $c2->ack($msg->id);
}

echo "c1 processed: " . $c1->getProcessedCount() . "\n";
echo "c2 processed: " . $c2->getProcessedCount() . "\n";
echo "Stats: " . json_encode($queue4->getStats()) . "\n";

echo "\n=== c043 Done ===\n";
