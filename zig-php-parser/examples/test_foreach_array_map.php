<?php
// Foreach with array_map and arrow function test
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
$descriptions = array_map(fn($i) => $i->describe(), $items);
foreach ($descriptions as $desc) {
    echo $desc . "\n";
}
echo "Done\n";
