<?php
// 混合复杂测试 10
class Item {
    public $id;
    public $data;
    public function __construct($id, $data) {
        $this->id = $id;
        $this->data = $data;
    }
}

$items = [];
for ($j = 0; $j < 5; $j++) {
    $items[] = new Item($j, range(1, $j + 1));
}

$sum = 0;
foreach ($items as $item) {
    $sum += array_sum($item->data);
}
echo $sum;
echo "
";
?>