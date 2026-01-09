<?php
class Pool {
    private $pool = [];
    private $class;

    public function __construct($class) {
        $this->class = $class;
    }

    public function get() {
        if (empty($this->pool)) {
            return new $this->class();
        }
        return array_pop($this->pool);
    }

    public function release($obj) {
        $this->pool[] = $obj;
    }
}

class Resource {
    public $id;

    public function __construct() {
        static $counter = 0;
        $this->id = ++$counter;
    }
}

$pool = new Pool(Resource::class);
$r1 = $pool->get();
$r2 = $pool->get();
echo "r1 ID: {$r1->id}\n";
echo "r2 ID: {$r2->id}\n";

$pool->release($r1);
$r3 = $pool->get();
echo "r3 ID (should be same as r1): {$r3->id}\n";
