<?php
require_once __DIR__ . '/Message.php';
require_once __DIR__ . '/MessageQueue.php';
require_once __DIR__ . '/Consumer.php';
require_once __DIR__ . '/QueueManager.php';

echo "=== Message Queue System ===\n\n";

$manager = new QueueManager();

// 创建队列
echo "--- Create Queues ---\n";
$ordersQueue = $manager->createQueue('orders', maxRetries: 3, maxSize: 5000);
$emailsQueue = $manager->createQueue('emails', maxRetries: 5, maxSize: 10000);
$logsQueue = $manager->createQueue('logs', maxRetries: 2, maxSize: 20000);

echo "Queues: " . count($manager->getQueues()) . "\n";
foreach ($manager->getQueues() as $name => $q) {
    echo "  $name (maxSize: {$q->getSize()})\n";
}

// 注册生产者
echo "\n--- Register Producers ---\n";
$orderProducer = $manager->registerProducer('OrderService');
$emailProducer = $manager->registerProducer('EmailService');
$logProducer = $manager->registerProducer('LogService');

// 注册消费者
echo "\n--- Register Consumers ---\n";
$orderProcessor = $manager->registerConsumer('OrderProcessor', function(Message $msg) {
    $data = json_decode($msg->body, true);
    if ($data === null) return false;
    return true;
});

$emailSender = $manager->registerConsumer('EmailSender', function(Message $msg) {
    $headers = $msg->headers;
    if (!isset($headers['to']) || !isset($headers['subject'])) return false;
    return true;
});

$logWriter1 = $manager->registerConsumer('LogWriter1', function(Message $msg) {
    return true;
});

$logWriter2 = $manager->registerConsumer('LogWriter2', function(Message $msg) {
    return true;
});

// 绑定消费者到队列
$manager->bindConsumer('orders', $orderProcessor->id);
$manager->bindConsumer('emails', $emailSender->id);
$manager->bindConsumer('logs', $logWriter1->id);
$manager->bindConsumer('logs', $logWriter2->id);

echo "Consumers: " . count($manager->getConsumers()) . "\n";

// 生产消息
echo "\n--- Produce Messages ---\n";

// 订单消息
$orders = [
    ['body' => json_encode(['id' => 1, 'product' => 'Laptop', 'price' => 999.99]), 'headers' => ['source' => 'web'], 'priority' => 8],
    ['body' => json_encode(['id' => 2, 'product' => 'Mouse', 'price' => 29.99]), 'headers' => ['source' => 'mobile'], 'priority' => 5],
    ['body' => json_encode(['id' => 3, 'product' => 'Keyboard', 'price' => 79.99]), 'headers' => ['source' => 'web'], 'priority' => 5],
    ['body' => json_encode(['id' => 4, 'product' => 'Monitor', 'price' => 449.99]), 'headers' => ['source' => 'api'], 'priority' => 9],
    ['body' => json_encode(['id' => 5, 'product' => 'Webcam', 'price' => 89.99]), 'headers' => ['source' => 'web'], 'priority' => 3],
];

$count = $orderProducer->produceBatch($ordersQueue, $orders);
echo "OrderService produced: $count messages\n";

// 邮件消息
$emailProducer->produce($emailsQueue, 'Welcome to our service!', ['to' => 'alice@test.com', 'subject' => 'Welcome'], 7);
$emailProducer->produce($emailsQueue, 'Your order has shipped', ['to' => 'bob@test.com', 'subject' => 'Shipping'], 6);
$emailProducer->produce($emailsQueue, 'Special offer inside!', ['to' => 'charlie@test.com', 'subject' => 'Promo'], 3);
echo "EmailService produced: {$emailProducer->getProducedCount()} messages\n";

// 日志消息
for ($i = 0; $i < 10; $i++) {
    $level = $i % 3 === 0 ? 'ERROR' : ($i % 3 === 1 ? 'INFO' : 'DEBUG');
    $logProducer->produce($logsQueue, "[$level] Log entry #$i at " . date('Y-m-d H:i:s'), [], $i % 5 + 1);
}
echo "LogService produced: {$logProducer->getProducedCount()} messages\n";

// 查看队列状态
echo "\n--- Queue Status ---\n";
foreach ($manager->getQueueStats() as $name => $stats) {
    echo "  $name: size={$stats['size']}, enqueued={$stats['stats']['enqueued']}\n";
}

// 分发订单队列
echo "\n--- Dispatch Orders ---\n";
$results = $manager->dispatch('orders', 100);
echo "Dispatched: " . count($results) . "\n";
foreach ($results as $r) {
    echo "  {$r['messageId']} -> {$r['consumer']} (" . ($r['success'] ? 'ack' : 'nack') . ")\n";
}

// 分发邮件队列
echo "\n--- Dispatch Emails ---\n";
$results = $manager->dispatch('emails', 100);
echo "Dispatched: " . count($results) . "\n";
foreach ($results as $r) {
    echo "  {$r['messageId']} -> {$r['consumer']} (" . ($r['success'] ? 'ack' : 'nack') . ")\n";
}

// 分发日志队列（多个消费者轮询）
echo "\n--- Dispatch Logs ---\n";
$results = $manager->dispatch('logs', 100);
echo "Dispatched: " . count($results) . "\n";
$consumerCounts = [];
foreach ($results as $r) {
    $consumerCounts[$r['consumer']] = ($consumerCounts[$r['consumer']] ?? 0) + 1;
}
foreach ($consumerCounts as $name => $count) {
    echo "  $name processed: $count\n";
}

// 消费者暂停测试
echo "\n--- Pause Consumer ---\n";
$logWriter1->pause();
echo "LogWriter1 active: " . ($logWriter1->isActive() ? 'true' : 'false') . "\n";

for ($i = 0; $i < 3; $i++) {
    $logProducer->produce($logsQueue, "Post-pause log #$i");
}
$results = $manager->dispatch('logs', 10);
echo "After pause, dispatched: " . count($results) . "\n";
$consumerCounts = [];
foreach ($results as $r) {
    $consumerCounts[$r['consumer']] = ($consumerCounts[$r['consumer']] ?? 0) + 1;
}
foreach ($consumerCounts as $name => $count) {
    echo "  $name processed: $count\n";
}

// 错误处理测试
echo "\n--- Error Handling ---\n";
$badProducer = $manager->registerProducer('BadService');
$badProducer->produce($ordersQueue, 'not valid json');
$badProducer->produce($ordersQueue, 'also not json');
$results = $manager->dispatch('orders', 10);
echo "Bad messages dispatched: " . count($results) . "\n";
foreach ($results as $r) {
    echo "  {$r['messageId']} -> " . ($r['success'] ? 'ack' : 'nack') . "\n";
}

// 总览
echo "\n--- Manager Stats ---\n";
$stats = $manager->getStats();
echo "  Total enqueued: {$stats['totalDequeued']}\n";
echo "  Total acked: {$stats['totalAcked']}\n";
echo "  Total failed: {$stats['totalFailed']}\n";

echo "\n--- Consumer Stats ---\n";
foreach ($manager->getConsumerStats() as $stats) {
    echo "  {$stats['name']}: processed={$stats['processed']}, errors={$stats['errors']}, active=" . ($stats['active'] ? 'true' : 'false') . "\n";
}

echo "\n--- Producer Stats ---\n";
foreach ($manager->getProducerStats() as $stats) {
    echo "  {$stats['name']}: produced={$stats['produced']}\n";
}

echo "\n--- Final Queue Status ---\n";
foreach ($manager->getQueueStats() as $name => $stats) {
    echo "  $name: size={$stats['size']}, acked={$stats['stats']['acked']}, failed={$stats['stats']['failed']}, deadLetters={$stats['deadLetters']}\n";
}
