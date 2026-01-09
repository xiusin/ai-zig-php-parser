<?php
class Prototype {
    public $value = 0;
}

$original = new Prototype();
$clone = clone $original;

$original->value = 100;
$clone->value = 200;

echo "Original: " . $original->value . "\n";
echo "Clone: " . $clone->value . "\n";
