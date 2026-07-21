<?php
// 图算法：DFS/BFS、最短路径、拓扑排序、连通分量
echo "=== f177: Graph Algorithms + DFS/BFS/ShortestPath ===\n";

class Graph {
    private array $adj = [];
    private bool $directed;

    public function __construct(bool $directed = false) {
        $this->directed = $directed;
    }

    public function addVertex(string $v): void {
        if (!isset($this->adj[$v])) $this->adj[$v] = [];
    }

    public function addEdge(string $from, string $to, int $weight = 1): void {
        $this->addVertex($from);
        $this->addVertex($to);
        $this->adj[$from][$to] = $weight;
        if (!$this->directed) {
            $this->adj[$to][$from] = $weight;
        }
    }

    public function getVertices(): array { return array_keys($this->adj); }
    public function getNeighbors(string $v): array { return $this->adj[$v] ?? []; }
    public function getEdgeWeight(string $from, string $to): ?int { return $this->adj[$from][$to] ?? null; }

    public function dfs(string $start): array {
        $visited = [];
        $result = [];
        $this->dfsHelper($start, $visited, $result);
        return $result;
    }

    private function dfsHelper(string $v, array &$visited, array &$result): void {
        $visited[$v] = true;
        $result[] = $v;
        foreach ($this->adj[$v] as $neighbor => $w) {
            if (!isset($visited[$neighbor])) {
                $this->dfsHelper($neighbor, $visited, $result);
            }
        }
    }

    public function bfs(string $start): array {
        $visited = [$start => true];
        $queue = [$start];
        $result = [];
        while (!empty($queue)) {
            $v = array_shift($queue);
            $result[] = $v;
            foreach ($this->adj[$v] as $neighbor => $w) {
                if (!isset($visited[$neighbor])) {
                    $visited[$neighbor] = true;
                    $queue[] = $neighbor;
                }
            }
        }
        return $result;
    }

    public function dijkstra(string $start): array {
        $dist = [];
        $visited = [];
        foreach ($this->adj as $v => $_) $dist[$v] = PHP_FLOAT_MAX;
        $dist[$start] = 0;

        while (true) {
            // 找到未访问的最小距离顶点
            $minDist = PHP_FLOAT_MAX;
            $minVertex = null;
            foreach ($dist as $v => $d) {
                if (!isset($visited[$v]) && $d < $minDist) {
                    $minDist = $d;
                    $minVertex = $v;
                }
            }
            if ($minVertex === null) break;
            $visited[$minVertex] = true;
            foreach ($this->adj[$minVertex] as $neighbor => $weight) {
                $newDist = $dist[$minVertex] + $weight;
                if ($newDist < $dist[$neighbor]) {
                    $dist[$neighbor] = $newDist;
                }
            }
        }
        return $dist;
    }

    public function topologicalSort(): array {
        if (!$this->directed) throw new Exception("Topological sort requires directed graph");
        $inDegree = [];
        foreach ($this->adj as $v => $neighbors) $inDegree[$v] = 0;
        foreach ($this->adj as $v => $neighbors) {
            foreach ($neighbors as $n => $w) $inDegree[$n] = ($inDegree[$n] ?? 0) + 1;
        }
        $queue = [];
        foreach ($inDegree as $v => $deg) {
            if ($deg === 0) $queue[] = $v;
        }
        $result = [];
        while (!empty($queue)) {
            $v = array_shift($queue);
            $result[] = $v;
            foreach ($this->adj[$v] as $neighbor => $w) {
                $inDegree[$neighbor]--;
                if ($inDegree[$neighbor] === 0) $queue[] = $neighbor;
            }
        }
        if (count($result) !== count($this->adj)) {
            throw new Exception("Graph has cycles, topological sort not possible");
        }
        return $result;
    }

    public function connectedComponents(): array {
        if ($this->directed) throw new Exception("Use stronglyConnectedComponents for directed graphs");
        $visited = [];
        $components = [];
        foreach ($this->adj as $v => $_) {
            if (!isset($visited[$v])) {
                $component = [];
                $this->dfsHelper($v, $visited, $component);
                $components[] = $component;
            }
        }
        return $components;
    }

    public function hasCycle(): bool {
        if ($this->directed) {
            $visited = [];
            $recursion = [];
            foreach ($this->adj as $v => $_) {
                if (!isset($visited[$v]) && $this->hasCycleDFS($v, $visited, $recursion)) {
                    return true;
                }
            }
            return false;
        } else {
            $visited = [];
            foreach ($this->adj as $v => $_) {
                if (!isset($visited[$v]) && $this->hasCycleUndirected($v, $visited, null)) {
                    return true;
                }
            }
            return false;
        }
    }

    private function hasCycleDFS(string $v, array &$visited, array &$recursion): bool {
        $visited[$v] = true;
        $recursion[$v] = true;
        foreach ($this->adj[$v] as $neighbor => $w) {
            if (!isset($visited[$neighbor])) {
                if ($this->hasCycleDFS($neighbor, $visited, $recursion)) return true;
            } elseif (isset($recursion[$neighbor])) {
                return true;
            }
        }
        $recursion[$v] = false;
        return false;
    }

    private function hasCycleUndirected(string $v, array &$visited, ?string $parent): bool {
        $visited[$v] = true;
        foreach ($this->adj[$v] as $neighbor => $w) {
            if (!isset($visited[$neighbor])) {
                if ($this->hasCycleUndirected($neighbor, $visited, $v)) return true;
            } elseif ($neighbor !== $parent) {
                return true;
            }
        }
        return false;
    }
}

// 测试
echo "--- Undirected Graph: DFS/BFS ---\n";
$g = new Graph(false);
$g->addEdge('A', 'B'); $g->addEdge('A', 'C');
$g->addEdge('B', 'D'); $g->addEdge('B', 'E');
$g->addEdge('C', 'F'); $g->addEdge('D', 'G');
$g->addEdge('E', 'G'); $g->addEdge('F', 'G');

echo "  Vertices: " . implode(', ', $g->getVertices()) . "\n";
echo "  DFS from A: " . implode(' → ', $g->dfs('A')) . "\n";
echo "  BFS from A: " . implode(' → ', $g->bfs('A')) . "\n";

echo "\n--- Shortest Path (Dijkstra) ---\n";
$wg = new Graph(true);
$wg->addEdge('A', 'B', 4); $wg->addEdge('A', 'C', 2);
$wg->addEdge('B', 'D', 3); $wg->addEdge('C', 'B', 1);
$wg->addEdge('C', 'D', 5); $wg->addEdge('C', 'E', 8);
$wg->addEdge('D', 'E', 2); $wg->addEdge('E', 'F', 3);
$wg->addEdge('D', 'F', 6);

$dist = $wg->dijkstra('A');
echo "  Shortest distances from A:\n";
foreach ($dist as $v => $d) {
    echo "    A → $v: $d\n";
}

echo "\n--- Topological Sort ---\n";
$dag = new Graph(true);
$dag->addEdge('CS101', 'CS201');
$dag->addEdge('CS101', 'CS102');
$dag->addEdge('CS102', 'CS201');
$dag->addEdge('CS201', 'CS301');
$dag->addEdge('CS201', 'CS302');
$dag->addEdge('CS301', 'CS401');
$dag->addEdge('CS302', 'CS401');
$dag->addEdge('MATH101', 'CS201');
$dag->addEdge('MATH101', 'CS301');

$topo = $dag->topologicalSort();
echo "  Course order: " . implode(' → ', $topo) . "\n";

echo "\n--- Cycle Detection ---\n";
echo "  DAG has cycle: " . ($dag->hasCycle() ? 'Y' : 'N') . "\n";
echo "  Undirected graph has cycle: " . ($g->hasCycle() ? 'Y' : 'N') . "\n";

$cyclic = new Graph(true);
$cyclic->addEdge('A', 'B');
$cyclic->addEdge('B', 'C');
$cyclic->addEdge('C', 'A');
echo "  Cyclic graph has cycle: " . ($cyclic->hasCycle() ? 'Y' : 'N') . "\n";

echo "\n--- Connected Components ---\n";
$ccGraph = new Graph(false);
$ccGraph->addEdge('A', 'B');
$ccGraph->addEdge('B', 'C');
$ccGraph->addEdge('D', 'E');
$ccGraph->addEdge('F', 'G');
$ccGraph->addEdge('G', 'H');
$ccGraph->addEdge('H', 'F');

$components = $ccGraph->connectedComponents();
echo "  Connected components: " . count($components) . "\n";
foreach ($components as $i => $comp) {
    echo "    Component $i: {" . implode(', ', $comp) . "}\n";
}

echo "=== f177 Done ===\n";
