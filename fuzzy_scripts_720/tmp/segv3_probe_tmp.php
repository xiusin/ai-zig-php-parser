<?php
// 探针8: 独立复现 foreach($it->args) 静默跳过
class Item {
    public function __construct(public string $name, public array $args = []) {}
}
$items = [new Item('i1', ['x']), new Item('i2', ['y'])];
foreach ($items as $it) {
    echo "OUT {$it->name}\n";
    foreach ($it->args as $a) {
        echo "  IN $a\n";
    }
}
echo "DONE\n";
