<?php
// Foreach with method call return test
class Test {
    public function getArray() {
        return ["x", "y", "z"];
    }
}

$obj = new Test();
foreach ($obj->getArray() as $item) {
    echo "Item: {$item}\n";
}
echo "Done\n";
