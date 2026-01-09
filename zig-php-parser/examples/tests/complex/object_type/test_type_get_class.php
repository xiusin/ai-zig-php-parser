<?php
class Base {}
class Derived extends Base {}

$obj = new Derived();
echo "Class: " . get_class($obj) . "\n";
echo "Parent: " . get_parent_class($obj) . "\n";
echo "Parent of Base: " . get_parent_class("Base") . "\n";
