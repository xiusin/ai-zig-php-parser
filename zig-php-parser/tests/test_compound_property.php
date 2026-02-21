<?php
class Counter {
    public $x = 1;
}

$c = new Counter();
$c->x += 4;
echo "Result: " . $c->x . " (expect 5)\n";
