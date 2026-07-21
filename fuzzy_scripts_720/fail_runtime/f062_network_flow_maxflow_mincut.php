<?php
// 极度混搭: 网络流 + 最大流(Ford-Fulkerson) + 最小割 + 二分匹配
echo "=== f062: Network Flow + MaxFlow + MinCut + Bipartite ===\n";

class FlowNetwork {
    private array $capacity = []; // [from][to] = capacity
    private array $nodes = [];

    public function addEdge(string $u, string $v, float $cap): void {
        $this->nodes[$u] = true;
        $this->nodes[$v] = true;
        if (!isset($this->capacity[$u])) $this->capacity[$u] = [];
        $this->capacity[$u][$v] = $cap;
        if (!isset($this->capacity[$v])) $this->capacity[$v] = [];
        if (!isset($this->capacity[$v][$u])) $this->capacity[$v][$u] = 0;
    }

    private function bfs(string $s, string $t, array &$parent): bool {
        $visited = [$s => true];
        $queue = [$s];
        $parent = [$s => null];
        while (!empty($queue)) {
            $u = array_shift($queue);
            if (isset($this->capacity[$u])) {
                foreach ($this->capacity[$u] as $v => $cap) {
                    if (!isset($visited[$v]) && $cap > 0) {
                        $parent[$v] = $u;
                        if ($v === $t) return true;
                        $visited[$v] = true;
                        $queue[] = $v;
                    }
                }
            }
        }
        return false;
    }

    public function maxFlow(string $s, string $t): float {
        $maxFlow = 0;
        $parent = [];
        while ($this->bfs($s, $t, $parent)) {
            // 找最小残余容量
            $pathFlow = PHP_FLOAT_MAX;
            $v = $t;
            while ($parent[$v] !== null) {
                $u = $parent[$v];
                $pathFlow = min($pathFlow, $this->capacity[$u][$v]);
                $v = $u;
            }
            // 更新残余网络
            $v = $t;
            while ($parent[$v] !== null) {
                $u = $parent[$v];
                $this->capacity[$u][$v] -= $pathFlow;
                $this->capacity[$v][$u] += $pathFlow;
                $v = $u;
            }
            $maxFlow += $pathFlow;
        }
        return $maxFlow;
    }

    public function minCut(string $s, string $t): array {
        // 先计算最大流
        $this->maxFlow($s, $t);
        // BFS找可达节点
        $visited = [$s => true];
        $queue = [$s];
        while (!empty($queue)) {
            $u = array_shift($queue);
            if (isset($this->capacity[$u])) {
                foreach ($this->capacity[$u] as $v => $cap) {
                    if (!isset($visited[$v]) && $cap > 0) {
                        $visited[$v] = true;
                        $queue[] = $v;
                    }
                }
            }
        }
        $cut = [];
        foreach ($this->capacity as $u => $edges) {
            foreach ($edges as $v => $cap) {
                if (isset($visited[$u]) && !isset($visited[$v]) && $cap === 0) {
                    if (isset($this->capacity[$v][$u]) && $this->capacity[$v][$u] > 0) {
                        $cut[] = "$u→$v";
                    }
                }
            }
        }
        return ['reachable' => array_keys($visited), 'cut_edges' => array_unique($cut)];
    }

    public function getNodes(): array { return array_keys($this->nodes); }
}

class BipartiteMatcher {
    private array $adj = [];
    private array $match = [];

    public function addEdge(int $u, int $v): void {
        $this->adj[$u][] = $v;
    }

    private function bpm(int $u, array &$seen, array &$matchR): bool {
        if (!isset($this->adj[$u])) return false;
        foreach ($this->adj[$u] as $v) {
            if (!isset($seen[$v])) {
                $seen[$v] = true;
                if (!isset($matchR[$v]) || $this->bpm($matchR[$v], $seen, $matchR)) {
                    $matchR[$v] = $u;
                    return true;
                }
            }
        }
        return false;
    }

    public function maxMatching(): array {
        $matchR = [];
        $result = [];
        $leftNodes = array_keys($this->adj);
        foreach ($leftNodes as $u) {
            $seen = [];
            if ($this->bpm($u, $seen, $matchR)) {
                // 收集
            }
        }
        foreach ($matchR as $v => $u) {
            $result[] = ['left' => $u, 'right' => $v];
        }
        return $result;
    }
}

// 测试
echo "--- Max Flow ---\n";
$fn = new FlowNetwork();
$fn->addEdge('S', 'A', 10);
$fn->addEdge('S', 'B', 5);
$fn->addEdge('A', 'B', 15);
$fn->addEdge('A', 'C', 10);
$fn->addEdge('A', 'D', 5);
$fn->addEdge('B', 'D', 10);
$fn->addEdge('C', 'T', 10);
$fn->addEdge('D', 'T', 15);

$flow = $fn->maxFlow('S', 'T');
echo "Max flow S→T: $flow\n";

echo "\n--- Min Cut ---\n";
$fn2 = new FlowNetwork();
$fn2->addEdge('S', 'A', 10);
$fn2->addEdge('S', 'B', 5);
$fn2->addEdge('A', 'B', 15);
$fn2->addEdge('A', 'C', 10);
$fn2->addEdge('A', 'D', 5);
$fn2->addEdge('B', 'D', 10);
$fn2->addEdge('C', 'T', 10);
$fn2->addEdge('D', 'T', 15);
$cut = $fn2->minCut('S', 'T');
echo "Reachable from S: " . implode(', ', $cut['reachable']) . "\n";
echo "Cut edges: " . implode(', ', $cut['cut_edges']) . "\n";

echo "\n--- Bipartite Matching ---\n";
$bm = new BipartiteMatcher();
// 申请人 → 职位
$bm->addEdge(0, 0); $bm->addEdge(0, 1);
$bm->addEdge(1, 1); $bm->addEdge(1, 2);
$bm->addEdge(2, 0); $bm->addEdge(2, 3);
$bm->addEdge(3, 2); $bm->addEdge(3, 3);
$matches = $bm->maxMatching();
echo "Max matching: " . count($matches) . "\n";
foreach ($matches as $m) echo "  Applicant {$m['left']} → Job {$m['right']}\n";

echo "=== f062 Done ===\n";
