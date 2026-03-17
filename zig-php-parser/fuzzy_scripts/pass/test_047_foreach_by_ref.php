<?php
// 测试47: foreach引用与修改
$arr = [1, 2, 3, 4, 5];
foreach ($arr as &$value) {
    $value *= 2;
}
unset($value);
print_r($arr);

// 多维数组引用
$matrix = [[1, 2], [3, 4], [5, 6]];
foreach ($matrix as &$row) {
    foreach ($row as &$cell) {
        $cell += 10;
    }
    unset($cell);
}
unset($row);
print_r($matrix);

// 遍历同时修改
$items = ['a' => 1, 'b' => 2, 'c' => 3];
foreach ($items as $key => &$val) {
    $val = strtoupper($key) . "_" . ($val * 10);
}
unset($val);
print_r($items);

// 引用与值混合问题
$test = [1, 2, 3];
foreach ($test as &$ref) {}
unset($ref);
foreach ($test as $val) {}
print_r($test);

// 对象数组
class Item {
    public $value;
    public function __construct($v) { $this->value = $v; }
}
$objects = [new Item(1), new Item(2), new Item(3)];
foreach ($objects as $obj) {
    $obj->value *= 10;
}
foreach ($objects as $obj) {
    echo $obj->value . " ";
}
echo "\n";
?>