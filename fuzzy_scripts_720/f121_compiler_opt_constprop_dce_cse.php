<?php
// 极度混搭: 编译器优化 + 常量传播 + 死代码消除 + 公共子表达式消除
echo "=== f121: Compiler Opt + ConstProp + DCE + CSE ===\n";

class IRInst {
    public function __construct(
        public string $op,
        public array $args = [],
        public ?string $dest = null,
        public ?string $comment = null
    ) {}
    public function __toString(): string {
        $a = implode(', ', $this->args);
        $d = $this->dest ? "$this->dest = " : '';
        $c = $this->comment ? "  ; $this->comment" : '';
        return "$d{$this->op}($a)$c";
    }
}

class IRBlock {
    public array $insts = [];
    public array $succ = [];
    public array $pred = [];
    public function __construct(public string $label) {}
    public function add(IRInst $inst): self { $this->insts[] = $inst; return $this; }
}

class IRFunction {
    public array $blocks = [];
    public function addBlock(IRBlock $b): self { $this->blocks[$b->label] = $b; return $this; }
    public function addEdge(string $from, string $to): self {
        $this->blocks[$from]->succ[] = $to;
        $this->blocks[$to]->pred[] = $from;
        return $this;
    }
    public function dump(): string {
        $s = '';
        foreach ($this->blocks as $block) {
            $s .= "{$block->label}:\n";
            foreach ($block->insts as $inst) $s .= "  $inst\n";
        }
        return $s;
    }
}

class ConstantPropagation {
    public array $constants = [];

    public function optimize(IRFunction $func): int {
        $changes = 0;
        $this->constants = [];
        foreach ($func->blocks as $block) {
            foreach ($block->insts as $inst) {
                if ($inst->op === 'const' && $inst->dest !== null) {
                    $this->constants[$inst->dest] = $inst->args[0];
                    $changes++;
                } elseif ($inst->op === 'mov' && $inst->dest !== null) {
                    $src = $inst->args[0];
                    if (isset($this->constants[$src])) {
                        $this->constants[$inst->dest] = $this->constants[$src];
                        $inst->op = 'const';
                        $inst->args = [$this->constants[$src]];
                        $changes++;
                    }
                } elseif ($inst->op === 'add' && $inst->dest !== null) {
                    $a = $this->resolveConst($inst->args[0]);
                    $b = $this->resolveConst($inst->args[1]);
                    if ($a !== null && $b !== null) {
                        $this->constants[$inst->dest] = $a + $b;
                        $inst->op = 'const';
                        $inst->args = [(string)($a + $b)];
                        $inst->comment = "folded add";
                        $changes++;
                    }
                } elseif ($inst->op === 'mul' && $inst->dest !== null) {
                    $a = $this->resolveConst($inst->args[0]);
                    $b = $this->resolveConst($inst->args[1]);
                    if ($a !== null && $b !== null) {
                        $this->constants[$inst->dest] = $a * $b;
                        $inst->op = 'const';
                        $inst->args = [(string)($a * $b)];
                        $inst->comment = "folded mul";
                        $changes++;
                    }
                }
                // 替换操作数中的常量引用
                if ($inst->op !== 'const') {
                    foreach ($inst->args as $i => $arg) {
                        if (isset($this->constants[$arg])) {
                            $inst->args[$i] = (string)$this->constants[$arg];
                            $changes++;
                        }
                    }
                }
            }
        }
        return $changes;
    }

    private function resolveConst(string $arg): ?int {
        if (isset($this->constants[$arg])) return (int)$this->constants[$arg];
        if (preg_match('/^-?\d+$/', $arg)) return (int)$arg;
        return null;
    }
}

class DeadCodeElimination {
    public function optimize(IRFunction $func): int {
        $changes = 0;
        $used = $this->findUsedVars($func);
        foreach ($func->blocks as $block) {
            $newInsts = [];
            foreach ($block->insts as $inst) {
                if ($inst->dest !== null && !isset($used[$inst->dest]) && !in_array($inst->op, ['ret', 'store', 'call', 'br', 'jmp', 'label'])) {
                    $changes++;
                    continue;
                }
                $newInsts[] = $inst;
            }
            $block->insts = $newInsts;
        }
        return $changes;
    }

    private function findUsedVars(IRFunction $func): array {
        $used = [];
        foreach ($func->blocks as $block) {
            foreach ($block->insts as $inst) {
                foreach ($inst->args as $arg) {
                    if (preg_match('/^t\d+$/', $arg)) $used[$arg] = true;
                }
            }
        }
        return $used;
    }
}

class CommonSubexprElimination {
    public function optimize(IRFunction $func): int {
        $changes = 0;
        foreach ($func->blocks as $block) {
            $exprMap = [];
            foreach ($block->insts as $inst) {
                if (in_array($inst->op, ['add', 'sub', 'mul', 'div']) && $inst->dest !== null) {
                    $expr = $inst->op . ':' . implode(',', $inst->args);
                    $commutative = $inst->op === 'add' || $inst->op === 'mul';
                    if ($commutative) {
                        $sorted = $inst->args;
                        sort($sorted);
                        $expr = $inst->op . ':' . implode(',', $sorted);
                    }
                    if (isset($exprMap[$expr])) {
                        $inst->op = 'mov';
                        $inst->args = [$exprMap[$expr]];
                        $inst->comment = "CSE: reuse $exprMap[$expr]";
                        $changes++;
                    } else {
                        $exprMap[$expr] = $inst->dest;
                    }
                }
            }
        }
        return $changes;
    }
}

class ConstantFolding {
    public function optimize(IRFunction $func): int {
        $changes = 0;
        foreach ($func->blocks as $block) {
            foreach ($block->insts as $inst) {
                if (!in_array($inst->op, ['add', 'sub', 'mul', 'div', 'mod'])) continue;
                $allConst = true;
                $vals = [];
                foreach ($inst->args as $arg) {
                    if (preg_match('/^-?\d+$/', $arg)) $vals[] = (int)$arg;
                    else { $allConst = false; break; }
                }
                if (!$allConst || count($vals) < 2) continue;
                $result = match($inst->op) {
                    'add' => $vals[0] + $vals[1],
                    'sub' => $vals[0] - $vals[1],
                    'mul' => $vals[0] * $vals[1],
                    'div' => $vals[1] !== 0 ? (int)($vals[0] / $vals[1]) : 0,
                    'mod' => $vals[1] !== 0 ? $vals[0] % $vals[1] : 0,
                    default => null,
                };
                if ($result !== null) {
                    $inst->op = 'const';
                    $inst->args = [(string)$result];
                    $inst->comment = "folded";
                    $changes++;
                }
            }
        }
        return $changes;
    }
}

class CopyPropagation {
    public function optimize(IRFunction $func): int {
        $changes = 0;
        $copies = [];
        foreach ($func->blocks as $block) {
            foreach ($block->insts as $inst) {
                if ($inst->op === 'mov' && $inst->dest !== null) {
                    $src = $inst->args[0];
                    $copies[$inst->dest] = $src;
                }
                // 替换操作数
                foreach ($inst->args as $i => $arg) {
                    if (isset($copies[$arg])) {
                        $inst->args[$i] = $copies[$arg];
                        $changes++;
                    }
                }
            }
        }
        return $changes;
    }
}

// 测试
echo "--- Build IR Function ---\n";
$func = new IRFunction();
$entry = $func->addBlock(new IRBlock('entry'));
$entry->add(new IRInst('const', ['10'], 't0', 'x = 10'));
$entry->add(new IRInst('const', ['20'], 't1', 'y = 20'));
$entry->add(new IRInst('add', ['t0', 't1'], 't2', 'z = x + y'));
$entry->add(new IRInst('add', ['t0', 't1'], 't3', 'w = x + y (duplicate)'));
$entry->add(new IRInst('mul', ['t2', '1'], 't4', 'v = z * 1'));
$entry->add(new IRInst('add', ['t4', '0'], 't5', 'u = v + 0'));
$entry->add(new IRInst('mov', ['t5'], 't6', 'a = u'));
$entry->add(new IRInst('mul', ['t6', 't0'], 't7', 'b = a * x'));
$entry->add(new IRInst('const', ['99'], 't8', 'dead = 99'));
$entry->add(new IRInst('ret', ['t7'], null, 'return b'));

echo "Before optimization:\n" . $func->dump();

echo "\n--- Constant Folding ---\n";
$cf = new ConstantFolding();
$cfChanges = $cf->optimize($func);
echo "Changes: $cfChanges\n";

echo "\n--- Constant Propagation ---\n";
$cp = new ConstantPropagation();
$cpChanges = $cp->optimize($func);
echo "Changes: $cpChanges\n";

echo "\n--- Copy Propagation ---\n";
$cprop = new CopyPropagation();
$cpropChanges = $cprop->optimize($func);
echo "Changes: $cpropChanges\n";

echo "\n--- Common Subexpression Elimination ---\n";
$cse = new CommonSubexprElimination();
$cseChanges = $cse->optimize($func);
echo "Changes: $cseChanges\n";

echo "\n--- Dead Code Elimination ---\n";
$dce = new DeadCodeElimination();
$dceChanges = $dce->optimize($func);
echo "Changes: $dceChanges\n";

echo "\nAfter all optimizations:\n" . $func->dump();

echo "\n--- Optimization Summary ---\n";
echo "  Constant Folding:     $cfChanges changes\n";
echo "  Constant Propagation: $cpChanges changes\n";
echo "  Copy Propagation:     $cpropChanges changes\n";
echo "  CSE:                  $cseChanges changes\n";
echo "  DCE:                  $dceChanges changes\n";
echo "  Total:                " . ($cfChanges + $cpChanges + $cpropChanges + $cseChanges + $dceChanges) . " changes\n";

echo "\n--- Second Pass (fixed-point) ---\n";
$totalChanges = 0;
for ($pass = 1; $pass <= 5; $pass++) {
    $passChanges = 0;
    $passChanges += $cf->optimize($func);
    $passChanges += $cp->optimize($func);
    $passChanges += $cprop->optimize($func);
    $passChanges += $cse->optimize($func);
    $passChanges += $dce->optimize($func);
    $totalChanges += $passChanges;
    echo "  Pass $pass: $passChanges changes\n";
    if ($passChanges === 0) break;
}
echo "Total after fixed-point: $totalChanges additional changes\n";

echo "\nFinal IR:\n" . $func->dump();

echo "=== f121 Done ===\n";
