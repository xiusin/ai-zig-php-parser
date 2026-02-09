<?php
// 测试静态属性

class Counter {
    private static $count = 0;
    
    public static function increment() {
        self::$count++;
    }
    
    public static function getCount() {
        return self::$count;
    }
    
    public static function reset() {
        self::$count = 0;
    }
}

echo "=== 测试静态属性 ===\n";
Counter::increment();
Counter::increment();
Counter::increment();
echo "Count: " . Counter::getCount() . "\n";
Counter::reset();
echo "After reset: " . Counter::getCount() . "\n";
