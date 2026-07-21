<?php
// 极度混搭: 消息队列 + Kafka模拟 + 消费者组 + 分区 + 偏移量
echo "=== f120: MessageQueue + Kafka + Partition + ConsumerGroup ===\n";

class Message {
    public function __construct(
        public string $topic,
        public int $partition,
        public string $key,
        public mixed $value,
        public int $offset = -1,
        public array $headers = [],
        public float $timestamp = 0
    ) {
        if ($this->timestamp === 0) $this->timestamp = microtime(true);
    }
}

class TopicPartition {
    public array $messages = [];
    public int $writeOffset = 0;
    public array $consumerOffsets = [];

    public function append(Message $msg): int {
        $msg->offset = $this->writeOffset;
        $this->messages[] = $msg;
        return $this->writeOffset++;
    }

    public function fetch(string $consumerId, int $maxMessages = 100): array {
        $offset = $this->consumerOffsets[$consumerId] ?? 0;
        $result = [];
        for ($i = $offset; $i < count($this->messages) && count($result) < $maxMessages; $i++) {
            $result[] = $this->messages[$i];
        }
        return $result;
    }

    public function commitOffset(string $consumerId, int $offset): void {
        $this->consumerOffsets[$consumerId] = $offset;
    }

    public function getOffset(string $consumerId): int { return $this->consumerOffsets[$consumerId] ?? 0; }
    public function getMessageCount(): int { return count($this->messages); }
}

class KafkaTopic {
    public array $partitions = [];

    public function __construct(public string $name, int $partitionCount = 3) {
        for ($i = 0; $i < $partitionCount; $i++) $this->partitions[$i] = new TopicPartition();
    }

    public function produce(string $key, mixed $value, array $headers = []): Message {
        $partition = $this->selectPartition($key);
        $msg = new Message($this->name, $partition, $key, $value, -1, $headers);
        $this->partitions[$partition]->append($msg);
        return $msg;
    }

    private function selectPartition(string $key): int {
        return abs(crc32($key)) % count($this->partitions);
    }

    public function getTotalMessages(): int {
        return array_sum(array_map(fn($p) => $p->getMessageCount(), $this->partitions));
    }
}

class ConsumerGroup {
    public array $assignments = []; // consumerId => [partitionIdx]
    private array $processed = [];
    private array $errors = [];

    public function __construct(public string $groupId, public KafkaTopic $topic) {}

    public function join(string $consumerId): void {
        $this->assignments[$consumerId] = [];
        $this->rebalance();
    }

    public function leave(string $consumerId): void {
        unset($this->assignments[$consumerId]);
        $this->rebalance();
    }

    private function rebalance(): void {
        $partitions = array_keys($this->topic->partitions);
        $consumers = array_keys($this->assignments);
        $consumerCount = count($consumers);
        if ($consumerCount === 0) return;
        foreach ($consumers as $i => $consumerId) {
            $assigned = [];
            for ($p = $i; $p < count($partitions); $p += $consumerCount) {
                $assigned[] = $partitions[$p];
            }
            $this->assignments[$consumerId] = $assigned;
        }
    }

    public function consume(string $consumerId, callable $processor): array {
        $results = [];
        foreach ($this->assignments[$consumerId] ?? [] as $partitionIdx) {
            $partition = $this->topic->partitions[$partitionIdx];
            $messages = $partition->fetch($consumerId, 10);
            foreach ($messages as $msg) {
                try {
                    $processor($msg);
                    $partition->commitOffset($consumerId, $msg->offset + 1);
                    $this->processed[] = ['consumer' => $consumerId, 'topic' => $msg->topic, 'partition' => $msg->partition, 'offset' => $msg->offset];
                    $results[] = ['status' => 'ok', 'offset' => $msg->offset];
                } catch (Exception $e) {
                    $this->errors[] = ['consumer' => $consumerId, 'offset' => $msg->offset, 'error' => $e->getMessage()];
                    $results[] = ['status' => 'error', 'offset' => $msg->offset, 'error' => $e->getMessage()];
                }
            }
        }
        return $results;
    }

    public function getAssignments(): array { return $this->assignments; }
    public function getProcessedCount(): int { return count($this->processed); }
    public function getErrorCount(): int { return count($this->errors); }
}

class KafkaSimulator {
    private array $topics = [];

    public function createTopic(string $name, int $partitions = 3): KafkaTopic {
        $this->topics[$name] = new KafkaTopic($name, $partitions);
        return $this->topics[$name];
    }

    public function getTopic(string $name): ?KafkaTopic { return $this->topics[$name] ?? null; }
    public function getTopics(): array { return array_keys($this->topics); }

    public function produce(string $topicName, string $key, mixed $value, array $headers = []): ?Message {
        $topic = $this->getTopic($topicName);
        if ($topic === null) return null;
        return $topic->produce($key, $value, $headers);
    }
}

// 测试
echo "--- Create Kafka Topics ---\n";
$kafka = new KafkaSimulator();
$ordersTopic = $kafka->createTopic('orders', 3);
$paymentsTopic = $kafka->createTopic('payments', 2);
echo "Topics: " . implode(', ', $kafka->getTopics()) . "\n";

echo "\n--- Produce Messages ---\n";
$customers = ['alice', 'bob', 'charlie', 'dave', 'eve'];
for ($i = 0; $i < 15; $i++) {
    $customer = $customers[$i % count($customers)];
    $order = ['order_id' => 1000 + $i, 'customer' => $customer, 'amount' => mt_rand(10, 500) + mt_rand(0, 99) / 100, 'items' => mt_rand(1, 5)];
    $msg = $kafka->produce('orders', $customer, $order, ['source' => 'web']);
    echo "  Produced: partition={$msg->partition} offset={$msg->offset} key=$customer\n";
}
echo "Total messages in 'orders': " . $ordersTopic->getTotalMessages() . "\n";

echo "\n--- Partition Distribution ---\n";
foreach ($ordersTopic->partitions as $idx => $partition) {
    echo "  Partition $idx: " . $partition->getMessageCount() . " messages\n";
}

echo "\n--- Consumer Group ---\n";
$group = new ConsumerGroup('order-processors', $ordersTopic);
$group->join('consumer-1');
$group->join('consumer-2');
$group->join('consumer-3');

echo "Assignments:\n";
foreach ($group->getAssignments() as $consumer => $partitions) {
    echo "  $consumer: partitions [" . implode(', ', $partitions) . "]\n";
}

echo "\n--- Consume Messages ---\n";
$processedOrders = [];
$processor = function($msg) use (&$processedOrders) {
    $value = $msg->value;
    $processedOrders[] = $value;
    if ($value['amount'] > 400) {
        throw new Exception("Order amount too high: {$value['amount']}");
    }
};

$allResults = [];
foreach (['consumer-1', 'consumer-2', 'consumer-3'] as $consumer) {
    $results = $group->consume($consumer, $processor);
    $allResults = array_merge($allResults, $results);
    $okCount = count(array_filter($results, fn($r) => $r['status'] === 'ok'));
    $errCount = count(array_filter($results, fn($r) => $r['status'] === 'error'));
    echo "  $consumer: processed=" . count($results) . " ok=$okCount errors=$errCount\n";
}

echo "\nTotal processed: " . $group->getProcessedCount() . "\n";
echo "Total errors: " . $group->getErrorCount() . "\n";

echo "\n--- Consumer Rebalance ---\n";
echo "Before rebalance:\n";
foreach ($group->getAssignments() as $consumer => $partitions) {
    echo "  $consumer: [" . implode(', ', $partitions) . "]\n";
}

$group->leave('consumer-2');
echo "\nAfter consumer-2 leaves:\n";
foreach ($group->getAssignments() as $consumer => $partitions) {
    echo "  $consumer: [" . implode(', ', $partitions) . "]\n";
}

$group->join('consumer-4');
echo "\nAfter consumer-4 joins:\n";
foreach ($group->getAssignments() as $consumer => $partitions) {
    echo "  $consumer: [" . implode(', ', $partitions) . "]\n";
}

echo "\n--- Payments Topic ---\n";
for ($i = 0; $i < 8; $i++) {
    $payment = ['payment_id' => 2000 + $i, 'order_id' => 1000 + $i, 'method' => ['card', 'paypal', 'crypto'][$i % 3], 'status' => 'completed'];
    $kafka->produce('payments', "pay_$i", $payment);
}
echo "Payments topic: " . $paymentsTopic->getTotalMessages() . " messages\n";
foreach ($paymentsTopic->partitions as $idx => $p) {
    echo "  Partition $idx: " . $p->getMessageCount() . " messages\n";
}

echo "\n--- Processed Orders Summary ---\n";
$byCustomer = [];
foreach ($processedOrders as $order) {
    $byCustomer[$order['customer']] = ($byCustomer[$order['customer']] ?? 0) + 1;
}
foreach ($byCustomer as $customer => $count) echo "  $customer: $count orders\n";
$totalAmount = array_sum(array_map(fn($o) => $o['amount'], $processedOrders));
echo "Total amount: $" . number_format($totalAmount, 2) . "\n";

echo "=== f120 Done ===\n";
