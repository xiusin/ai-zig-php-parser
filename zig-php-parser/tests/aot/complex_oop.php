<?php
// 测试复杂的面向对象特性

interface Logger {
    public function log(string $message): void;
}

trait TimestampTrait {
    private static $counter = 0;
    
    public function getTimestamp(): string {
        self::$counter++;
        return "[" . date("Y-m-d H:i:s") . "] #" . self::$counter;
    }
}

abstract class BaseLogger implements Logger {
    protected string $prefix;
    
    public function __construct(string $prefix) {
        $this->prefix = $prefix;
    }
    
    abstract protected function write(string $text): void;
    
    public function log(string $message): void {
        $this->write($this->prefix . ": " . $message);
    }
}

class ConsoleLogger extends BaseLogger {
    use TimestampTrait;
    
    private int $logCount = 0;
    
    protected function write(string $text): void {
        $this->logCount++;
        echo $this->getTimestamp() . " " . $text . "\n";
    }
    
    public function getCount(): int {
        return $this->logCount;
    }
}

class FileLogger extends BaseLogger {
    use TimestampTrait;
    
    private string $filename;
    private static array $instances = [];
    
    public function __construct(string $prefix, string $filename) {
        parent::__construct($prefix);
        $this->filename = $filename;
        self::$instances[] = $this;
    }
    
    protected function write(string $text): void {
        $content = $this->getTimestamp() . " " . $text . "\n";
        file_put_contents($this->filename, $content, FILE_APPEND);
    }
    
    public static function getInstanceCount(): int {
        return count(self::$instances);
    }
}

// 测试
$console = new ConsoleLogger("APP");
$console->log("Application started");
$console->log("Processing data");
$console->log("Application finished");

echo "Total logs: " . $console->getCount() . "\n";

$file1 = new FileLogger("SYS", "/tmp/test1.log");
$file2 = new FileLogger("DB", "/tmp/test2.log");
$file1->log("System initialized");
$file2->log("Database connected");

echo "FileLogger instances: " . FileLogger::getInstanceCount() . "\n";
