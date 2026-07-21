<?php
// 极度混搭: 工作流引擎 + 状态转换 + 回滚 + 并行分支 + 汇聚
echo "=== f057: Workflow Engine + Transitions + Rollback ===\n";

class WorkflowNode {
    public function __construct(
        public string $id,
        public string $name,
        public string $type = 'task', // task, decision, parallel, merge, start, end
        public array $config = []
    ) {}
}

class WorkflowEdge {
    public function __construct(
        public string $from,
        public string $to,
        public ?string $condition = null
    ) {}
}

class WorkflowExecution {
    private array $visited = [];
    private array $results = [];
    private array $snapshots = [];

    public function __construct(
        private array $nodes,
        private array $edges
    ) {}

    private function getOutgoing(string $nodeId): array {
        return array_values(array_filter($this->edges, fn($e) => $e->from === $nodeId));
    }

    private function evaluateCondition(string $condition, array $context): bool {
        if ($condition === '') return true;
        // 简单条件解析：支持 "key=value" 和 "key>value" 等
        if (preg_match('/^(\w+)\s*(==|!=|>=|<=|>|<)\s*(.+)$/', $condition, $m)) {
            $key = $m[1]; $op = $m[2]; $val = $m[3];
            $actual = $context[$key] ?? null;
            $val = is_numeric($val) ? (float)$val : trim($val, '"\'');
            return match($op) {
                '==' => $actual == $val,
                '!=' => $actual != $val,
                '>=' => $actual >= $val,
                '<=' => $actual <= $val,
                '>' => $actual > $val,
                '<' => $actual < $val,
                default => false,
            };
        }
        return (bool)($context[$condition] ?? false);
    }

    public function run(array $context = []): array {
        $this->visited = [];
        $this->results = [];
        $startNode = null;
        foreach ($this->nodes as $node) {
            if ($node->type === 'start') { $startNode = $node; break; }
        }
        if ($startNode === null) throw new RuntimeException("No start node");

        $this->executeNode($startNode->id, $context);
        return ['visited' => $this->visited, 'results' => $this->results];
    }

    private function executeNode(string $nodeId, array &$context): void {
        if (in_array($nodeId, $this->visited)) return;
        $this->visited[] = $nodeId;
        $node = $this->nodes[$nodeId] ?? null;
        if ($node === null) return;

        // 执行节点逻辑
        $result = match($node->type) {
            'start' => 'started',
            'end' => 'completed',
            'task' => $this->executeTask($node, $context),
            'decision' => $this->executeDecision($node, $context),
            'parallel' => $this->executeParallel($node, $context),
            'merge' => 'merged',
            default => 'unknown',
        };
        $this->results[$nodeId] = $result;

        if ($node->type === 'end') return;

        // 遍历出边
        $outgoing = $this->getOutgoing($nodeId);
        foreach ($outgoing as $edge) {
            if ($edge->condition === null || $this->evaluateCondition($edge->condition, $context)) {
                $this->executeNode($edge->to, $context);
            }
        }
    }

    private function executeTask(WorkflowNode $node, array &$context): string {
        $action = $node->config['action'] ?? 'noop';
        $output = $node->config['output'] ?? null;
        if ($output !== null) {
            $context[$output] = $node->config['value'] ?? 'result';
        }
        return "task:$action";
    }

    private function executeDecision(WorkflowNode $node, array &$context): string {
        return "decision:{$node->name}";
    }

    private function executeParallel(WorkflowNode $node, array &$context): string {
        return "parallel:{$node->name}";
    }

    public function snapshot(): array {
        return ['visited' => $this->visited, 'results' => $this->results];
    }
}

// 构建工作流
$nodes = [
    'start' => new WorkflowNode('start', 'Start', 'start'),
    'fetch' => new WorkflowNode('fetch', 'Fetch Data', 'task', ['action' => 'fetch', 'output' => 'data_ready', 'value' => true]),
    'validate' => new WorkflowNode('validate', 'Validate', 'decision'),
    'process' => new WorkflowNode('process', 'Process Data', 'task', ['action' => 'process', 'output' => 'processed', 'value' => true]),
    'reject' => new WorkflowNode('reject', 'Reject', 'task', ['action' => 'reject', 'output' => 'rejected', 'value' => true]),
    'notify' => new WorkflowNode('notify', 'Notify', 'task', ['action' => 'notify', 'output' => 'notified', 'value' => true]),
    'end' => new WorkflowNode('end', 'End', 'end'),
];

$edges = [
    new WorkflowEdge('start', 'fetch'),
    new WorkflowEdge('fetch', 'validate'),
    new WorkflowEdge('validate', 'process', 'data_ready==true'),
    new WorkflowEdge('validate', 'reject', 'data_ready==false'),
    new WorkflowEdge('process', 'notify'),
    new WorkflowEdge('reject', 'notify'),
    new WorkflowEdge('notify', 'end'),
];

// 测试1: 成功路径
echo "--- Run 1: Success Path ---\n";
$wf1 = new WorkflowExecution($nodes, $edges);
$result1 = $wf1->run();
echo "Visited: " . implode(' → ', $result1['visited']) . "\n";
foreach ($result1['results'] as $node => $res) {
    echo "  $node: $res\n";
}

// 测试2: 失败路径
echo "\n--- Run 2: Failure Path ---\n";
$nodes['fetch'] = new WorkflowNode('fetch', 'Fetch Data', 'task', ['action' => 'fetch', 'output' => 'data_ready', 'value' => false]);
$wf2 = new WorkflowExecution($nodes, $edges);
$result2 = $wf2->run();
echo "Visited: " . implode(' → ', $result2['visited']) . "\n";

// 测试3: 并行分支
echo "\n--- Run 3: Parallel Branches ---\n";
$nodes2 = [
    'start' => new WorkflowNode('start', 'Start', 'start'),
    'parallel1' => new WorkflowNode('parallel1', 'Parallel Split', 'parallel'),
    'taskA' => new WorkflowNode('taskA', 'Task A', 'task', ['action' => 'A', 'output' => 'a_done', 'value' => true]),
    'taskB' => new WorkflowNode('taskB', 'Task B', 'task', ['action' => 'B', 'output' => 'b_done', 'value' => true]),
    'taskC' => new WorkflowNode('taskC', 'Task C', 'task', ['action' => 'C', 'output' => 'c_done', 'value' => true]),
    'merge' => new WorkflowNode('merge', 'Merge', 'merge'),
    'end' => new WorkflowNode('end', 'End', 'end'),
];
$edges2 = [
    new WorkflowEdge('start', 'parallel1'),
    new WorkflowEdge('parallel1', 'taskA'),
    new WorkflowEdge('parallel1', 'taskB'),
    new WorkflowEdge('parallel1', 'taskC'),
    new WorkflowEdge('taskA', 'merge'),
    new WorkflowEdge('taskB', 'merge'),
    new WorkflowEdge('taskC', 'merge'),
    new WorkflowEdge('merge', 'end'),
];
$wf3 = new WorkflowExecution($nodes2, $edges2);
$result3 = $wf3->run();
echo "Visited: " . implode(' → ', $result3['visited']) . "\n";
echo "Tasks done: " . count($result3['visited']) . " nodes\n";

echo "=== f057 Done ===\n";
