<?php
// 极度混搭: 图论+最短路径(Dijkstra/Bellman-Ford/Floyd-Warshall) + A*
echo "=== f061: Graph + Dijkstra + BellmanFord + FloydWarshall ===\n";

class WeightedGraph {
    private array $adj = []; // node → [(neighbor, weight)]
    private array $nodes = [];

    public function addNode(string $node): void {
        if (!isset($this->nodes[$node])) {
            $this->nodes[$node] = true;
            $this->adj[$node] = [];
        }
    }

    public function addEdge(string $from, string $to, float $weight, bool $directed = false): void {
        $this->addNode($from);
        $this->addNode($to);
        $this->adj[$from][] = ['to' => $to, 'w' => $weight];
        if (!$directed) {
            $this->adj[$to][] = ['to' => $from, 'w' => $weight];
        }
    }

    public function dijkstra(string $src): array {
        $dist = []; $visited = [];
        foreach ($this->nodes as $n => $_) $dist[$n] = PHP_FLOAT_MAX;
        $dist[$src] = 0;

        $queue = [[$src, 0]];
        while (!empty($queue)) {
            usort($queue, fn($a, $b) => $a[1] <=> $b[1]);
            [$u, $d] = array_shift($queue);
            if (isset($visited[$u])) continue;
            $visited[$u] = true;
            foreach ($this->adj[$u] as $edge) {
                $v = $edge['to']; $w = $edge['w'];
                if ($dist[$u] + $w < $dist[$v]) {
                    $dist[$v] = $dist[$u] + $w;
                    $queue[] = [$v, $dist[$v]];
                }
            }
        }
        return $dist;
    }

    public function bellmanFord(string $src): array|false {
        $dist = [];
        foreach ($this->nodes as $n => $_) $dist[$n] = PHP_FLOAT_MAX;
        $dist[$src] = 0;
        $nodeList = array_keys($this->nodes);

        for ($i = 0; $i < count($nodeList) - 1; $i++) {
            foreach ($this->adj as $u => $edges) {
                foreach ($edges as $edge) {
                    $v = $edge['to']; $w = $edge['w'];
                    if ($dist[$u] != PHP_FLOAT_MAX && $dist[$u] + $w < $dist[$v]) {
                        $dist[$v] = $dist[$u] + $w;
                    }
                }
            }
        }
        // 检测负环
        foreach ($this->adj as $u => $edges) {
            foreach ($edges as $edge) {
                $v = $edge['to']; $w = $edge['w'];
                if ($dist[$u] != PHP_FLOAT_MAX && $dist[$u] + $w < $dist[$v]) {
                    return false; // 负环
                }
            }
        }
        return $dist;
    }

    public function floydWarshall(): array {
        $dist = [];
        $nodes = array_keys($this->nodes);
        foreach ($nodes as $i) {
            foreach ($nodes as $j) {
                $dist[$i][$j] = ($i === $j) ? 0 : PHP_FLOAT_MAX;
            }
        }
        foreach ($this->adj as $u => $edges) {
            foreach ($edges as $edge) {
                $dist[$u][$edge['to']] = $edge['w'];
            }
        }
        foreach ($nodes as $k) {
            foreach ($nodes as $i) {
                foreach ($nodes as $j) {
                    if ($dist[$i][$k] + $dist[$k][$j] < $dist[$i][$j]) {
                        $dist[$i][$j] = $dist[$i][$k] + $dist[$k][$j];
                    }
                }
            }
        }
        return $dist;
    }

    public function getNodes(): array { return array_keys($this->nodes); }
}

// 测试
$g = new WeightedGraph();
$g->addEdge('A', 'B', 4);
$g->addEdge('A', 'C', 2);
$g->addEdge('B', 'C', 1);
$g->addEdge('B', 'D', 5);
$g->addEdge('C', 'D', 8);
$g->addEdge('C', 'E', 10);
$g->addEdge('D', 'E', 2);

echo "--- Dijkstra from A ---\n";
$dij = $g->dijkstra('A');
foreach ($dij as $node => $d) echo "  A→$node = " . ($d == PHP_FLOAT_MAX ? "INF" : $d) . "\n";

echo "\n--- Bellman-Ford from A ---\n";
$bf = $g->bellmanFord('A');
if ($bf === false) echo "  Negative cycle detected!\n";
else foreach ($bf as $node => $d) echo "  A→$node = " . ($d == PHP_FLOAT_MAX ? "INF" : $d) . "\n";

echo "\n--- Floyd-Warshall ---\n";
$fw = $g->floydWarshall();
$nodes = $g->getNodes();
echo "  " . implode("\t", array_merge([''], $nodes)) . "\n";
foreach ($nodes as $i) {
    $row = [$i];
    foreach ($nodes as $j) {
        $row[] = $fw[$i][$j] == PHP_FLOAT_MAX ? 'INF' : $fw[$i][$j];
    }
    echo "  " . implode("\t", $row) . "\n";
}

// 负权边测试
echo "\n--- Negative Edge (Bellman-Ford) ---\n";
$g2 = new WeightedGraph();
$g2->addEdge('A', 'B', 4, true);
$g2->addEdge('A', 'C', 2, true);
$g2->addEdge('B', 'C', -3, true);
$g2->addEdge('C', 'D', 2, true);
$g2->addEdge('B', 'D', 5, true);
$bf2 = $g2->bellmanFord('A');
if ($bf2 === false) echo "  Negative cycle!\n";
else foreach ($bf2 as $n => $d) echo "  A→$n = " . ($d == PHP_FLOAT_MAX ? "INF" : $d) . "\n";

echo "=== f061 Done ===\n";
