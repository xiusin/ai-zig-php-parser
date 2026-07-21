<?php
// 极度混搭: 编译器后端 + 寄存器分配 + 指令调度 + 窥孔优化
echo "=== f109: Compiler Backend + RegAlloc + Peephole ===\n";

class Instruction {
    public function __construct(
        public string $op,
        public array $operands = [],
        public ?string $comment = null
    ) {}

    public function __toString(): string {
        $ops = implode(', ', $this->operands);
        $str = "{$this->op} $ops";
        if ($this->comment) $str .= "  ; " . $this->comment;
        return $str;
    }
}

class BasicBlock {
    public array $instructions = [];
    public array $succ = [];
    public array $pred = [];
    public array $liveIn = [];
    public array $liveOut = [];

    public function __construct(public string $label) {}

    public function add(Instruction $inst): self { $this->instructions[] = $inst; return $this; }
}

class IRProgram {
    public array $blocks = [];
    private int $blockCount = 0;

    public function addBlock(string $label = ''): BasicBlock {
        if ($label === '') $label = "bb" . $this->blockCount++;
        $block = new BasicBlock($label);
        $this->blocks[$label] = $block;
        return $block;
    }

    public function addEdge(string $from, string $to): void {
        $this->blocks[$from]->succ[] = $to;
        $this->blocks[$to]->pred[] = $from;
    }
}

class LivenessAnalyzer {
    public static function analyze(IRProgram $prog): void {
        $changed = true;
        while ($changed) {
            $changed = false;
            foreach (array_reverse($prog->blocks) as $block) {
                $newOut = [];
                foreach ($block->succ as $s) {
                    $newOut = array_unique(array_merge($newOut, $prog->blocks[$s]->liveIn));
                }
                $newIn = $newOut;
                for ($i = count($block->instructions) - 1; $i >= 0; $i--) {
                    $inst = $block->instructions[$i];
                    $defs = self::getDefs($inst);
                    $uses = self::getUses($inst);
                    $newIn = array_unique(array_merge($uses, array_diff($newIn, $defs)));
                }
                sort($newIn); sort($newOut);
                if ($newIn != $block->liveIn || $newOut != $block->liveOut) {
                    $block->liveIn = $newIn;
                    $block->liveOut = $newOut;
                    $changed = true;
                }
            }
        }
    }

    private static function getDefs(Instruction $inst): array {
        if ($inst->op === 'MOV' || $inst->op === 'ADD' || $inst->op === 'SUB' || $inst->op === 'MUL') {
            return [$inst->operands[0]];
        }
        return [];
    }

    private static function getUses(Instruction $inst): array {
        $uses = [];
        if (($inst->op === 'MOV' || $inst->op === 'ADD' || $inst->op === 'SUB' || $inst->op === 'MUL') && count($inst->operands) > 1) {
            for ($i = 1; $i < count($inst->operands); $i++) {
                if (str_starts_with($inst->operands[$i], 't')) $uses[] = $inst->operands[$i];
            }
        }
        return $uses;
    }
}

class InterferenceGraph {
    public array $nodes = [];
    public array $edges = [];

    public function build(IRProgram $prog): void {
        foreach ($prog->blocks as $block) {
            foreach ($block->liveOut as $v) $this->nodes[$v] = true;
            foreach ($block->liveIn as $v) $this->nodes[$v] = true;
        }
        // 干扰边
        foreach ($prog->blocks as $block) {
            $live = $block->liveOut;
            for ($i = count($block->instructions) - 1; $i >= 0; $i--) {
                $defs = LivenessAnalyzer::getDefs($block->instructions[$i]);
                $uses = LivenessAnalyzer::getUses($block->instructions[$i]);
                foreach ($defs as $d) {
                    foreach ($live as $l) {
                        if ($d !== $l) {
                            $key = $d < $l ? "$d-$l" : "$l-$d";
                            $this->edges[$key] = true;
                        }
                    }
                }
                $live = array_unique(array_merge($uses, array_diff($live, $defs)));
            }
        }
    }

    public function neighbors(string $node): array {
        $neighbors = [];
        foreach (array_keys($this->edges) as $edge) {
            [$a, $b] = explode('-', $edge);
            if ($a === $node) $neighbors[] = $b;
            if ($b === $node) $neighbors[] = $a;
        }
        return array_unique($neighbors);
    }

    public function color(int $numColors): array {
        $colors = [];
        $nodes = array_keys($this->nodes);
        // 简化贪心着色
        foreach ($nodes as $node) {
            $usedColors = [];
            foreach ($this->neighbors($node) as $n) {
                if (isset($colors[$n])) $usedColors[] = $colors[$n];
            }
            for ($c = 0; $c < $numColors; $c++) {
                if (!in_array($c, $usedColors)) { $colors[$node] = $c; break; }
            }
            if (!isset($colors[$node])) $colors[$node] = -1; // spill
        }
        return $colors;
    }
}

class PeepholeOptimizer {
    public function optimize(BasicBlock $block): int {
        $optimized = 0;
        $insts = $block->instructions;
        $newInsts = [];
        for ($i = 0; $i < count($insts); $i++) {
            $inst = $insts[$i];
            $next = $insts[$i + 1] ?? null;

            // MOV t0, t0 → 删除
            if ($inst->op === 'MOV' && count($inst->operands) === 2 && $inst->operands[0] === $inst->operands[1]) {
                $optimized++;
                continue;
            }
            // MOV t0, c; ADD t1, t0, t2 → ADD t1, c, t2
            if ($next && $inst->op === 'MOV' && $next->op === 'ADD' &&
                count($next->operands) === 3 && $next->operands[1] === $inst->operands[0] &&
                preg_match('/^\d+$/', $inst->operands[1])) {
                $newInsts[] = new Instruction('ADD', [$next->operands[0], $inst->operands[1], $next->operands[2]], 'fused');
                $i++;
                $optimized++;
                continue;
            }
            // ADD t0, t1, 0 → MOV t0, t1
            if ($inst->op === 'ADD' && count($inst->operands) === 3 && $inst->operands[2] === '0') {
                $newInsts[] = new Instruction('MOV', [$inst->operands[0], $inst->operands[1]], 'x+0=x');
                $optimized++;
                continue;
            }
            // MUL t0, t1, 1 → MOV t0, t1
            if ($inst->op === 'MUL' && count($inst->operands) === 3 && $inst->operands[2] === '1') {
                $newInsts[] = new Instruction('MOV', [$inst->operands[0], $inst->operands[1]], 'x*1=x');
                $optimized++;
                continue;
            }
            // MUL t0, t1, 0 → MOV t0, 0
            if ($inst->op === 'MUL' && count($inst->operands) === 3 && $inst->operands[2] === '0') {
                $newInsts[] = new Instruction('MOV', [$inst->operands[0], '0'], 'x*0=0');
                $optimized++;
                continue;
            }
            $newInsts[] = $inst;
        }
        $block->instructions = $newInsts;
        return $optimized;
    }
}

class InstructionScheduler {
    public function schedule(BasicBlock $block): void {
        // 简化: 按依赖排序 (拓扑排序)
        $insts = $block->instructions;
        $deps = [];
        for ($i = 0; $i < count($insts); $i++) {
            $deps[$i] = [];
            $defs = LivenessAnalyzer::getDefs($insts[$i]);
            for ($j = 0; $j < $i; $j++) {
                $uses = LivenessAnalyzer::getUses($insts[$i]);
                foreach ($defs as $d) {
                    if (in_array($d, LivenessAnalyzer::getUses($insts[$j]))) {
                        $deps[$i][] = $j;
                    }
                }
            }
        }
        // 简化: 保持原序 (真正的调度器会更复杂)
    }
}

// 测试
echo "--- Build IR Program ---\n";
$prog = new IRProgram();
$bb0 = $prog->addBlock('entry');
$bb0->add(new Instruction('MOV', ['t0', '10'], 'x = 10'));
$bb0->add(new Instruction('MOV', ['t1', '20'], 'y = 20'));
$bb0->add(new Instruction('ADD', ['t2', 't0', 't1'], 'z = x + y'));
$bb0->add(new Instruction('MUL', ['t3', 't2', '1'], 'w = z * 1'));
$bb0->add(new Instruction('ADD', ['t4', 't3', '0'], 'v = w + 0'));
$bb0->add(new Instruction('MOV', ['t5', 't5'], 'noop'));
$bb0->add(new Instruction('MOV', ['ret', 't4'], 'return v'));

$bb1 = $prog->addBlock('loop');
$bb1->add(new Instruction('ADD', ['t0', 't0', 't1'], 'x += y'));
$bb1->add(new Instruction('SUB', ['t1', 't1', 't2'], 'y -= z'));

$prog->addEdge('entry', 'loop');
$prog->addEdge('loop', 'loop');

echo "IR Program:\n";
foreach ($prog->blocks as $block) {
    echo "{$block->label}:\n";
    foreach ($block->instructions as $inst) echo "  $inst\n";
    echo "  succ=[" . implode(',', $block->succ) . "]\n";
}

echo "\n--- Liveness Analysis ---\n";
LivenessAnalyzer::analyze($prog);
foreach ($prog->blocks as $block) {
    echo "{$block->label}: liveIn=[" . implode(',', $block->liveIn) . "] liveOut=[" . implode(',', $block->liveOut) . "]\n";
}

echo "\n--- Interference Graph ---\n";
$ig = new InterferenceGraph();
$ig->build($prog);
echo "Nodes: " . implode(', ', array_keys($ig->nodes)) . "\n";
echo "Edges (" . count($ig->edges) . "):\n";
foreach (array_keys($ig->edges) as $edge) echo "  $edge\n";

echo "\n--- Register Allocation (3 registers) ---\n";
$colors = $ig->color(3);
foreach ($colors as $var => $reg) {
    $regName = $reg >= 0 ? "R$reg" : "SPILL";
    echo "  $var → $regName\n";
}

echo "\n--- Peephole Optimization ---\n";
foreach ($prog->blocks as $block) {
    $opt = new PeepholeOptimizer();
    $count = $opt->optimize($block);
    echo "{$block->label}: $count optimizations applied\n";
}

echo "\nOptimized IR:\n";
foreach ($prog->blocks as $block) {
    echo "{$block->label}:\n";
    foreach ($block->instructions as $inst) echo "  $inst\n";
}

echo "\n--- Register Allocation After Optimization ---\n";
LivenessAnalyzer::analyze($prog);
$ig2 = new InterferenceGraph();
$ig2->build($prog);
$colors2 = $ig2->color(3);
echo "Variables after optimization: " . count($colors2) . "\n";
foreach ($colors2 as $var => $reg) {
    $regName = $reg >= 0 ? "R$reg" : "SPILL";
    echo "  $var → $regName\n";
}

echo "=== f109 Done ===\n";
