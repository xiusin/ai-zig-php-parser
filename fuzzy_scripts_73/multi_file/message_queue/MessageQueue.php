<?php

class MessageQueue {
    private string $name;
    private array $messages = [];
    private array $deadLetterQueue = [];
    private int $maxRetries;
    private int $maxSize;
    private array $stats = [
        'enqueued' => 0,
        'dequeued' => 0,
        'acked' => 0,
        'nacked' => 0,
        'failed' => 0,
        'expired' => 0,
    ];
    private int $totalSize = 0;

    public function __construct(string $name, int $maxRetries = 3, int $maxSize = 10000) {
        $this->name = $name;
        $this->maxRetries = $maxRetries;
        $this->maxSize = $maxSize;
    }

    public function enqueue(Message $message): bool {
        if ($this->totalSize >= $this->maxSize) return false;

        $this->messages[] = $message;
        $this->totalSize++;
        $this->stats['enqueued']++;

        // 按优先级排序（高优先级在前）
        usort($this->messages, fn($a, $b) => $b->priority <=> $a->priority);
        return true;
    }

    public function dequeue(): ?Message {
        if (empty($this->messages)) return null;

        $message = array_shift($this->messages);
        $message->markDelivered();
        $this->stats['dequeued']++;
        return $message;
    }

    public function ack(string $messageId): bool {
        $this->stats['acked']++;
        return true;
    }

    public function nack(string $messageId, string $reason = ''): bool {
        $this->stats['nacked']++;

        // 重新入队或进入死信队列
        foreach ($this->messages as $i => $msg) {
            if ($msg->id === $messageId) {
                if ($msg->deliveryCount >= $this->maxRetries) {
                    $this->deadLetterQueue[] = $msg;
                    $msg->markFailed();
                    $this->stats['failed']++;
                    unset($this->messages[$i]);
                    $this->messages = array_values($this->messages);
                }
                return true;
            }
        }
        return false;
    }

    public function requeue(Message $message): bool {
        if ($message->deliveryCount >= $this->maxRetries) {
            $this->deadLetterQueue[] = $message;
            $message->markFailed();
            $this->stats['failed']++;
            return false;
        }

        $message->status = 'pending';
        $this->messages[] = $message;
        usort($this->messages, fn($a, $b) => $b->priority <=> $a->priority);
        return true;
    }

    public function peek(int $n = 1): array {
        return array_slice($this->messages, 0, $n);
    }

    public function purge(): int {
        $count = count($this->messages);
        $this->messages = [];
        $this->totalSize = 0;
        return $count;
    }

    public function getName(): string { return $this->name; }
    public function getSize(): int { return count($this->messages); }
    public function getStats(): array { return $this->stats; }
    public function getDeadLetterQueue(): array { return $this->deadLetterQueue; }
    public function getDeadLetterCount(): int { return count($this->deadLetterQueue); }

    public function getMessagesByPriority(int $priority): array {
        return array_values(array_filter($this->messages, fn($m) => $m->priority === $priority));
    }

    public function toArray(): array {
        return [
            'name' => $this->name,
            'size' => $this->getSize(),
            'deadLetters' => $this->getDeadLetterCount(),
            'stats' => $this->stats,
        ];
    }
}
