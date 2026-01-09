<?php
class Counter {
    private static $count = 0;
    private $id;
    
    public function __construct() {
        self::$count = self::$count + 1;
        $this->id = self::$count;
    }
    
    public static function getCount() {
        return self::$count;
    }
    
    public function getId() {
        return $this->id;
    }
    
    public function __destruct() {
        self::$count = self::$count - 1;
    }
}

echo "Initial count: " . Counter::getCount() . "\n";

$counter1 = new Counter();
echo "After counter1: " . Counter::getCount() . "\n";

$counter2 = new Counter();
echo "After counter2: " . Counter::getCount() . "\n";

$counter3 = new Counter();
echo "After counter3: " . Counter::getCount() . "\n";

echo "Counter1 ID: " . $counter1->getId() . "\n";
echo "Counter2 ID: " . $counter2->getId() . "\n";
echo "Counter3 ID: " . $counter3->getId() . "\n";
?>