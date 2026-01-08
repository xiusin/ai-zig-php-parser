<?php

class Test {
    public $value = 10;

    public function test() {
        return $this->value;
    }
}

$t = new Test();
echo "value = " . $t->test() . "\n";
echo "Done\n";

