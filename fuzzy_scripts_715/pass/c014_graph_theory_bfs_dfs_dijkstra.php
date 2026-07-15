<?php
// 极度混搭: 图论算法 + BFS/DFS + 最短路径 + 拓扑排序 + 环检测
echo "=== c014: Graph Theory + BFS/DFS + ShortestPath + TopoSort ===\n\n";

class Graph {
    private array $adjacency = [];
    private bool $directed;

    public function __construct(bool $directed = false) {
        $this->directed = $directed;
    }

    public function addNode(string $node): void {
        if (!isset($this->adjacency[$node])) {
            $this->adjacency[$node] = [];
        }
    }

    public function addEdge(string $from, string $to, int $weight = 1): void {
        $this->addNode($from);
        $this->addNode($to);
        $this->adjacency[$from][$to] = $weight;
        if (!$this->directed) {
            $this->adjacency[$to][$from] = $weight;
        }
    }

    public function getNeighbors(string $node): array {
        return $this->adjacency[$node] ?? [];
    }

    public function getNodes(): array {
        return array_keys($this->adjacency);
    }

    public function bfs(string $start): array {
        $visited = [];
        $queue = [$start];
        $visited[$start] = true;
        $order = [];

        while (!empty($queue)) {
            $node = array_shift($queue);
            $order[] = $node;
            $neighbors = $this->getNeighbors($node);
            ksort($neighbors);
            foreach ($neighbors as $neighbor => $weight) {
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
        $this->dfsVisit($start, $visited, $order);
        return $order;
    }

    private function dfsVisit(string $node, array &$visited, array &$order): void {
        $visited[$node] = true;
        $order[] = $node;
        $neighbors = $this->getNeighbors($node);
        ksort($neighbors);
        foreach ($neighbors as $neighbor => $weight) {
            if (!isset($visited[$neighbor])) {
                $this->dfsVisit($neighbor, $visited, $order);
            }
        }
    }

    public function dijkstra(string $start): array {
        $dist = [];
        $visited = [];
        foreach ($this->getNodes() as $node) {
            $dist[$node] = PHP_INT_MAX;
        }
        $dist[$start] = 0;

        $queue = [$start];
        while (!empty($queue)) {
            $minNode = null;
            $minDist = PHP_INT_MAX;
            foreach ($queue as $node) {
                if (!isset($visited[$node]) && $dist[$node] < $minDist) {
                    $minDist = $dist[$node];
                    $minNode = $node;
                }
            }
            if ($minNode === null) break;
            $visited[$minNode] = true;
            $queue = array_values(array_filter($queue, fn($n) => $n !== $minNode));

            foreach ($this->getNeighbors($minNode) as $neighbor => $weight) {
                $newDist = $dist[$minNode] + $weight;
                if ($newDist < $dist[$neighbor]) {
                    $dist[$neighbor] = $newDist;
                    $queue[] = $neighbor;
                }
            }
        }
        return $dist;
    }

    public function hasCycle(): bool {
        $visited = [];
        $recursionStack = [];
        foreach ($this->getNodes() as $node) {
            if (!isset($visited[$node])) {
                if ($this->cycleDFS($node, $visited, $recursionStack)) {
                    return true;
                }
            }
        }
        return false;
    }

    private function cycleDFS(string $node, array &$visited, array &$recursionStack): bool {
        $visited[$node] = true;
        $recursionStack[$node] = true;

        foreach ($this->getNeighbors($node) as $neighbor => $weight) {
            if (!isset($visited[$neighbor])) {
                if ($this->cycleDFS($neighbor, $visited, $recursionStack)) {
                    return true;
                }
            } elseif (isset($recursionStack[$neighbor])) {
                return true;
            }
        }
        $recursionStack[$node] = false;
        return false;
    }

    public function topologicalSort(): array {
        if ($this->hasCycle()) {
            return [];
        }
        $visited = [];
        $stack = [];
        foreach ($this->getNodes() as $node) {
            if (!isset($visited[$node])) {
                $this->topoDFS($node, $visited, $stack);
            }
        }
        return array_reverse($stack);
    }

    private function topoDFS(string $node, array &$visited, array &$stack): void {
        $visited[$node] = true;
        foreach ($this->getNeighbors($node) as $neighbor => $weight) {
            if (!isset($visited[$neighbor])) {
                $this->topoDFS($neighbor, $visited, $stack);
            }
        }
        $stack[] = $node;
    }
}

// === 测试 ===

echo "--- Undirected Graph BFS/DFS ---\n";
$graph = new Graph(false);
$graph->addEdge('A', 'B');
$graph->addEdge('A', 'C');
$graph->addEdge('B', 'D');
$graph->addEdge('C', 'D');
$graph->addEdge('D', 'E');
$graph->addEdge('B', 'E');

echo "BFS from A: " . implode("->", $graph->bfs('A')) . "\n";
echo "DFS from A: " . implode("->", $graph->dfs('A')) . "\n";

echo "\n--- Shortest Path (Dijkstra) ---\n";
$weighted = new Graph(true);
$weighted->addEdge('A', 'B', 4);
$weighted->addEdge('A', 'C', 2);
$weighted->addEdge('B', 'C', 1);
$weighted->addEdge('B', 'D', 5);
$weighted->addEdge('C', 'D', 8);
$weighted->addEdge('C', 'E', 10);
$weighted->addEdge('D', 'E', 2);
$weighted->addEdge('D', 'F', 6);
$weighted->addEdge('E', 'F', 3);

$dist = $weighted->dijkstra('A');
foreach ($dist as $node => $d) {
    echo "  $node: $d\n";
}

echo "\n--- Cycle Detection ---\n";
$acyclic = new Graph(true);
$acyclic->addEdge('A', 'B');
$acyclic->addEdge('B', 'C');
$acyclic->addEdge('C', 'D');
echo "Acyclic graph has cycle: " . var_export($acyclic->hasCycle(), true) . "\n";

$cyclic = new Graph(true);
$cyclic->addEdge('A', 'B');
$cyclic->addEdge('B', 'C');
$cyclic->addEdge('C', 'A');
echo "Cyclic graph has cycle: " . var_export($cyclic->hasCycle(), true) . "\n";

echo "\n--- Topological Sort ---\n";
$dag = new Graph(true);
$dag->addEdge('A', 'B');
$dag->addEdge('A', 'C');
$dag->addEdge('B', 'D');
$dag->addEdge('C', 'D');
$dag->addEdge('D', 'E');

$topoOrder = $dag->topologicalSort();
echo "Topological order: " . implode(" -> ", $topoOrder) . "\n";

echo "\n--- Complex Graph ---\n";
$complex = new Graph(true);
$complex->addEdge('task1', 'task2');
$complex->addEdge('task1', 'task3');
$complex->addEdge('task2', 'task4');
$complex->addEdge('task3', 'task4');
$complex->addEdge('task4', 'task5');
$complex->addEdge('task3', 'task5');

echo "Has cycle: " . var_export($complex->hasCycle(), true) . "\n";
echo "Topo sort: " . implode(" -> ", $complex->topologicalSort()) . "\n";
echo "BFS: " . implode(" -> ", $complex->bfs('task1')) . "\n";

echo "\n=== c014 Done ===\n";
