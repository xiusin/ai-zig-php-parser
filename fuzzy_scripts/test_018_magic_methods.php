<?php
// 魔术方法测试

class MagicClass {
    private array $data = [];
    private string $name;

    public function __construct(string $name) {
        echo "__construct called with $name\n";
        $this->name = $name;
    }

    public function __destruct() {
        echo "__destruct called for {$this->name}\n";
    }

    public function __get(string $key): mixed {
        echo "__get called for $key\n";
        return $this->data[$key] ?? null;
    }

    public function __set(string $key, mixed $value): void {
        echo "__set called for $key = " . var_export($value, true) . "\n";
        $this->data[$key] = $value;
    }

    public function __isset(string $key): bool {
        echo "__isset called for $key\n";
        return isset($this->data[$key]);
    }

    public function __unset(string $key): void {
        echo "__unset called for $key\n";
        unset($this->data[$key]);
    }

    public function __call(string $method, array $args): mixed {
        echo "__call called for $method with args: " . implode(', ', $args) . "\n";
        return "dynamic method result";
    }

    public static function __callStatic(string $method, array $args): mixed {
        echo "__callStatic called for $method\n";
        return "static dynamic method result";
    }

    public function __toString(): string {
        return "MagicClass({$this->name})";
    }

    public function __invoke(mixed $arg): string {
        echo "__invoke called with $arg\n";
        return "invoked with $arg";
    }

    public function __clone(): void {
        echo "__clone called\n";
        $this->name = $this->name . ' (clone)';
    }

    public function __debugInfo(): array {
        return [
            'name' => $this->name,
            'dataKeys' => array_keys($this->data)
        ];
    }

    public function __serialize(): array {
        echo "__serialize called\n";
        return [
            'name' => $this->name,
            'data' => $this->data
        ];
    }

    public function __unserialize(array $data): void {
        echo "__unserialize called\n";
        $this->name = $data['name'];
        $this->data = $data['data'];
    }
}

// 测试
$obj = new MagicClass('TestObject');

// __get, __set
$obj->dynamicProp = 'dynamic value';
echo "dynamicProp: " . $obj->dynamicProp . "\n";

// __isset, __unset
echo "isset check: " . var_export(isset($obj->dynamicProp), true) . "\n";
unset($obj->dynamicProp);
echo "after unset: " . var_export(isset($obj->dynamicProp), true) . "\n";

// __call
echo "dynamicMethod: " . $obj->dynamicMethod('arg1', 'arg2') . "\n";

// __callStatic
echo "staticDynamic: " . MagicClass::staticDynamic('arg') . "\n";

// __toString
echo "toString: " . $obj . "\n";

// __invoke
echo "invoke: " . $obj('test argument') . "\n";

// __clone
$obj2 = clone $obj;
echo "cloned: " . $obj2 . "\n";

// __debugInfo
echo "debugInfo: " . var_export($obj, true) . "\n";

// __serialize, __unserialize
$serialized = serialize($obj);
echo "serialized: " . $serialized . "\n";
$unserialized = unserialize($serialized);
echo "unserialized: " . $unserialized . "\n";

// 清理触发__destruct
unset($obj);
unset($obj2);
echo "Done\n";
