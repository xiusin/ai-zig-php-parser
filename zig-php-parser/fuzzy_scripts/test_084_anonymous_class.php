<?php
// === Anonymous Class Basics ===
$obj = new class {
    public $name = "anon";
    public function greet() {
        return "Hello from " . $this->name;
    }
};
echo $obj->greet() . "\n";
echo $obj->name . "\n";

// === Anonymous Class with Constructor ===
$obj2 = new class("World") {
    public $who;
    public function __construct($who) {
        $this->who = $who;
    }
    public function sayHi() {
        return "Hi, " . $this->who . "!";
    }
};
echo $obj2->sayHi() . "\n";

// === Anonymous Class with Method ===
$counter = new class {
    private $count = 0;
    public function increment() {
        $this->count++;
        return $this;
    }
    public function getCount() {
        return $this->count;
    }
};
$counter->increment();
$counter->increment();
$counter->increment();
echo "Count: " . $counter->getCount() . "\n";

// === Anonymous Class implementing interface-like behavior ===
$logger = new class {
    public function log($msg) {
        echo "LOG: " . $msg . "\n";
    }
};
$logger->log("test message");

// === get_class on anonymous class ===
$cls = get_class($obj);
$is_anon = (strpos($cls, "anonymous") !== false || strpos($cls, "class@") !== false);
echo "Is anonymous: " . ($is_anon ? "true" : "false") . "\n";
?>
