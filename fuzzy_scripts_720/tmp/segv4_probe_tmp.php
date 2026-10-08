<?php
// 探针9: 复刻 DCE 形态 —— 外层 foreach 内两个顺序兄弟内层 foreach，
// 内层数组含空 args 元素（ret 形态），pass2 消费 pass1 收集的 map
class Box {
    public array $instructions = [];
    public function __construct(public string $name) {}
    public function add(string $op, string $dest, array $args): self {
        $this->instructions[] = new Item($op, $dest, $args);
        return $this;
    }
}
class Item {
    public function __construct(public string $op, public string $dest = '', public array $args = [], public bool $dead = false) {}
}
$blocks = [];
$b1 = new Box('b1');
$b1->add('const', 'a', [])->add('add', 'sum', ['a', 'b'])->add('ret', '', ['sum']);
$b2 = new Box('b2');
$b2->add('const', 'c', ['x'])->add('ret', '', []);
$blocks[] = $b1;
$blocks[] = $b2;
$count = 0;
foreach ($blocks as $block) {
    $used = [];
    foreach ($block->instructions as $inst) {
        if ($inst->op === 'ret') {
            foreach ($inst->args as $arg) {
                $used[$arg] = true;
            }
        }
    }
    echo "USED[{$block->name}]=" . implode(',', array_keys($used)) . "\n";
    foreach ($block->instructions as $inst) {
        if ($inst->dest !== '' && !isset($used[$inst->dest]) && $inst->op !== 'ret') {
            $inst->dead = true;
            $count++;
            echo "DEAD {$block->name} {$inst->dest}\n";
        }
    }
}
echo "count=$count\n";
