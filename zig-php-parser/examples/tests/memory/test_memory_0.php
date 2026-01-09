<?php
class RefCounted {
    public $data;
    
    public function __construct($data) {
        $this->data = $data;
    }
    
    public function __destruct() {
        echo "Destroying RefCounted with data: " . $this->data . "\n";
    }
}

echo "Creating object\n";
$obj1 = new RefCounted("data1");
$obj2 = $obj1;
$obj3 = $obj1;

echo "Copying to obj2 and obj3\n";
echo "After copy, obj1 refcount should be 3\n";

unset($obj1);
echo "After unset obj1\n";

unset($obj2);
echo "After unset obj2\n";

unset($obj3);
echo "After unset obj3 (should trigger destructor)\n";
?>