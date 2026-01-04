<?php
// Test undefined variable in class inheritance
class Parent {
    public function method($param) {
        echo $param . "\n";
    }
}
class Child extends Parent {
    public function childMethod() {
        parent::method($undefined_var);
    }
}
$obj = new Child();
$obj->childMethod();
echo "Done\n";
