<?php
// Foreach with object array test
class Item {
    public $name;
    public function __construct($name) {
        $this->name = $name;
    }
    public function describe() {
        return "Item: " . $this->name;
    }
}

$items = [new Item("A"), new Item("B"), new Item("C")];
foreach ($items as $item) {
    echo $item->describe() . "\n";
}
echo "Done\n";
