<?php
/**
 * Test variable variables: $obj->$varName
 */
class Test {
    public $name = "John";
    public $age = 30;
}

$obj = new Test();
$prop = "name";
echo "Name: " . $obj->$prop . "\n";

$prop2 = "age";
echo "Age: " . $obj->$prop2 . "\n";

