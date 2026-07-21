<?php
// 极度混搭: 数据流分析 + 活跃变量 + 到达定义 + 基本块
echo "=== f101: Data Flow Analysis + Liveness + ReachingDef ===\n";

class CFGNode {
    public array $defs = [];
    public array $uses = [];
    public array $succ = [];
    public array $pred = [];
    public array $liveIn = [];
    public array $liveOut = [];

    public function __construct(public string $id, public string $label = '') {}
}

class CFG {
    public array $nodes = [];

    public function addNode(CFGNode $node): self { $this->nodes[$node->id] = $node; return $this; }

    public function addEdge(string $from, string $to): void {
        $this->nodes[$from]->succ[] = $to;
        $this->nodes[$to]->pred[] = $from;
    }
}

class LivenessAnalysis {
    public static function analyze(CFG $cfg): array {
        $changed = true;
        while ($changed) {
            $changed = false;
            foreach (array_reverse($cfg->nodes) as $node) {
                // liveOut = union of liveIn of successors
                $newOut = [];
                foreach ($node->succ as $s) {
                    $newOut = array_unique(array_merge($newOut, $cfg->nodes[$s]->liveIn));
                }
                sort($newOut);
                // liveIn = use ∪ (liveOut - def)
                $newIn = array_unique(array_merge(
                    $node->uses,
                    array_diff($newOut, $node->defs)
                ));
                sort($newIn);
                if ($newIn != $node->liveIn || $newOut != $node->liveOut) {
                    $node->liveIn = $newIn;
                    $node->liveOut = $newOut;
                    $changed = true;
                }
            }
        }
        $result = [];
        foreach ($cfg->nodes as $id => $node) {
            $result[$id] = ['liveIn' => $node->liveIn, 'liveOut' => $node->liveOut];
        }
        return $result;
    }
}

class ReachingDefinitions {
    public static function analyze(CFG $cfg): array {
        $changed = true;
        while ($changed) {
            $changed = false;
            foreach ($cfg->nodes as $node) {
                $newIn = [];
                foreach ($node->pred as $p) {
                    $newIn = array_unique(array_merge($newIn, $cfg->nodes[$p]->gen));
                }
                sort($newIn);
                $newOut = array_unique(array_merge($node->gen, array_diff($newIn, $node->kill)));
                sort($newOut);
                if ($newIn != $node->rdIn || $newOut != $node->rdOut) {
                    $node->rdIn = $newIn;
                    $node->rdOut = $newOut;
                    $changed = true;
                }
            }
        }
        $result = [];
        foreach ($cfg->nodes as $id => $node) {
            $result[$id] = ['in' => $node->rdIn ?? [], 'out' => $node->rdOut ?? []];
        }
        return $result;
    }
}

// 测试
echo "--- Build CFG ---\n";
$cfg = new CFG();
// x = 1
$n1 = new CFGNode('n1', 'x = 1'); $n1->defs = ['x']; $n1->uses = []; $cfg->addNode($n1);
// y = x + 2
$n2 = new CFGNode('n2', 'y = x + 2'); $n2->defs = ['y']; $n2->uses = ['x']; $cfg->addNode($n2);
// if y > 5
$n3 = new CFGNode('n3', 'if y > 5'); $n3->uses = ['y']; $cfg->addNode($n3);
// z = y * 2 (true branch)
$n4 = new CFGNode('n4', 'z = y * 2'); $n4->defs = ['z']; $n4->uses = ['y']; $cfg->addNode($n4);
// z = y - 1 (false branch)
$n5 = new CFGNode('n5', 'z = y - 1'); $n5->defs = ['z']; $n5->uses = ['y']; $cfg->addNode($n5);
// return z
$n6 = new CFGNode('n6', 'return z'); $n6->uses = ['z']; $cfg->addNode($n6);

$cfg->addEdge('n1', 'n2');
$cfg->addEdge('n2', 'n3');
$cfg->addEdge('n3', 'n4');
$cfg->addEdge('n3', 'n5');
$cfg->addEdge('n4', 'n6');
$cfg->addEdge('n5', 'n6');

echo "CFG:\n";
foreach ($cfg->nodes as $node) {
    echo "  {$node->id}: {$node->label} defs=[" . implode(',', $node->defs) . "] uses=[" . implode(',', $node->uses) . "] succ=[" . implode(',', $node->succ) . "]\n";
}

echo "\n--- Liveness Analysis ---\n";
$liveness = LivenessAnalysis::analyze($cfg);
foreach ($liveness as $node => $info) {
    echo "  $node: liveIn=[" . implode(',', $info['liveIn']) . "] liveOut=[" . implode(',', $info['liveOut']) . "]\n";
}

echo "\n--- Dead Code Detection ---\n";
foreach ($cfg->nodes as $node) {
    $usefulVars = array_intersect($node->defs, $node->liveOut);
    $deadVars = array_diff($node->defs, $node->liveOut);
    if (!empty($deadVars)) {
        echo "  {$node->id}: dead vars = [" . implode(',', $deadVars) . "]\n";
    } else {
        echo "  {$node->id}: no dead vars\n";
    }
}

echo "\n--- Reaching Definitions ---\n";
// Add gen/kill info
$n1->gen = ['x@n1']; $n1->kill = ['x@n2', 'x@n3'];
$n2->gen = ['y@n2']; $n2->kill = [];
$n3->gen = []; $n3->kill = [];
$n4->gen = ['z@n4']; $n4->kill = ['z@n5'];
$n5->gen = ['z@n5']; $n5->kill = ['z@n4'];
$n6->gen = []; $n6->kill = [];

$reaching = ReachingDefinitions::analyze($cfg);
foreach ($reaching as $node => $info) {
    echo "  $node: in=[" . implode(',', $info['in']) . "] out=[" . implode(',', $info['out']) . "]\n";
}

echo "\n--- Register Allocation (Simplified) ---\n";
$allLive = [];
foreach ($liveness as $node => $info) {
    $allLive = array_unique(array_merge($allLive, $info['liveIn'], $info['liveOut']));
}
sort($allLive);
echo "All live variables: [" . implode(', ', $allLive) . "]\n";
echo "Registers needed: " . count($allLive) . "\n";

// 简化图着色
$interference = [];
foreach ($liveness as $info) {
    $vars = array_unique(array_merge($info['liveIn'], $info['liveOut']));
    for ($i = 0; $i < count($vars); $i++) {
        for ($j = $i + 1; $j < count($vars); $j++) {
            $key = $vars[$i] < $vars[$j] ? "{$vars[$i]}-{$vars[$j]}" : "{$vars[$j]}-{$vars[$i]}";
            $interference[$key] = true;
        }
    }
}
echo "Interference edges: " . count($interference) . "\n";
foreach (array_keys($interference) as $edge) echo "  $edge\n";

echo "=== f101 Done ===\n";
