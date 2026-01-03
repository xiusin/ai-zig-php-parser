<?php
class Base {
    public $value;
    
    public function __construct($v) {
        $this->value = $v;
    }
}

class Child extends Base {
    public function __construct($v) {
        parent::__construct($v);
    }
}

$c = new Child(42);
echo "Value: " . $c->value . "\n";
?>
