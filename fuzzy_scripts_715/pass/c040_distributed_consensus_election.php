<?php
// 极度混搭: 分布式系统模拟 + 共识算法 + 领导者选举 + 日志复制 + 心跳
echo "=== c040: DistributedSim + Consensus + LeaderElection + LogReplication ===\n\n";

class Node {
    public string $id;
    public string $state = 'follower';
    public int $term = 0;
    public ?string $votedFor = null;
    public int $commitIndex = 0;
    public int $lastApplied = 0;
    public array $log = [];
    public bool $alive = true;
    public int $lastHeartbeat = 0;

    public function __construct(string $id) {
        $this->id = $id;
    }

    public function getState(): string { return $this->state; }
    public function getTerm(): int { return $this->term; }
    public function getLogSize(): int { return count($this->log); }
    public function isAlive(): bool { return $this->alive; }
    public function crash(): void { $this->alive = false; $this->state = 'down'; }
    public function restart(): void { $this->alive = true; $this->state = 'follower'; $this->votedFor = null; }

    public function appendLog(string $command, int $term): void {
        $this->log[] = ['term' => $term, 'command' => $command, 'index' => count($this->log)];
    }

    public function getLogFrom(int $index): array {
        return array_slice($this->log, $index);
    }
}

class Cluster {
    private array $nodes = [];
    private ?string $leaderId = null;
    private int $electionTimeout = 5;
    private int $heartbeatInterval = 1;
    private int $tick = 0;
    private array $events = [];

    public function addNode(string $id): Node {
        $node = new Node($id);
        $this->nodes[$id] = $node;
        return $node;
    }

    public function startElection(string $candidateId): bool {
        $candidate = $this->nodes[$candidateId] ?? null;
        if ($candidate === null || !$candidate->isAlive()) return false;

        $candidate->term++;
        $candidate->votedFor = $candidateId;
        $candidate->state = 'candidate';

        $votes = 1;
        foreach ($this->nodes as $id => $node) {
            if ($id === $candidateId || !$node->isAlive()) continue;
            if ($node->term < $candidate->term && $node->votedFor === null) {
                $node->votedFor = $candidateId;
                $votes++;
            }
        }

        $majority = intdiv(count($this->nodes), 2) + 1;
        if ($votes >= $majority) {
            $candidate->state = 'leader';
            $this->leaderId = $candidateId;
            $this->events[] = ['type' => 'election', 'term' => $candidate->term, 'leader' => $candidateId, 'votes' => $votes];
            return true;
        } else {
            $candidate->state = 'follower';
            $this->events[] = ['type' => 'election_failed', 'term' => $candidate->term, 'candidate' => $candidateId, 'votes' => $votes];
            return false;
        }
    }

    public function appendEntries(string $leaderId, string $command): bool {
        if ($this->leaderId !== $leaderId) return false;
        $leader = $this->nodes[$leaderId];
        $leader->appendLog($command, $leader->term);

        $replicated = 1;
        foreach ($this->nodes as $id => $node) {
            if ($id === $leaderId || !$node->isAlive()) continue;
            $node->appendLog($command, $leader->term);
            $replicated++;
        }

        $majority = intdiv(count($this->nodes), 2) + 1;
        if ($replicated >= $majority) {
            $leader->commitIndex++;
            $this->events[] = ['type' => 'commit', 'command' => $command, 'term' => $leader->term, 'replicas' => $replicated];
            return true;
        }
        return false;
    }

    public function sendHeartbeat(): void {
        if ($this->leaderId === null) return;
        foreach ($this->nodes as $node) {
            if ($node->isAlive()) {
                $node->lastHeartbeat = $this->tick;
            }
        }
    }

    public function tick_(): void {
        $this->tick++;
        $this->sendHeartbeat();

        foreach ($this->nodes as $node) {
            if (!$node->isAlive()) continue;
            if ($node->state === 'follower' && $this->tick - $node->lastHeartbeat > $this->electionTimeout) {
                $this->startElection($node->id);
            }
        }
    }

    public function getLeader(): ?string { return $this->leaderId; }
    public function getNodes(): array { return $this->nodes; }
    public function getEvents(): array { return $this->events; }
    public function getTick(): int { return $this->tick; }

    public function getNodeStates(): array {
        $states = [];
        foreach ($this->nodes as $id => $node) {
            $states[$id] = [
                'state' => $node->state,
                'term' => $node->term,
                'log_size' => $node->getLogSize(),
                'alive' => $node->isAlive(),
            ];
        }
        return $states;
    }
}

// === 测试 ===

echo "--- Cluster Setup ---\n";
$cluster = new Cluster();
$cluster->addNode('n1');
$cluster->addNode('n2');
$cluster->addNode('n3');
$cluster->addNode('n4');
$cluster->addNode('n5');

echo "Nodes: " . implode(", ", array_keys($cluster->getNodes())) . "\n";

echo "\n--- Leader Election ---\n";
echo "n1 starts election: " . var_export($cluster->startElection('n1'), true) . "\n";
echo "Leader: " . ($cluster->getLeader() ?? 'none') . "\n";

echo "\nNode states:\n";
foreach ($cluster->getNodeStates() as $id => $state) {
    echo "  $id: state={$state['state']} term={$state['term']} log={$state['log_size']}\n";
}

echo "\n--- Log Replication ---\n";
$cluster->appendEntries('n1', 'SET x=1');
$cluster->appendEntries('n1', 'SET y=2');
$cluster->appendEntries('n1', 'DELETE z');
$cluster->appendEntries('n1', 'INCREMENT counter');

echo "After 4 commands:\n";
foreach ($cluster->getNodeStates() as $id => $state) {
    echo "  $id: log_size={$state['log_size']}\n";
}

echo "\n--- Node Failure ---\n";
$nodes = $cluster->getNodes();
$nodes['n3']->crash();
echo "n3 crashed\n";
echo "n3 state: " . $nodes['n3']->getState() . "\n";

echo "\n--- Replication with Failure ---\n";
$cluster->appendEntries('n1', 'SET w=3');
echo "After n3 crash, new command:\n";
foreach ($cluster->getNodeStates() as $id => $state) {
    echo "  $id: state={$state['state']} log={$state['log_size']} alive=" . var_export($state['alive'], true) . "\n";
}

echo "\n--- Node Recovery ---\n";
$nodes['n3']->restart();
echo "n3 restarted\n";
echo "n3 state: " . $nodes['n3']->getState() . "\n";

echo "\n--- Heartbeat & Tick ---\n";
for ($i = 0; $i < 3; $i++) {
    $cluster->tick_();
}
echo "Tick: " . $cluster->getTick() . "\n";

echo "\n--- Events Log ---\n";
foreach ($cluster->getEvents() as $i => $event) {
    echo "  [$i] type={$event['type']}";
    if (isset($event['leader'])) echo " leader={$event['leader']}";
    if (isset($event['command'])) echo " command='{$event['command']}'";
    if (isset($event['votes'])) echo " votes={$event['votes']}";
    echo "\n";
}

echo "\n=== c040 Done ===\n";
