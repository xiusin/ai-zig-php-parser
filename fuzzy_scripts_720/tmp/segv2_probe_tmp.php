<?php
// 探针7: 隔离内层 foreach 崩溃触发点
class Item {
    public function __construct(public string $name, public array $args = []) {}
}
$items = [new Item('i1', ['x']), new Item('i2', ['y'])];
$mode = getenv('MODE') ?: 'B1';
if ($mode === 'B1') {
    // 内层 foreach 源=局部数组变量（非属性），写外层 map
    $local = ['p', 'q'];
    $map = [];
    foreach ($items as $it) {
        echo "OUT {$it->name}\n";
        foreach ($local as $a) { $map[$a] = true; }
    }
    echo "MAP=" . count($map) . "\n";
} elseif ($mode === 'B2') {
    // 内层 foreach 源=属性数组，仅 echo 不写
    foreach ($items as $it) {
        echo "OUT {$it->name}\n";
        foreach ($it->args as $a) { echo "  IN $a\n"; }
    }
} elseif ($mode === 'B3') {
    // 内层 foreach 源=属性数组，写外层 map（=原 B）
    $map = [];
    foreach ($items as $it) {
        echo "OUT {$it->name}\n";
        foreach ($it->args as $a) { $map[$a] = true; }
    }
    echo "MAP=" . count($map) . "\n";
} elseif ($mode === 'B4') {
    // 无外层循环：单层 foreach 属性 + 写外层 map
    $map = [];
    foreach ($items[0]->args as $a) { $map[$a] = true; }
    foreach ($items[1]->args as $a) { $map[$a] = true; }
    echo "MAP=" . count($map) . "\n";
}
echo "DONE $mode\n";
