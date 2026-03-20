<?php
class Counter {
    private static int $count = 0;
    private int $instanceId;

    public function __construct() {
        $this->instanceId = ++self::$count;
    }

    public static function getTotalCount(): int {
        return self::$count;
    }

    public static function reset(): void {
        self::$count = 0;
    }

    public function getInstanceId(): int {
        return $this->instanceId;
    }
}

Counter::reset();
$a = new Counter();
$b = new Counter();
$c = new Counter();

echo "Total: " . Counter::getTotalCount() . "\n";
echo "A id: " . $a->getInstanceId() . "\n";
echo "B id: " . $b->getInstanceId() . "\n";
echo "C id: " . $c->getInstanceId() . "\n";

class ExtendedCounter extends Counter {
    private static int $extendedCount = 0;
    private int $extendedId;

    public function __construct() {
        parent::__construct();
        $this->extendedId = ++self::$extendedCount;
    }

    public function getExtendedId(): int {
        return $this->extendedId;
    }
}

$d = new ExtendedCounter();
echo "Extended total: " . Counter::getTotalCount() . "\n";
echo "Extended id: " . $d->getExtendedId() . "\n";
echo "OK\n";
