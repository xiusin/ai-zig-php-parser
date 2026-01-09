<?php
class GraphNode {
    public $name;
    public $neighbors = [];

    public function __construct($name) {
        $this->name = $name;
    }

    public function addNeighbor($node) {
        $this->neighbors[] = $node;
    }
}

function dfs($node, &$visited = [], $depth = 0) {
    if (isset($visited[$node->name])) {
        return;
    }
    $visited[$node->name] = true;
    echo str_repeat("  ", $depth) . $node->name . "\n";
    foreach ($node->neighbors as $neighbor) {
        dfs($neighbor, $visited, $depth + 1);
    }
}

function bfs($start) {
    $queue = [$start];
    $visited = [$start->name => true];
    $depth = 0;

    while (!empty($queue)) {
        $levelSize = count($queue);
        echo "Level $depth: ";
        for ($i = 0; $i < $levelSize; $i++) {
            $node = array_shift($queue);
            echo $node->name . " ";
            foreach ($node->neighbors as $neighbor) {
                if (!isset($visited[$neighbor->name])) {
                    $visited[$neighbor->name] = true;
                    $queue[] = $neighbor;
                }
            }
        }
        echo "\n";
        $depth++;
    }
}

$a = new GraphNode("A");
$b = new GraphNode("B");
$c = new GraphNode("C");
$d = new GraphNode("D");
$e = new GraphNode("E");

$a->addNeighbor($b);
$a->addNeighbor($c);
$b->addNeighbor($d);
$c->addNeighbor($d);
$d->addNeighbor($e);

echo "DFS:\n";
dfs($a);

echo "\nBFS:\n";
bfs($a);
