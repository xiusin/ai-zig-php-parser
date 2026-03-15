<?php
// 测试56: PHP 8.1 final常量 - 不可被子类覆盖的类常量
// 测试目的：验证final const语法的继承行为

class ApiEndpoints {
    // 普通常量可以被覆盖
    public const VERSION = 'v1';
    
    // final常量不能被覆盖
    final public const BASE_URL = 'https://api.example.com';
    final protected const TIMEOUT = 30;
    final private const RETRY_COUNT = 3;
    
    public static function getConfig(): array {
        return [
            'version' => self::VERSION,
            'base_url' => self::BASE_URL,
            'timeout' => self::TIMEOUT,
            'retry' => self::RETRY_COUNT,
        ];
    }
}

class ExtendedEndpoints extends ApiEndpoints {
    // 可以覆盖非final常量
    public const VERSION = 'v2';
    
    // 不能覆盖final常量 - 会导致编译错误
    // final public const BASE_URL = 'https://new.api.com'; // Error!
    
    public static function getExtendedConfig(): array {
        return [
            'version' => self::VERSION, // v2
            'parent_version' => parent::VERSION, // v1
            'base_url' => self::BASE_URL, // 继承自父类
        ];
    }
}

echo "Base config:\n";
print_r(ApiEndpoints::getConfig());

echo "\nExtended config:\n";
print_r(ExtendedEndpoints::getExtendedConfig());

// 接口中的final常量
interface LoggerInterface {
    final public const LEVEL_DEBUG = 100;
    final public const LEVEL_INFO = 200;
    final public const LEVEL_WARNING = 300;
    final public const LEVEL_ERROR = 400;
}

class FileLogger implements LoggerInterface {
    // 不能覆盖接口的final常量
    // public const LEVEL_DEBUG = 10; // Error!
    
    public function log(int $level, string $message): void {
        $prefix = match($level) {
            self::LEVEL_DEBUG => 'DEBUG',
            self::LEVEL_INFO => 'INFO',
            self::LEVEL_WARNING => 'WARN',
            self::LEVEL_ERROR => 'ERROR',
            default => 'UNKNOWN',
        };
        echo "[$prefix] $message\n";
    }
}

$logger = new FileLogger();
$logger->log(LoggerInterface::LEVEL_INFO, "Application started");
$logger->log(LoggerInterface::LEVEL_ERROR, "Database connection failed");

// Trait中的final常量
trait DatabaseTrait {
    final public const DEFAULT_CHARSET = 'utf8mb4';
    final public const DEFAULT_COLLATION = 'utf8mb4_unicode_ci';
}

class DatabaseConnection {
    use DatabaseTrait;
    
    public function getDefaults(): array {
        return [
            'charset' => self::DEFAULT_CHARSET,
            'collation' => self::DEFAULT_COLLATION,
        ];
    }
}

$db = new DatabaseConnection();
echo "\nDatabase defaults:\n";
print_r($db->getDefaults());

// 多级继承
class Level1 {
    final public const FROM_LEVEL1 = 'level1';
    public const OVERRIDE_ME = 'original';
}

class Level2 extends Level1 {
    public const OVERRIDE_ME = 'level2'; // 可以覆盖非final
    final public const FROM_LEVEL2 = 'level2';
}

class Level3 extends Level2 {
    public const OVERRIDE_ME = 'level3'; // 继续覆盖
    // final public const FROM_LEVEL1 = 'override'; // Error!
    // final public const FROM_LEVEL2 = 'override'; // Error!
}

echo "\nLevel3 constants:\n";
echo "OVERRIDE_ME: " . Level3::OVERRIDE_ME . "\n";
echo "FROM_LEVEL1: " . Level3::FROM_LEVEL1 . "\n";
echo "FROM_LEVEL2: " . Level3::FROM_LEVEL2 . "\n";
?>
