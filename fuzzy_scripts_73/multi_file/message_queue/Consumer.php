<?php

class Consumer {
    public readonly string $id;
    public string $name;
    private $handler;
    private int $processedCount = 0;
    private int $errorCount = 0;
    private array $processingTimes = [];
    private bool $active = true;

    public function __construct(string $name, callable $handler) {
        $this->id = 'CONS' . substr(md5($name . uniqid()), 0, 8);
        $this->name = $name;
        $this->handler = $handler;
    }

    public function process(Message $message): bool {
        if (!$this->active) return false;

        $start = microtime(true);
        try {
            $result = ($this->handler)($message);
            $elapsed = (microtime(true) - $start) * 1000;
            $this->processingTimes[] = $elapsed;
            $this->processedCount++;

            if ($result === false) {
                $this->errorCount++;
                return false;
            }
            return true;
        } catch (Throwable $e) {
            $this->errorCount++;
            return false;
        }
    }

    public function getProcessedCount(): int { return $this->processedCount; }
    public function getErrorCount(): int { return $this->errorCount; }
    public function isActive(): bool { return $this->active; }

    public function pause(): void { $this->active = false; }
    public function resume(): void { $this->active = true; }

    public function getAverageProcessingTime(): float {
        if (empty($this->processingTimes)) return 0.0;
        return array_sum($this->processingTimes) / count($this->processingTimes);
    }

    public function getStats(): array {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'processed' => $this->processedCount,
            'errors' => $this->errorCount,
            'active' => $this->active,
            'avgTimeMs' => round($this->getAverageProcessingTime(), 3),
        ];
    }
}

class Producer {
    public readonly string $id;
    public string $name;
    private int $producedCount = 0;

    public function __construct(string $name) {
        $this->id = 'PROD' . substr(md5($name . uniqid()), 0, 8);
        $this->name = $name;
    }

    public function produce(MessageQueue $queue, string $body, array $headers = [], int $priority = 5): ?Message {
        $message = new Message($queue->getName(), $body, $headers, $priority);
        if ($queue->enqueue($message)) {
            $this->producedCount++;
            return $message;
        }
        return null;
    }

    public function produceBatch(MessageQueue $queue, array $messages): int {
        $count = 0;
        foreach ($messages as $msg) {
            $body = is_string($msg) ? $msg : ($msg['body'] ?? '');
            $headers = is_array($msg) ? ($msg['headers'] ?? []) : [];
            $priority = is_array($msg) ? ($msg['priority'] ?? 5) : 5;

            if ($this->produce($queue, $body, $headers, $priority) !== null) {
                $count++;
            }
        }
        return $count;
    }

    public function getProducedCount(): int { return $this->producedCount; }

    public function getStats(): array {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'produced' => $this->producedCount,
        ];
    }
}
