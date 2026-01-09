<?php
class Item {
    public $name;
    public $price;

    public function __construct($name, $price) {
        $this->name = $name;
        $this->price = $price;
    }
}

$items = [
    new Item("Apple", 1.50),
    new Item("Banana", 0.75),
    new Item("Cherry", 2.00),
];

foreach ($items as &$item) {
    $item->price = $item->price * 1.1; // 10% discount
}
unset($item);

echo "Updated prices:\n";
foreach ($items as $item) {
    echo $item->name . ": $" . number_format($item->price, 2) . "\n";
}
