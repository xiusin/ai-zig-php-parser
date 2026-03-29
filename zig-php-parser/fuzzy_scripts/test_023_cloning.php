<?php
// Test 023: Object cloning, serialization, and deep copy
class CloneLab {
    public function process(): string {
        $out = "";

        // Simple clone
        $a = new stdClass();
        $a->value = 100;

        $b = clone $a;
        $b->value = 200;

        $out .= "After clone: a.value = {$a->value}, b.value = {$b->value}\n";

        // Deep clone with nested objects
        $nested = new stdClass();
        $nested->inner = new stdClass();
        $nested->inner->data = 'original';

        $nestedClone = clone $nested;
        $nestedClone->inner->data = 'modified';

        $out .= "Original nested inner data: {$nested->inner->data}\n";
        $out .= "Clone nested inner data: {$nestedClone->inner->data}\n";

        // Clone with array
        $arr = new stdClass();
        $arr->items = [1, 2, 3];
        $arr->nested = new stdClass();
        $arr->nested->name = 'original';

        $arrClone = clone $arr;
        $arrClone->items[] = 4;
        $arrClone->nested->name = 'cloned';

        $out .= "Original items: " . implode(',', $arr->items) . "\n";
        $out .= "Clone items: " . implode(',', $arrClone->items) . "\n";
        $out .= "Original nested name: {$arr->nested->name}\n";
        $out .= "Clone nested name: {$arrClone->nested->name}\n";

        // Serialize clone
        $serialized = serialize($arr);
        $unserialized = unserialize($serialized);
        $unserialized->items[] = 5;
        $unserialized->nested->name = 'unserialized';

        $out .= "\nOriginal items after unserialize modify: " . implode(',', $arr->items) . "\n";
        $out .= "Unserialized items: " . implode(',', $unserialized->items) . "\n";

        // __clone magic method
        $withClone = new ClassWithClone('original');
        $withCloneClone = clone $withClone;

        $out .= "\nWithClone __clone: original={$withClone->data}, clone={$withCloneClone->data}\n";

        return $out;
    }

    public function deepCopy(): string {
        $out = "";

        function deepClone(mixed $obj): mixed {
            if (is_object($obj)) {
                $clone = clone $obj;
                foreach (get_object_vars($clone) as $key => $value) {
                    $clone->$key = deepClone($value);
                }
                return $clone;
            }
            if (is_array($obj)) {
                $result = [];
                foreach ($obj as $k => $v) {
                    $result[$k] = deepClone($v);
                }
                return $result;
            }
            return $obj;
        }

        $original = [
            'obj' => (object)['a' => 1, 'b' => 2],
            'nested' => [
                (object)['x' => 10],
                (object)['y' => 20],
            ],
        ];

        $copied = deepClone($original);
        $copied['obj']->a = 999;
        $copied['nested'][0]->x = 888;

        $out .= "Original obj.a: {$original['obj']->a}\n";
        $out .= "Copied obj.a: {$copied['obj']->a}\n";
        $out .= "Original nested[0].x: {$original['nested'][0]->x}\n";
        $out .= "Copied nested[0].x: {$copied['nested'][0]->x}\n";

        return $out;
    }
}

class ClassWithClone {
    public string $data;
    public array $history = [];

    public function __construct(public string $name) {
        $this->data = $name;
    }

    public function __clone() {
        $this->data = $this->data . '_cloned';
        $this->history[] = 'cloned at ' . time();
    }
}

$lab = new CloneLab();
echo $lab->process();
echo "\n";
echo $lab->deepCopy();