<?php
// 随机测试脚本 #2 - 面向对象和继承

echo "=== Random Test #2: OOP ===\n";

class Base {
    public $id;
    protected $secret;
    private $data;
    
    public function __construct($id) {
        $this->id = $id;
        $this->secret = "secret_$id";
        $this->data = [];
    }
    
    public function getId() {
        return $this->id;
    }
    
    public function setData($key, $value) {
        $this->data[$key] = $value;
    }
    
    public function getData($key) {
        return $this->data[$key] ?? null;
    }
    
    public function process($x) {
        return $x * 2 + $this->id;
    }
}

class Derived extends Base {
    private $items = [];
    
    public function __construct($id, $items) {
        parent::__construct($id);
        $this->items = $items;
    }
    
    public function addItem($item) {
        $this->items[] = $item;
    }
    
    public function getItems() {
        return $this->items;
    }
    
    public function process($x) {
        $base_result = parent::process($x);
        $sum = array_sum($this->items);
        return $base_result + $sum;
    }
}

// 创建对象链
$objects = [];
for ($i = 0; $i < 5; $i++) {
    $items = range($i, $i + 3);
    $objects[] = new Derived($i, $items);
}

// 调用方法
$total = 0;
foreach ($objects as $obj) {
    $obj->setData("name", "object_" . $obj->getId());
    $result = $obj->process(10);
    $total += $result;
    echo "Object {$obj->getId()}: process(10) = $result, items=" . count($obj->getItems()) . "\n";
}

echo "Total: $total\n";

// 验证继承链
$obj = new Derived(100, [1, 2, 3]);
echo "Base ID: " . $obj->getId() . "\n";
echo "Process(5): " . $obj->process(5) . "\n";

// 数组包含对象
$container = [
    "obj1" => new Base(1),
    "obj2" => new Derived(2, [10, 20]),
    "nested" => [
        "deep" => new Base(3)
    ]
];

// 安全遍历：只处理对象
foreach ($container as $key => $obj) {
    if (is_object($obj)) {
        echo "Container[$key]->getId() = " . $obj->getId() . "\n";
    }
}

// 测试多维数组访问
$deep_obj = $container["nested"]["deep"];
echo "Container[nested][deep]->getId() = " . $deep_obj->getId() . "\n";

echo "=== Test #2 Complete ===\n";

