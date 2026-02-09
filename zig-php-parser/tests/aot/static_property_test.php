<?php

class Counter {
    public static int $count = 0;
    
    public static function increment(): void {
        self::$count = self::$count + 1;
        echo "After increment: " . self::$count . "\n";
    }
    
    public static function getCount(): int {
        echo "Getting count: " . self::$count . "\n";
        return self::$count;
    }
}

echo "Initial: " . Counter::$count . "\n";

Counter::increment();
Counter::increment();
Counter::increment();

$result = Counter::getCount();
echo "Final result: $result\n";
