<?php
// 极度混搭: 日志系统 + 结构化日志 + 多级别 + 轮转 + 格式化
echo "=== f119: Logging + Structured + Levels + Rotation ===\n";

class LogRecord {
    public function __construct(
        public string $level,
        public string $message,
        public array $context = [],
        public float $timestamp = 0,
        public string $channel = 'default'
    ) {
        if ($this->timestamp === 0) $this->timestamp = microtime(true);
    }
}

interface LogHandler {
    public function handle(LogRecord $record): void;
    public function isHandling(string $level): bool;
}

class ConsoleHandler implements LogHandler {
    public function __construct(private int $minLevel = 0, private string $format = '[{level}] {channel}: {message}') {}
    public function handle(LogRecord $record): void {
        $output = str_replace(
            ['{level}', '{channel}', '{message}', '{timestamp}'],
            [$record->level, $record->channel, $record->message, date('Y-m-d H:i:s', (int)$record->timestamp)],
            $this->format
        );
        if (!empty($record->context)) $output .= ' ' . json_encode($record->context);
        echo $output . "\n";
    }
    public function isHandling(string $level): bool {
        $levels = ['debug' => 0, 'info' => 1, 'notice' => 2, 'warning' => 3, 'error' => 4, 'critical' => 5, 'alert' => 6, 'emergency' => 7];
        return ($levels[$level] ?? 0) >= $this->minLevel;
    }
}

class MemoryHandler implements LogHandler {
    public array $records = [];
    public function __construct(private int $minLevel = 0) {}
    public function handle(LogRecord $record): void { $this->records[] = $record; }
    public function isHandling(string $level): bool { return true; }
    public function getRecords(): array { return $this->records; }
    public function count(): int { return count($this->records); }
}

class RotatingFileHandler implements LogHandler {
    private array $files = [];
    public function __construct(private string $baseFilename, private int $maxFiles = 3) {}
    public function handle(LogRecord $record): void {
        $date = date('Y-m-d', (int)$record->timestamp);
        $filename = "{$this->baseFilename}_$date.log";
        if (!isset($this->files[$filename])) $this->files[$filename] = [];
        $this->files[$filename][] = $record;
        // 轮转
        if (count($this->files) > $this->maxFiles) {
            $oldest = array_key_first($this->files);
            unset($this->files[$oldest]);
        }
    }
    public function isHandling(string $level): bool { return true; }
    public function getFiles(): array { return array_keys($this->files); }
    public function getFileContent(string $filename): array { return $this->files[$filename] ?? []; }
}

class Logger {
    private array $handlers = [];
    private array $levelMap = ['debug' => 0, 'info' => 1, 'notice' => 2, 'warning' => 3, 'error' => 4, 'critical' => 5, 'alert' => 6, 'emergency' => 7];
    private int $minLevel = 0;

    public function __construct(private string $channel = 'default') {}

    public function addHandler(LogHandler $handler): self { $this->handlers[] = $handler; return $this; }
    public function setMinLevel(string $level): self { $this->minLevel = $this->levelMap[$level] ?? 0; return $this; }

    public function log(string $level, string $message, array $context = []): void {
        if (($this->levelMap[$level] ?? 0) < $this->minLevel) return;
        $record = new LogRecord($level, $message, $context, microtime(true), $this->channel);
        foreach ($this->handlers as $handler) {
            if ($handler->isHandling($level)) $handler->handle($record);
        }
    }

    public function debug(string $msg, array $ctx = []): void { $this->log('debug', $msg, $ctx); }
    public function info(string $msg, array $ctx = []): void { $this->log('info', $msg, $ctx); }
    public function warning(string $msg, array $ctx = []): void { $this->log('warning', $msg, $ctx); }
    public function error(string $msg, array $ctx = []): void { $this->log('error', $msg, $ctx); }
    public function critical(string $msg, array $ctx = []): void { $this->log('critical', $msg, $ctx); }
}

class LogProcessor {
    public static function interpolate(string $message, array $context): string {
        foreach ($context as $key => $value) {
            if (is_scalar($value)) $message = str_replace("{{$key}}", (string)$value, $message);
        }
        return $message;
    }

    public static function addExtraContext(LogRecord $record, array $extra): LogRecord {
        $record->context = array_merge($record->context, $extra);
        return $record;
    }
}

class LogFilter {
    public static function byLevel(array $records, string $minLevel): array {
        $levels = ['debug' => 0, 'info' => 1, 'notice' => 2, 'warning' => 3, 'error' => 4, 'critical' => 5, 'alert' => 6, 'emergency' => 7];
        $threshold = $levels[$minLevel] ?? 0;
        return array_filter($records, fn($r) => ($levels[$r->level] ?? 0) >= $threshold);
    }

    public static function byChannel(array $records, string $channel): array {
        return array_filter($records, fn($r) => $r->channel === $channel);
    }

    public static function byTimeRange(array $records, float $start, float $end): array {
        return array_filter($records, fn($r) => $r->timestamp >= $start && $r->timestamp <= $end);
    }
}

// 测试
echo "--- Basic Logging ---\n";
$console = new ConsoleHandler(1); // info+
$memory = new MemoryHandler();
$logger = new Logger('app');
$logger->addHandler($console)->addHandler($memory);

$logger->debug('Debug message', ['user' => 'alice']);
$logger->info('User logged in', ['user' => 'alice', 'ip' => '192.168.1.1']);
$logger->warning('Rate limit approaching', ['count' => 95, 'limit' => 100]);
$logger->error('Database error', ['query' => 'SELECT * FROM users', 'error' => 'Connection refused']);
$logger->critical('System failure', ['component' => 'core']);

echo "\nMemory handler records: " . $memory->count() . "\n";

echo "\n--- Log Interpolation ---\n";
$msg = LogProcessor::interpolate('User {name} performed {action} on {target}', ['name' => 'Bob', 'action' => 'delete', 'target' => 'file.txt']);
echo "Interpolated: $msg\n";

echo "\n--- Log Filtering ---\n";
$allRecords = $memory->getRecords();
$errors = LogFilter::byLevel($allRecords, 'error');
echo "Error+ records: " . count($errors) . "\n";
foreach ($errors as $r) echo "  [{$r->level}] {$r->message}\n";

$appRecords = LogFilter::byChannel($allRecords, 'app');
echo "App channel records: " . count($appRecords) . "\n";

echo "\n--- Multiple Loggers ---\n";
$apiLogger = new Logger('api');
$apiLogger->addHandler($memory);
$apiLogger->info('API request', ['method' => 'GET', 'path' => '/users']);
$apiLogger->warning('Slow query', ['duration' => 2.5]);

$dbLogger = new Logger('db');
$dbLogger->addHandler($memory);
$dbLogger->error('Query failed', ['sql' => 'INSERT INTO logs']);
$dbLogger->info('Reconnected');

$apiRecords = LogFilter::byChannel($memory->getRecords(), 'api');
$dbRecords = LogFilter::byChannel($memory->getRecords(), 'db');
echo "API records: " . count($apiRecords) . "\n";
echo "DB records: " . count($dbRecords) . "\n";

echo "\n--- Rotating File Handler ---\n";
$rotating = new RotatingFileHandler('/tmp/app', 3);
$logger2 = new Logger('file');
$logger2->addHandler($rotating);
$logger2->info('Day 1 message');
$logger2->error('Day 1 error');

echo "Files created: " . count($rotating->getFiles()) . "\n";
foreach ($rotating->getFiles() as $file) {
    echo "  $file: " . count($rotating->getFileContent($file)) . " records\n";
}

echo "\n--- Structured Logging ---\n";
$structLogger = new Logger('structured');
$structLogger->addHandler(new ConsoleHandler(0, '{timestamp} [{level}] {channel}: {message}'));
$structLogger->info('Order placed', ['order_id' => 12345, 'total' => 99.99, 'items' => 3, 'customer' => 'alice@test.com']);
$structLogger->warning('Inventory low', ['product' => 'widget', 'stock' => 5, 'threshold' => 10]);
$structLogger->error('Payment failed', ['order_id' => 12345, 'reason' => 'insufficient_funds', 'amount' => 99.99]);

echo "\n--- Log Level Distribution ---\n";
$distribution = [];
foreach ($memory->getRecords() as $r) {
    $distribution[$r->level] = ($distribution[$r->level] ?? 0) + 1;
}
foreach (['debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency'] as $level) {
    if (isset($distribution[$level])) {
        $bar = str_repeat('#', $distribution[$level]);
        echo "  $level: $distribution[$level] $bar\n";
    }
}

echo "=== f119 Done ===\n";
