<?php
// foreach循环测试

// 索引数组遍历
echo "索引数组:\n";
$arr = ['apple', 'banana', 'cherry'];
foreach ($arr as $item) {
    echo $item . " ";
}
echo "\n";

// 带键的遍历
echo "带键遍历:\n";
foreach ($arr as $key => $value) {
    echo "$key: $value\n";
}

// 关联数组遍历
echo "关联数组:\n";
$assoc = ['name' => 'John', 'age' => 30, 'city' => 'NYC'];
foreach ($assoc as $key => $val) {
    echo "$key => $val\n";
}

// 修改值（引用）
echo "修改值:\n";
$nums = [1, 2, 3, 4, 5];
foreach ($nums as &$n) {
    $n *= 2;
}
unset($n);
echo implode(", ", $nums) . "\n";

// 替代语法
echo "替代语法:\n";
$items = ['a', 'b', 'c'];
foreach ($items as $i => $item):
    echo "[$i] = $item\n";
endforeach;

// 嵌套foreach
echo "嵌套foreach:\n";
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];
foreach ($matrix as $row) {
    foreach ($row as $cell) {
        echo $cell . " ";
    }
    echo "\n";
}

// 遍历对象属性
class TestObj {
    public $x = 10;
    public $y = 20;
    private $z = 30;
}
$obj = new TestObj();
echo "对象遍历:\n";
foreach ($obj as $key => $val) {
    echo "$key => $val\n";
}

// 遍历并break
echo "遍历+break:\n";
$numbers = range(1, 100);
foreach ($numbers as $num) {
    if ($num > 5) break;
    echo $num . " ";
}
echo "\n";

// 遍历并continue
echo "遍历+continue:\n";
foreach (range(1, 10) as $n) {
    if ($n % 3 === 0) continue;
    echo $n . " ";
}
echo "\n";

// 遍历空数组
echo "空数组:\n";
$empty = [];
foreach ($empty as $item) {
    echo "never\n";
}
echo "done\n";

// 在foreach中修改数组
echo "修改数组:\n";
$arr2 = [1, 2, 3, 4, 5];
foreach ($arr2 as $i => $val) {
    if ($i === 2) {
        $arr2[5] = 6; // 添加元素
    }
    echo "i=$i, val=$val\n";
}

// 使用list解构
echo "list解构:\n";
$pairs = [[1, 'a'], [2, 'b'], [3, 'c']];
foreach ($pairs as [$num, $char]) {
    echo "$num => $char\n";
}

// 带键的list解构
echo "带键list解构:\n";
foreach ($pairs as $idx => [$n, $c]) {
    echo "[$idx] $n => $c\n";
}
