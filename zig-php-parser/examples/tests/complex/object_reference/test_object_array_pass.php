<?php
class Container {
    public $items = [];
}

function addItem($container, $item) {
    $container->items[] = $item;
}

function removeLast($container) {
    array_pop($container->items);
}

$container = new Container();
addItem($container, "A");
addItem($container, "B");
addItem($container, "C");

echo "Items: " . implode(", ", $container->items) . "\n";

removeLast($container);
echo "After remove: " . implode(", ", $container->items) . "\n";
