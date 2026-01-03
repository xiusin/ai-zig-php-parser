<?php
class Counter {
    public $count = 0;
    
    public function increment() {
        $this->count = $this->count + 1;
        return $this->count;
    }
}

$c = new Counter();
echo $c->increment();
echo "\n";
