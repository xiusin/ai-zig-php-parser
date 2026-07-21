<?php
// 极度混搭: 图算法 + 最小生成树 + 桥 + 割点 + 强连通分量
echo "=== f127: Graph + MST + Bridge + Articulation + SCC ===\n";

class Graph {
    public array $adj = [];
    public array $weights = [];

    public function addVertex(string $v): void { if (!isset($this->adj[$v])) $this->adj[$v] = []; }

    public function addEdge(string $u, string $v, int $w = 1, bool $directed = false): void {
        $this->addVertex($u); $this->addVertex($v);
        $this->adj[$u][$v] = $w;
        $this->weights["$u-$v"] = $w;
        if (!$directed) { $this->adj[$v][$u] = $w; $this->weights["$v-$u"] = $w; }
    }

    public function getVertices(): array { return array_keys($this->adj); }
    public function getEdgeWeight(string $u, string $v): int { return $this->adj[$u][$v] ?? INF; }
}

class KruskalMST {
    public static function find(Graph $g): array {
        $edges = [];
        foreach ($g->weights as $key => $w) {
            [$u, $v] = explode('-', $key);
            if ($u < $v) $edges[] = ['u' => $u, 'v' => $v, 'w' => $w];
        }
        usort($edges, fn($a, $b) => $a['w'] <=> $b['w']);
        $parent = [];
        foreach ($g->getVertices() as $v) $parent[$v] = $v;
        $find = function($x) use (&$parent, &$find) {
            while ($parent[$x] !== $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x]; }
            return $x;
        };
        $mst = []; $totalWeight = 0;
        foreach ($edges as $e) {
            $pu = $find($e['u']); $pv = $find($e['v']);
            if ($pu !== $pv) {
                $parent[$pu] = $pv;
                $mst[] = $e;
                $totalWeight += $e['w'];
            }
        }
        return ['edges' => $mst, 'totalWeight' => $totalWeight];
    }
}

class PrimMST {
    public static function find(Graph $g, string $start = ''): array {
        $vertices = $g->getVertices();
        if (empty($vertices)) return ['edges' => [], 'totalWeight' => 0];
        if ($start === '') $start = $vertices[0];
        $inMST = []; $inMST[$start] = true;
        $mst = []; $totalWeight = 0;
        while (count($inMST) < count($vertices)) {
            $minW = INF; $minEdge = null;
            foreach (array_keys($inMST) as $u) {
                foreach ($g->adj[$u] as $v => $w) {
                    if (!isset($inMST[$v]) && $w < $minW) { $minW = $w; $minEdge = ['u' => $u, 'v' => $v, 'w' => $w]; }
                }
            }
            if ($minEdge === null) break;
            $mst[] = $minEdge;
            $totalWeight += $minEdge['w'];
            $inMST[$minEdge['v']] = true;
        }
        return ['edges' => $mst, 'totalWeight' => $totalWeight];
    }
}

class ArticulationPoints {
    private array $disc = []; private array $low = []; private array $visited = [];
    private array $ap = []; private int $time = 0;

    public function find(Graph $g): array {
        $this->disc = []; $this->low = []; $this->visited = []; $this->ap = []; $this->time = 0;
        foreach ($g->getVertices() as $v) {
            if (!isset($this->visited[$v])) $this->dfs($g, $v, null, true);
        }
        return array_keys($this->ap);
    }

    private function dfs(Graph $g, string $u, ?string $parent, bool $isRoot): void {
        $this->visited[$u] = true;
        $this->disc[$u] = $this->low[$u] = $this->time++;
        $children = 0;
        foreach ($g->adj[$u] as $v => $w) {
            if ($v === $parent) continue;
            if (isset($this->visited[$v])) {
                $this->low[$u] = min($this->low[$u], $this->disc[$v]);
            } else {
                $children++;
                $this->dfs($g, $v, $u, false);
                $this->low[$u] = min($this->low[$u], $this->low[$v]);
                if (!$isRoot && $this->low[$v] >= $this->disc[$u]) $this->ap[$u] = true;
            }
        }
        if ($isRoot && $children > 1) $this->ap[$u] = true;
    }
}

class Bridges {
    private array $disc = []; private array $low = []; private array $visited = [];
    private array $bridges = []; private int $time = 0;

    public function find(Graph $g): array {
        $this->disc = []; $this->low = []; $this->visited = []; $this->bridges = []; $this->time = 0;
        foreach ($g->getVertices() as $v) {
            if (!isset($this->visited[$v])) $this->dfs($g, $v, null);
        }
        return $this->bridges;
    }

    private function dfs(Graph $g, string $u, ?string $parent): void {
        $this->visited[$u] = true;
        $this->disc[$u] = $this->low[$u] = $this->time++;
        foreach ($g->adj[$u] as $v => $w) {
            if ($v === $parent) continue;
            if (isset($this->visited[$v])) {
                $this->low[$u] = min($this->low[$u], $this->disc[$v]);
            } else {
                $this->dfs($g, $v, $u);
                $this->low[$u] = min($this->low[$u], $this->low[$v]);
                if ($this->low[$v] > $this->disc[$u]) {
                    $this->bridges[] = $u < $v ? "$u-$v" : "$v-$u";
                }
            }
        }
    }
}

class StronglyConnectedComponents {
    private array $disc = []; private array $low = []; private array $onStack = [];
    private array $sccs = []; private int $time = 0; private array $stack = [];

    public function find(Graph $g): array {
        $this->disc = []; $this->low = []; $this->onStack = []; $this->sccs = []; $this->time = 0; $this->stack = [];
        foreach ($g->getVertices() as $v) {
            if (!isset($this->disc[$v])) $this->dfs($g, $v);
        }
        return $this->sccs;
    }

    private function dfs(Graph $g, string $u): void {
        $this->disc[$u] = $this->low[$u] = $this->time++;
        $this->stack[] = $u; $this->onStack[$u] = true;
        foreach ($g->adj[$u] as $v => $w) {
            if (!isset($this->disc[$v])) { $this->dfs($g, $v); $this->low[$u] = min($this->low[$u], $this->low[$v]); }
            elseif (isset($this->onStack[$v]) && $this->onStack[$v]) $this->low[$u] = min($this->low[$u], $this->disc[$v]);
        }
        if ($this->low[$u] === $this->disc[$u]) {
            $scc = [];
            do { $w = array_pop($this->stack); $this->onStack[$w] = false; $scc[] = $w; } while ($w !== $u);
            $this->sccs[] = $scc;
        }
    }
}

// 测试
echo "--- Minimum Spanning Tree ---\n";
$g = new Graph();
$g->addEdge('A', 'B', 4); $g->addEdge('A', 'H', 8);
$g->addEdge('B', 'C', 8); $g->addEdge('B', 'H', 11);
$g->addEdge('C', 'D', 7); $g->addEdge('C', 'F', 4); $g->addEdge('C', 'I', 2);
$g->addEdge('D', 'E', 9); $g->addEdge('D', 'F', 14);
$g->addEdge('E', 'F', 10);
$g->addEdge('F', 'G', 2);
$g->addEdge('G', 'H', 1); $g->addEdge('G', 'I', 6);
$g->addEdge('H', 'I', 7);

$kruskal = KruskalMST::find($g);
echo "Kruskal MST: total={$kruskal['totalWeight']}\n";
foreach ($kruskal['edges'] as $e) echo "  {$e['u']}--{$e['v']} ({$e['w']})\n";

$prim = PrimMST::find($g, 'A');
echo "\nPrim MST: total={$prim['totalWeight']}\n";
foreach ($prim['edges'] as $e) echo "  {$e['u']}--{$e['v']} ({$e['w']})\n";

echo "\n--- Articulation Points ---\n";
$g2 = new Graph();
$g2->addEdge('A', 'B'); $g2->addEdge('B', 'C'); $g2->addEdge('C', 'A'); $g2->addEdge('C', 'D'); $g2->addEdge('D', 'E');
$ap = new ArticulationPoints();
$aps = $ap->find($g2);
echo "Articulation points: " . implode(', ', $aps) . "\n";

echo "\n--- Bridges ---\n";
$bridges = new Bridges();
$bs = $bridges->find($g2);
echo "Bridges: " . implode(', ', $bs) . "\n";

echo "\n--- Strongly Connected Components ---\n";
$g3 = new Graph();
$g3->addEdge('A', 'B', 1, true);
$g3->addEdge('B', 'C', 1, true);
$g3->addEdge('C', 'A', 1, true);
$g3->addEdge('C', 'D', 1, true);
$g3->addEdge('D', 'E', 1, true);
$g3->addEdge('E', 'D', 1, true);
$g3->addEdge('B', 'E', 1, true);

$scc = new StronglyConnectedComponents();
$sccs = $scc->find($g3);
echo "SCCs (" . count($sccs) . "):\n";
foreach ($sccs as $i => $component) {
    echo "  SCC $i: {" . implode(', ', $component) . "}\n";
}

echo "\n--- Complex Graph ---\n";
$g4 = new Graph();
$g4->addEdge('1', '2'); $g4->addEdge('1', '3'); $g4->addEdge('2', '3');
$g4->addEdge('3', '4'); $g4->addEdge('4', '5'); $g4->addEdge('4', '6');
$g4->addEdge('5', '6'); $g4->addEdge('5', '7'); $g4->addEdge('6', '7');
$g4->addEdge('7', '8'); $g4->addEdge('8', '9');

echo "Articulation points: " . implode(', ', (new ArticulationPoints())->find($g4)) . "\n";
echo "Bridges: " . implode(', ', (new Bridges())->find($g4)) . "\n";

$mst4 = KruskalMST::find($g4);
echo "MST weight: {$mst4['totalWeight']}\n";

echo "=== f127 Done ===\n";
