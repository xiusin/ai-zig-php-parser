<?php

class Base {
    public function greet() {
        return "Hello";
    }
}
class Derived extends Base {
    public function greet() {
        return "Hi";
    }
}
\$obj = new Derived();
echo \$obj->greet();

?>
