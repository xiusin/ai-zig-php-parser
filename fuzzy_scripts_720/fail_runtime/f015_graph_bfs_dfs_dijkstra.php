<?php
// 极度混搭: 图论算法 + BFS/DFS/Dijkstra + 邻接表 + 最短路径
echo "=== f015: Graph Theory + BFS/DFS/Dijkstra ===\n";

class Graph {
    private array $adj = [];
    private bool $directed;

    public function __construct(bool $directed = false) {
        $this->directed = $directed;
    }

    public function addNode(string $node): void {
        if (!isset($this->adj[$node])) {
            $this->adj[$node] = [];
        }
    }

    public function addEdge(string $from, string $to, int $weight = 1): void {
        $this->addNode($from);
        $this->addNode($to);
        $this->adj[$from][$to] = $weight;
        if (!$this->directed) {
            $this->adj[$to][$from] = $weight;
        }
    }

    public function bfs(string $start): array {
        $visited = [];
        $queue = [$start];
        $visited[$start] = true;
        $order = [];

        while (!empty($queue)) {
            $node = array_shift($queue);
            $order[] = $node;

            foreach ($this->adj[$node] as $neighbor => $w) {
                if (!isset($visited[$neighbor])) {
                    $visited[$neighbor] = true;
                    $queue[] = $neighbor;
                }
            }
        }
        return $order;
    }

    public function dfs(string $start): array {
        $visited = [];
        $order = [];
        $this->dfsHelper($start, $visited, $order);
        return $order;
    }

    private function dfsHelper(string $node, array &$visited, array &$order): void {
        $visited[$node] = true;
        $order[] = $node;

        $neighbors = array_keys($this->adj[$node] ?? []);
        sort($neighbors); // 保证顺序一致
        foreach ($neighbors as $neighbor) {
            if (!isset($visited[$neighbor])) {
                $this->dfsHelper($neighbor, $visited, $order);
            }
        }
    }

    public function dijkstra(string $start): array {
        $dist = [];
        $visited = [];
        foreach (array_keys($this->adj) as $node) {
            $dist[$node] = PHP_FLOAT_MAX;
        }
        $dist[$start] = 0;

        while (true) {
            // 找到未访问中距离最小的节点
            $minNode = null;
            $minDist = PHP_FLOAT_MAX;
            foreach ($dist as $node => $d) {
                if (!isset($visited[$node]) && $d < $minDist) {
                    $minDist = $d;
                    $minNode = $node;
                }
            }
            if ($minNode === null) break;
            $visited[$minNode] = true;

            foreach ($this->adj[$minNode] as $neighbor => $weight) {
                if (!isset($visited[$neighbor])) {
                    $newDist = $dist[$minNode] + $weight;
                    if ($newDist < $dist[$neighbor]) {
                        $dist[$neighbor] = $newDist;
                    }
                }
            }
        }
        return $dist;
    }

    public function hasCycle(): bool {
        $visited = [];
        $recStack = [];
        foreach (array_keys($this->adj) as $node) {
            if (!isset($visited[$node])) {
                if ($this->hasCycleDFS($node, $visited, $recStack)) {
                    return true;
                }
            }
        }
        return false;
    }

    private function hasCycleDFS(string $node, array &$visited, array &$recStack): bool {
        $visited[$node] = true;
        $recStack[$node] = true;

        foreach ($this->adj[$node] as $neighbor => $w) {
            if (!isset($visited[$neighbor])) {
                if ($this->hasCycleDFS($neighbor, $visited, $recStack)) return true;
            } elseif (isset($recStack[$neighbor])) {
                return true;
            }
        }
        $recStack[$node] = false;
        return false;
    }

    public function getNodes(): array {
        return array_keys($this->adj);
    }

    public function getEdges(): array {
        $edges = [];
        foreach ($this->adj as $from => $neighbors) {
            foreach ($neighbors as $to => $weight) {
                $edges[] = "$from->$to($weight)";
            }
        }
        return $edges;
    }
}

// === 测试 ===
// 城市路线图
$graph = new Graph(true);
$graph->addEdge('A', 'B', 4);
$graph->addEdge('A', 'C', 2);
$graph->addEdge('B', 'D', 3);
$graph->addEdge('B', 'E', 1);
$graph->addEdge('C', 'B', 1);
$graph->addEdge('C', 'D', 5);
$graph->addEdge('D', 'E', 2);
$graph->addEdge('E', 'A', 3);

echo "Nodes: " . implode(', ', $graph->getNodes()) . "\n";
echo "Edges: " . implode(', ', $graph->getEdges()) . "\n";

// BFS
echo "\nBFS from A: " . implode(' -> ', $graph->bfs('A')) . "\n";
echo "BFS from C: " . implode(' -> ', $graph->bfs('C')) . "\n";

// DFS
echo "DFS from A: " . implode(' -> ', $graph->dfs('A')) . "\n";
echo "DFS from C: " . implode(' -> ', $graph->dfs('C')) . "\n";

// Dijkstra
echo "\nDijkstra from A:\n";
$dist = $graph->dijkstra('A');
foreach ($dist as $node => $d) {
    echo "  A -> $node: $d\n";
}

echo "\nDijkstra from C:\n";
$dist2 = $graph->dijkstra('C');
foreach ($dist2 as $node => $d) {
    echo "  C -> $node: $d\n";
}

// 环检测
echo "\nHas cycle (directed): " . var_export($graph->hasCycle(), true) . "\n";

// 无向图测试
$undirected = new Graph(false);
$undirected->addEdge('X', 'Y', 1);
$undirected->addEdge('Y', 'Z', 1);
$undirected->addEdge('Z', 'W', 1);
$undirected->addEdge('W', 'X', 1);

echo "\nUndirected graph:\n";
echo "BFS from X: " . implode(' -> ', $undirected->bfs('X')) . "\n";
echo "DFS from X: " . implode(' -> ', $undirected->dfs('X')) . "\n";

$dist3 = $undirected->dijkstra('X');
echo "Dijkstra from X:\n";
foreach ($dist3 as $node => $d) {
    echo "  X -> $node: $d\n";
}

echo "=== f015 Done ===\n";
