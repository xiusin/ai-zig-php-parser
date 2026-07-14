<?php
// 日志系统 - 主入口
require_once __DIR__ . '/LogLevel.php';
require_once __DIR__ . '/Formatter.php';
require_once __DIR__ . '/Handler.php';
require_once __DIR__ . '/Logger.php';

// 创建日志器 - Plain 格式
echo "=== Plain Formatter ===\n";
$plainLogger = new Logger(new PlainFormatter(), new MemoryHandler());
$plainLogger->debug("Starting application", ['pid' => 1234]);
$plainLogger->info("User logged in", ['user' => 'alice', 'ip' => '192.168.1.1']);
$plainLogger->warning("High memory usage", ['memory' => '512MB']);
$plainLogger->error("Database connection failed", ['host' => 'localhost', 'port' => 3306]);
$plainLogger->critical("System out of disk space", ['disk' => '/dev/sda1', 'free' => '0KB']);

echo $plainLogger->output() . "\n";
echo "Total logs: " . $plainLogger->getLogCount() . "\n";

// JSON 格式
echo "\n=== JSON Formatter ===\n";
$jsonLogger = new Logger(new JSONFormatter(), new MemoryHandler());
$jsonLogger->info("API request", ['method' => 'GET', 'path' => '/api/users', 'status' => 200]);
$jsonLogger->warning("Slow query", ['query' => 'SELECT * FROM orders', 'duration_ms' => 1500]);
$jsonLogger->error("Payment failed", ['order_id' => 12345, 'reason' => 'insufficient_funds']);

foreach ($jsonLogger->getFormattedEntries() as $line) {
    echo $line . "\n";
}

// CSV 格式
echo "\n=== CSV Formatter ===\n";
$csvLogger = new Logger(new CSVFormatter(), new MemoryHandler());
$csvLogger->info("Login success", ['user' => 'bob']);
$csvLogger->warning("Rate limit approaching", ['count' => 95, 'limit' => 100]);
$csvLogger->error("API timeout", ['endpoint' => '/api/slow']);

foreach ($csvLogger->getFormattedEntries() as $line) {
    echo $line . "\n";
}

// 过滤处理器 - 只记录 Warning 及以上
echo "\n=== Filtered Logger (Warning+) ===\n";
$filterHandler = new FilterHandler(LogLevel::Warning);
$filteredLogger = new Logger(new PlainFormatter(), $filterHandler);
$filteredLogger->debug("This debug should be filtered out");
$filteredLogger->info("This info should be filtered out");
$filteredLogger->warning("This warning should appear");
$filteredLogger->error("This error should appear");
$filteredLogger->critical("This critical should appear");

echo $filteredLogger->output() . "\n";
echo "Filtered log count: " . $filteredLogger->getLogCount() . "\n";
echo "Actually stored: " . $filteredLogger->getHandler()->count() . "\n";

// 组合处理器
echo "\n=== Composite Handler ===\n";
$allHandler = new MemoryHandler();
$errorHandler = new FilterHandler(LogLevel::Error);
$composite = new CompositeHandler();
$composite->addHandler($allHandler);
$composite->addHandler($errorHandler);

$compositeLogger = new Logger(new PlainFormatter(), $composite);
$compositeLogger->info("Info message 1");
$compositeLogger->warning("Warning message 1");
$compositeLogger->error("Error message 1");
$compositeLogger->info("Info message 2");
$compositeLogger->error("Error message 2");

echo "All handler count: " . $allHandler->count() . "\n";
echo "Error handler count: " . $errorHandler->count() . "\n";

echo "\nAll entries:\n";
foreach ($allHandler->getEntries() as $e) {
    echo "  $e\n";
}

echo "\nError entries only:\n";
foreach ($errorHandler->getEntries() as $e) {
    echo "  $e\n";
}

// 切换格式化器
echo "\n=== Switch Formatter ===\n";
$switchLogger = new Logger(new PlainFormatter(), new MemoryHandler());
$switchLogger->info("First message (plain)");
$switchLogger->info("Second message (plain)");

$switchLogger->setFormatter(new JSONFormatter());
$switchLogger->info("Third message (json)");

foreach ($switchLogger->getFormattedEntries() as $line) {
    echo $line . "\n";
}

// 日志统计
echo "\n=== Log Statistics ===\n";
$statsLogger = new Logger(new PlainFormatter(), new MemoryHandler());
$statsLogger->debug("d1"); $statsLogger->debug("d2");
$statsLogger->info("i1"); $statsLogger->info("i2"); $statsLogger->info("i3");
$statsLogger->warning("w1");
$statsLogger->error("e1"); $statsLogger->error("e2");

$levelCounts = [];
foreach ($statsLogger->getHandler()->getEntries() as $entry) {
    $level = $entry->level->label();
    $levelCounts[$level] = ($levelCounts[$level] ?? 0) + 1;
}
ksort($levelCounts);
echo "Log level distribution:\n";
foreach ($levelCounts as $level => $count) {
    echo "  $level: $count\n";
}
echo "Total: " . $statsLogger->getLogCount() . "\n";
