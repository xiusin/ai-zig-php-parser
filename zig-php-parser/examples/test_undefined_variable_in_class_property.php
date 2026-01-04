<?php
// Test undefined variable in class property assignment
class Test {
    public $prop;
}
$obj = new Test();
$obj->prop = $undefined_var;
echo "Done\n";
