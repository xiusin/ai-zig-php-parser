<?php
// 复杂场景测试 5: 静态成员和常量

class MathUtils {
    public static int $pi_digits = 3;
    private static array $cache = [];
    
    public static function square(int $x): int {
        return $x * $x;
    }
    
    public static function cube(int $x): int {
        return $x * $x * $x;
    }
    
    public static function memoize(int $key, callable $fn) {
        if (!isset(self::$cache[$key])) {
            self::$cache[$key] = $fn();
        }
        return self::$cache[$key];
    }
    
    public static function getCacheSize(): int {
        return count(self::$cache);
    }
}

// 测试静态方法
echo "Square of 5: " . MathUtils::square(5) . "\n";
echo "Cube of 3: " . MathUtils::cube(3) . "\n";

// 测试静态属性
echo "Pi digits: " . MathUtils::$pi_digits . "\n";
MathUtils::$pi_digits = 5;
echo "Updated pi digits: " . MathUtils::$pi_digits . "\n";

// 测试静态缓存
$result1 = MathUtils::memoize(1, function() { return 100; });
$result2 = MathUtils::memoize(2, function() { return 200; });
echo "Memoized 1: " . $result1 . "\n";
echo "Memoized 2: " . $result2 . "\n";
echo "Cache size: " . MathUtils::getCacheSize() . "\n";

// 测试类常量（暂不支持）
// class Config {
//     public const VERSION = "1.0.0";
//     public const MAX_SIZE = 1000;
// }

echo "\nTest 5 passed!\n";
