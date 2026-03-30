<?php
// 测试57: PHP 8.1 new表达式在初始化器中 - 属性默认值和函数参数默认值
// 测试目的：验证new可以在属性默认值和参数默认值中使用

class Logger {
    private array $logs = [];
    
    public function log(string $message): void {
        $this->logs[] = date('H:i:s') . ' ' . $message;
    }
    
    public function getLogs(): array {
        return $this->logs;
    }
}

// 在属性默认值中使用new
class Service {
    // PHP 8.1+: 可以在属性默认值中使用new
    private Logger $logger;
    
    public function __construct(
        ?Logger $logger = null
    ) {
        $this->logger = $logger ?? new Logger();
    }
    
    public function doWork(): void {
        $this->logger->log("Work started");
        // ... do something ...
        $this->logger->log("Work completed");
    }
    
    public function getLogger(): Logger {
        return $this->logger;
    }
}

$service1 = new Service();
$service1->doWork();
echo "Service 1 logs:\n";
print_r($service1->getLogger()->getLogs());

// 共享logger
$sharedLogger = new Logger();
$service2 = new Service($sharedLogger);
$service3 = new Service($sharedLogger);
$service2->doWork();
$service3->doWork();
echo "\nShared logger logs:\n";
print_r($sharedLogger->getLogs());

// 在函数参数中使用new（PHP 8.0+）
function processData(
    array $data,
    Logger $logger = new Logger() // 默认创建新logger
): array {
    $logger->log("Processing " . count($data) . " items");
    $result = array_map(fn($x) => $x * 2, $data);
    $logger->log("Processing complete");
    return $result;
}

echo "\nProcess with default logger:\n";
$result1 = processData([1, 2, 3]);
echo "Result: " . implode(', ', $result1) . "\n";

// 属性钩子（PHP 8.4+ 特性，这里模拟）
class Config {
    private array $values = [];
    
    public function get(string $key, mixed $default = null): mixed {
        return $this->values[$key] ?? $default;
    }
    
    public function set(string $key, mixed $value): void {
        $this->values[$key] = $value;
    }
}

// 在属性默认值中使用复杂表达式
class Application {
    private Config $config;
    private Logger $logger;
    
    public function __construct() {
        $this->config = new Config();
        $this->logger = new Logger();
        
        $this->config->set('env', 'production');
        $this->config->set('debug', false);
    }
    
    public function run(): void {
        $this->logger->log("App starting in " . $this->config->get('env'));
        echo "Application running\n";
        $this->logger->log("App finished");
    }
    
    public function getLogs(): array {
        return $this->logger->getLogs();
    }
}

$app = new Application();
$app->run();
echo "\nApplication logs:\n";
print_r($app->getLogs());

// 默认参数中的复杂对象创建
class DatabaseConfig {
    public function __construct(
        public string $host = 'localhost',
        public int $port = 3306,
        public string $charset = 'utf8mb4'
    ) {}
}

function connectToDatabase(DatabaseConfig $config = new DatabaseConfig()): string {
    return "Connected to {$config->host}:{$config->port}";
}

echo "\n" . connectToDatabase() . "\n";
echo connectToDatabase(new DatabaseConfig('remote.server.com', 5432)) . "\n";
?>
