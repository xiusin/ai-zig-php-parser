<?php

class QueueManager {
    private array $queues = [];
    private array $consumers = [];
    private array $producers = [];
    private array $routes = [];
    private array $stats = ['totalEnqueued' => 0, 'totalDequeued' => 0, 'totalAcked' => 0, 'totalFailed' => 0];

    public function createQueue(string $name, int $maxRetries = 3, int $maxSize = 10000): MessageQueue {
        if (isset($this->queues[$name])) {
            throw new RuntimeException("Queue '$name' already exists");
        }
        $queue = new MessageQueue($name, $maxRetries, $maxSize);
        $this->queues[$name] = $queue;
        return $queue;
    }

    public function getQueue(string $name): ?MessageQueue {
        return $this->queues[$name] ?? null;
    }

    public function deleteQueue(string $name): bool {
        if (!isset($this->queues[$name])) return false;
        unset($this->queues[$name]);
        return true;
    }

    public function registerConsumer(string $name, callable $handler): Consumer {
        $consumer = new Consumer($name, $handler);
        $this->consumers[$consumer->id] = $consumer;
        return $consumer;
    }

    public function registerProducer(string $name): Producer {
        $producer = new Producer($name);
        $this->producers[$producer->id] = $producer;
        return $producer;
    }

    public function bindConsumer(string $queueName, string $consumerId): void {
        $this->routes[$queueName][] = $consumerId;
    }

    public function dispatch(string $queueName, int $maxMessages = 100): array {
        $queue = $this->getQueue($queueName);
        if ($queue === null) return [];

        $consumerIds = $this->routes[$queueName] ?? [];
        if (empty($consumerIds)) return [];

        $results = [];
        $dispatched = 0;

        while ($dispatched < $maxMessages) {
            $message = $queue->dequeue();
            if ($message === null) break;

            // 轮询消费者
            $consumerId = $consumerIds[$dispatched % count($consumerIds)];
            $consumer = $this->consumers[$consumerId] ?? null;

            if ($consumer === null || !$consumer->isActive()) {
                $queue->requeue($message);
                break;
            }

            $success = $consumer->process($message);

            if ($success) {
                $queue->ack($message->id);
                $this->stats['totalAcked']++;
            } else {
                $queue->nack($message->id);
                $this->stats['totalFailed']++;
            }

            $results[] = [
                'messageId' => $message->id,
                'consumer' => $consumer->name,
                'success' => $success,
            ];

            $dispatched++;
        }

        $this->stats['totalDequeued'] += $dispatched;
        return $results;
    }

    public function getQueues(): array { return $this->queues; }
    public function getConsumers(): array { return $this->consumers; }
    public function getProducers(): array { return $this->producers; }
    public function getStats(): array { return $this->stats; }

    public function getQueueStats(): array {
        $result = [];
        foreach ($this->queues as $name => $queue) {
            $result[$name] = $queue->toArray();
        }
        return $result;
    }

    public function getConsumerStats(): array {
        return array_map(fn($c) => $c->getStats(), $this->consumers);
    }

    public function getProducerStats(): array {
        return array_map(fn($p) => $p->getStats(), $this->producers);
    }

    public function purgeAll(): int {
        $total = 0;
        foreach ($this->queues as $queue) {
            $total += $queue->purge();
        }
        return $total;
    }
}
