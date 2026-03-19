<?php
// 测试17: 序列化与反序列化
class SerializableClass {
    public $public = "public value";
    protected $protected = "protected value";
    private $private = "private value";
    
    public function __serialize(): array {
        return [
            'public' => $this->public,
            'protected' => $this->protected,
            'private' => $this->private
        ];
    }
    
    public function __unserialize(array $data): void {
        $this->public = $data['public'];
        $this->protected = $data['protected'];
        $this->private = $data['private'];
    }
}

// 简单数据
$data = [
    'string' => 'test',
    'int' => 42,
    'float' => 3.14,
    'bool' => true,
    'null' => null,
    'array' => [1, 2, 3],
    'nested' => ['a' => ['b' => 'c']]
];

$serialized = serialize($data);
echo "Serialized: $serialized\n";
$unserialized = unserialize($serialized);
print_r($unserialized);

// 对象序列化
$obj = new SerializableClass();
$objSerialized = serialize($obj);
echo "Object serialized length: " . strlen($objSerialized) . "\n";
$objUnserialized = unserialize($objSerialized);
echo "Public: " . $objUnserialized->public . "\n";

// 递归引用
$a = [];
$a[] = &$a;
$refSerialized = serialize($a);
echo "Ref serialized: $refSerialized\n";
$refUnserialized = unserialize($refSerialized);
echo "Is same: " . ($refUnserialized[0] === $refUnserialized ? "yes" : "no") . "\n";

// 闭包 (不支持序列化，测试错误处理)
// $withClosure = ['func' => function() {}];
// $closureSerialized = serialize($withClosure);
?>
