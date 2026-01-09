<?php
var_dump(class_exists('Generator'));
var_dump(class_exists('\\Generator'));

class TestGen {
    public function gen() {
        yield 1;
        yield 2;
        yield 3;
    }
}

$gen = new TestGen();
$result = $gen->gen();
var_dump(get_class($result));
var_dump($result instanceof Generator);
