<?php
// Foreach with method that returns array test
class Calculator {
    public function getData() {
        return [1, 2, 3];
    }
}

$calc = new Calculator();
foreach ($calc->getData() as $item) {
    echo "Item: {$item}\n";
}
echo "Done\n";
