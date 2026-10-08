<?php
// 极度混搭: 编译器优化 + 常量折叠 + 死代码消除 + 公共子表达式
echo "=== f095: Compiler Optimization + ConstFold + DCE + CSE ===\n";

class IRInstruction {
    public function __construct(
        public string $op, // 'const', 'add', 'sub', 'mul', 'div', 'mov', 'load', 'store', 'cmp', 'br', 'ret'
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
                // 尝试折叠算术运算
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

class DeadCodeElimination {
    public static function optimize(IRFunction $func): int {
        $count = 0;
        foreach ($func->blocks as $block) {
            // 找出使用的变量
            $used = [];
            foreach ($block->instructions as $inst) {
                if ($inst->op === 'ret' || $inst->op === 'br' || $inst->op === 'store') {
                    foreach ($inst->args as $arg) $used[$arg] = true;
                }
                if (in_array($inst->op, ['add', 'sub', 'mul', 'div', 'load', 'cmp'])) {
                    foreach ($inst->args as $arg) $used[$arg] = true;
                }
            }
            // 标记未使用
            foreach ($block->instructions as $inst) {
                if ($inst->dest !== '' && !isset($used[$inst->dest]) && !in_array($inst->op, ['ret', 'br', 'store'])) {
                    $inst->dead = true;
                    $count++;
                }
            }
            // 移除死指令
            $block->instructions = array_values(array_filter($block->instructions, fn($i) => !$i->dead));
        }
        return $count;
    }
}

class CommonSubexprElim {
    public static function optimize(IRFunction $func): int {
        $count = 0;
        foreach ($func->blocks as $block) {
            $exprMap = [];
            for ($i = 0; $i < count($block->instructions); $i++) {
                $inst = $block->instructions[$i];
                if (in_array($inst->op, ['add', 'sub', 'mul', 'div'])) {
                    $key = $inst->op . '(' . implode(',', $inst->args) . ')';
                    if (isset($exprMap[$key])) {
                        $inst->op = 'mov';
                        $inst->args = [$exprMap[$key]];
                        $count++;
                    } else {
                        $exprMap[$key] = $inst->dest;
                    }
                }
            }
        }
        return $count;
    }
}

class ConstantPropagation {
    public static function optimize(IRFunction $func): int {
        $count = 0;
        foreach ($func->blocks as $block) {
            $consts = [];
            for ($i = 0; $i < count($block->instructions); $i++) {
                $inst = $block->instructions[$i];
                if ($inst->op === 'const') { $consts[$inst->dest] = $inst->value; continue; }
                // 替换已知常量参数
                $newArgs = [];
                foreach ($inst->args as $arg) {
                    if (isset($consts[$arg])) { $newArgs[] = (string)$consts[$arg]; $count++; }
                    else $newArgs[] = $arg;
                }
                $inst->args = $newArgs;
            }
        }
        return $count;
    }
}

// 测试
echo "--- Before Optimization ---\n";
$func = new IRFunction('test');
$block = new IRBlock('entry');
$block->add(new IRInstruction('const', 'c1', [], 3))
      ->add(new IRInstruction('const', 'c2', [], 4))
      ->add(new IRInstruction('add', 't1', ['c1', 'c2']))
      ->add(new IRInstruction('mul', 't2', ['t1', 'c1']))
      ->add(new IRInstruction('add', 't3', ['c1', 'c2']))  // 重复
      ->add(new IRInstruction('const', 'c3', [], 10))
      ->add(new IRInstruction('sub', 't4', ['c3', 'c1']))
      ->add(new IRInstruction('ret', '', ['t2']));
$func->addBlock($block);

echo "Instructions:\n";
foreach ($block->instructions as $inst) echo "  $inst\n";

echo "\n--- Constant Folding ---\n";
$folded = ConstFold::optimize($func);
echo "Folded $folded instructions\n";
foreach ($block->instructions as $inst) echo "  $inst\n";

echo "\n--- Constant Propagation ---\n";
$propagated = ConstantPropagation::optimize($func);
echo "Propagated $propagated constants\n";

echo "\n--- Common Subexpression Elimination ---\n";
$cse = CommonSubexprElim::optimize($func);
echo "Eliminated $cse common subexpressions\n";
foreach ($block->instructions as $inst) echo "  $inst\n";

echo "\n--- Dead Code Elimination ---\n";
$dce = DeadCodeElimination::optimize($func);
echo "Eliminated $dce dead instructions\n";
echo "Final instructions:\n";
foreach ($block->instructions as $inst) echo "  $inst\n";

echo "\n--- Full Optimization Pipeline ---\n";
$func2 = new IRFunction('compute');
$b2 = new IRBlock('entry');
$b2->add(new IRInstruction('const', 'a', [], 5))
   ->add(new IRInstruction('const', 'b', [], 3))
   ->add(new IRInstruction('add', 'sum', ['a', 'b']))
   ->add(new IRInstruction('mul', 'prod', ['a', 'b']))
   ->add(new IRInstruction('add', 'sum2', ['a', 'b']))  // CSE target
   ->add(new IRInstruction('sub', 'diff', ['sum', 'prod']))
   ->add(new IRInstruction('const', 'unused', [], 999))  // DCE target
   ->add(new IRInstruction('ret', '', ['diff']));
$func2->addBlock($b2);

echo "Before:\n";
foreach ($b2->instructions as $inst) echo "  $inst\n";

$stats = [];
$stats['const_fold'] = ConstFold::optimize($func2);
$stats['cse'] = CommonSubexprElim::optimize($func2);
$stats['dce'] = DeadCodeElimination::optimize($func2);

echo "\nAfter optimization (fold={$stats['const_fold']}, cse={$stats['cse']}, dce={$stats['dce']}):\n";
foreach ($b2->instructions as $inst) echo "  $inst\n";

echo "=== f095 Done ===\n";
