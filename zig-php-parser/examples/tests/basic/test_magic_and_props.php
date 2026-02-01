<?php

class A {
    public $x = 1;
}

$a = new A();
$prop = "x";
echo $a->$prop, "\n";

$b = null;
echo $b?->x === null ? "null\n" : "not-null\n";

echo __FILE__, "\n";
echo __DIR__, "\n";
echo __LINE__, "\n";
