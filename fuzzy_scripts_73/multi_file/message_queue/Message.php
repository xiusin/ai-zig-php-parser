<?php

class Message {
    public readonly string $id;
    public readonly string $queueName;
    public readonly string $body;
    public readonly array $headers;
    public readonly int $priority;
    public readonly int $createdAt;
    public int $deliveryCount = 0;
    public ?int $deliveredAt = null;
    public string $status;

    private static int $idCounter = 0;

    public function __construct(
        string $queueName,
        string $body,
        array $headers = [],
        int $priority = 5
    ) {
        $this->id = 'MSG' . str_pad((string)(++self::$idCounter), 10, '0', STR_PAD_LEFT);
        $this->queueName = $queueName;
        $this->body = $body;
        $this->headers = $headers;
        $this->priority = max(1, min(10, $priority));
        $this->createdAt = time();
        $this->status = 'pending';
    }

    public function markDelivered(): void {
        $this->deliveryCount++;
        $this->deliveredAt = time();
        $this->status = 'delivered';
    }

    public function markAcked(): void { $this->status = 'acked'; }
    public function markNacked(): void { $this->status = 'nacked'; }
    public function markFailed(): void { $this->status = 'failed'; }

    public function isPending(): bool { return $this->status === 'pending'; }
    public function isDelivered(): bool { return $this->status === 'delivered'; }
    public function isAcked(): bool { return $this->status === 'acked'; }

    public function getAge(): int { return time() - $this->createdAt; }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'queue' => $this->queueName,
            'body' => $this->body,
            'priority' => $this->priority,
            'status' => $this->status,
            'deliveryCount' => $this->deliveryCount,
            'age' => $this->getAge(),
        ];
    }
}
