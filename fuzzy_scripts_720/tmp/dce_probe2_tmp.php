<?php
// 探针4: 精确复刻 ConstFold + DCE 两函数, 在 DCE 两遍之间打印 $used 内容
class IRInstruction {
    public function __construct(
        public string $op,
        public string $dest = '',
        public array $args = [],
        public mixed $value = null,
        public bool $dead = false
    ) {}
    public function __toString(): string {
        if ($this->op === 'const') return "$this->dest = const(" . var_export($this->value, true) . ")";
        if ($this->op === 'ret') return "ret " . implode(', ', $this->args);
        return "$this->dest = $this->op(" . implode(', ', $this->args) . ")";
    }
}
class IRBlock {
    public array $instructions = [];
    public function __construct(public string $label = '') {}
    public function add(IRInstruction $inst): self { $this->instructions[] = $inst; return $this; }
}
class IRFunction {
    public array $blocks = [];
    public function __construct(public string $name) {}
    public function addBlock(IRBlock $block): self { $this->blocks[] = $block; return $this; }
}
class ConstFold {
    public static function optimize(IRFunction $func): int {
        $count = 0;
        foreach ($func->blocks as $block) {
            $consts = [];
            for ($i = 0; $i < count($block->instructions); $i++) {
                $inst = $block->instructions[$i];
                if ($inst->op === 'const') {
                    $consts[$inst->dest] = $inst->value;
                    continue;
                }
                if (in_array($inst->op, ['add', 'sub', 'mul', 'div']) && count($inst->args) === 2) {
                    $a = $inst->args[0]; $b = $inst->args[1];
                    if (isset($consts[$a]) && isset($consts[$b])) {
                        $va = $consts[$a]; $vb = $consts[$b];
                        $result = match($inst->op) {
                            'add' => $va + $vb,
                            'sub' => $va - $vb,
                            'mul' => $va * $vb,
                            'div' => $vb != 0 ? $va / $vb : null,
                        };
                        if ($result !== null) {
                            $block->instructions[$i] = new IRInstruction('const', $inst->dest, [], $result);
                            $consts[$inst->dest] = $result;
                            $count++;
                        }
                    }
                }
            }
        }
        return $count;
    }
}
class DCEProbe {
    public static function optimize(IRFunction $func): int {
        $count = 0;
        foreach ($func->blocks as $block) {
            $used = [];
            foreach ($block->instructions as $inst) {

                if ($inst->op === 'ret' || $inst->op === 'br' || $inst->op === 'store') {
                    foreach ($inst->args as $arg) {
                        $used[$arg] = true;

                    }
                }
                if (in_array($inst->op, ['add', 'sub', 'mul', 'div', 'load', 'cmp'])) {
                    foreach ($inst->args as $arg) $used[$arg] = true;
                }
            }

            foreach ($block->instructions as $inst) {
                $hit = isset($used[$inst->dest]);

                if ($inst->dest !== '' && !$hit && !in_array($inst->op, ['ret', 'br', 'store'])) {
                    $inst->dead = true;
                    $count++;
                }
            }
            $block->instructions = array_values(array_filter($block->instructions, fn($i) => !$i->dead));
        }
        return $count;
    }
}
$func2 = new IRFunction('compute');
$b2 = new IRBlock('entry');
$b2->add(new IRInstruction('const', 'a', [], 5))
   ->add(new IRInstruction('const', 'b', [], 3))
   ->add(new IRInstruction('add', 'sum', ['a', 'b']))
   ->add(new IRInstruction('mul', 'prod', ['a', 'b']))
   ->add(new IRInstruction('add', 'sum2', ['a', 'b']))
   ->add(new IRInstruction('sub', 'diff', ['sum', 'prod']))
   ->add(new IRInstruction('const', 'unused', [], 999))
   ->add(new IRInstruction('ret', '', ['diff']));
$func2->addBlock($b2);
$f = ConstFold::optimize($func2);
echo "fold=$f\n";
foreach ($b2->instructions as $inst) echo "  $inst\n";
$d = DCEProbe::optimize($func2);
echo "dce=$d\n";
foreach ($b2->instructions as $inst) echo "  $inst\n";
