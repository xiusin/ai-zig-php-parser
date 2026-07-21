<?php
// 极度混搭: 分布式共识 + Raft模拟 + 领导者选举 + 日志复制
echo "=== f059: Consensus + Raft Sim + Leader Election ===\n";

class RaftNode {
    public string $state = 'follower'; // follower, candidate, leader
    public int $term = 0;
    public int $votedFor = -1;
    public array $log = [];
    public int $commitIndex = -1;
    public int $lastApplied = -1;
    public array $nextIndex = [];
    public array $matchIndex = [];
    public int $votes = 0;
    public int $id;

    public function __construct(int $id) { $this->id = $id; }
}

class RaftCluster {
    private array $nodes = [];
    private int $leaderId = -1;
    private array $events = [];

    public function __construct(int $nodeCount) {
        for ($i = 0; $i < $nodeCount; $i++) {
            $this->nodes[$i] = new RaftNode($i);
        }
    }

    public function startElection(int $candidateId): void {
        $candidate = $this->nodes[$candidateId];
        $candidate->state = 'candidate';
        $candidate->term++;
        $candidate->votedFor = $candidateId;
        $candidate->votes = 1;
        $this->events[] = "Node $candidateId starts election for term {$candidate->term}";

        // 请求其他节点投票
        $majority = (int)(count($this->nodes) / 2) + 1;
        foreach ($this->nodes as $node) {
            if ($node->id === $candidateId) continue;
            if ($node->term < $candidate->term && $node->votedFor === -1) {
                $node->term = $candidate->term;
                $node->votedFor = $candidateId;
                $candidate->votes++;
                $this->events[] = "Node {$node->id} votes for $candidateId";
            }
        }

        if ($candidate->votes >= $majority) {
            $candidate->state = 'leader';
            $this->leaderId = $candidateId;
            foreach ($this->nodes as $node) {
                if ($node->id !== $candidateId) {
                    $node->state = 'follower';
                    $node->votedFor = -1;
                }
                $candidate->nextIndex[$node->id] = count($candidate->log);
                $candidate->matchIndex[$node->id] = -1;
            }
            $this->events[] = "Node $candidateId becomes LEADER (term {$candidate->term}, votes={$candidate->votes})";
        } else {
            $candidate->state = 'follower';
            $this->events[] = "Node $candidateId failed election (votes={$candidate->votes})";
        }
    }

    public function appendEntry(int $leaderId, string $command): bool {
        if ($this->leaderId !== $leaderId) {
            $this->events[] = "Node $leaderId is not leader, rejected";
            return false;
        }
        $leader = $this->nodes[$leaderId];
        $entry = ['term' => $leader->term, 'command' => $command, 'index' => count($leader->log)];
        $leader->log[] = $entry;
        $this->events[] = "Leader $leaderId appends: '$command' (index={$entry['index']})";

        // 复制到跟随者
        $majority = (int)(count($this->nodes) / 2) + 1;
        $replicated = 1; // leader 自己
        foreach ($this->nodes as $node) {
            if ($node->id === $leaderId) continue;
            $node->log[] = $entry;
            $replicated++;
            $leader->matchIndex[$node->id] = $entry['index'];
            $this->events[] = "  Replicated to node {$node->id}";
        }

        if ($replicated >= $majority) {
            $leader->commitIndex = $entry['index'];
            $leader->lastApplied = $entry['index'];
            foreach ($this->nodes as $node) {
                if ($node->id !== $leaderId) {
                    $node->commitIndex = $entry['index'];
                    $node->lastApplied = $entry['index'];
                }
            }
            $this->events[] = "  Committed at index {$entry['index']} (replicated=$replicated)";
            return true;
        }
        return false;
    }

    public function failNode(int $nodeId): void {
        $node = $this->nodes[$nodeId];
        $wasLeader = $node->state === 'leader';
        $node->state = 'down';
        $this->events[] = "Node $nodeId FAILED" . ($wasLeader ? " (was leader!)" : "");

        if ($wasLeader) {
            $this->leaderId = -1;
            // 触发新选举
            $this->events[] = "Leader down, starting new election...";
            foreach ($this->nodes as $n) {
                if ($n->state === 'follower') {
                    $this->startElection($n->id);
                    if ($this->leaderId !== -1) break;
                }
            }
        }
    }

    public function recoverNode(int $nodeId): void {
        $this->nodes[$nodeId]->state = 'follower';
        $this->nodes[$nodeId]->votedFor = -1;
        $this->events[] = "Node $nodeId RECOVERED as follower";
    }

    public function getEvents(): array { return $this->events; }
    public function getLeader(): int { return $this->leaderId; }
    public function getNodes(): array { return $this->nodes; }
    public function clearEvents(): void { $this->events = []; }
}

// 测试
echo "--- 5-Node Cluster ---\n";
$cluster = new RaftCluster(5);

echo "\nStarting election (node 2):\n";
$cluster->startElection(2);
echo "Leader: node " . $cluster->getLeader() . "\n";

echo "\nAppend entries:\n";
$cluster->appendEntry(2, "SET x=1");
$cluster->appendEntry(2, "SET y=2");
$cluster->appendEntry(2, "SET z=3");

echo "\nNode states:\n";
foreach ($cluster->getNodes() as $node) {
    echo "  Node {$node->id}: state={$node->state} term={$node->term} log_count=" . count($node->log) . " commit={$node->commitIndex}\n";
}

echo "\n--- Leader Failure ---\n";
$cluster->clearEvents();
$cluster->failNode(2);
echo "New leader: node " . $cluster->getLeader() . "\n";

$cluster->appendEntry($cluster->getLeader(), "SET w=4");
echo "\nAfter new leader append:\n";
foreach ($cluster->getNodes() as $node) {
    $logCmds = array_map(fn($e) => $e['command'], $node->log);
    echo "  Node {$node->id}: state={$node->state} log=[" . implode(', ', $logCmds) . "] commit={$node->commitIndex}\n";
}

echo "\n--- Node Recovery ---\n";
$cluster->clearEvents();
$cluster->recoverNode(2);
echo "Events:\n";
foreach ($cluster->getEvents() as $e) echo "  $e\n";

echo "\n--- Election Failures ---\n";
$cluster->clearEvents();
$cluster2 = new RaftCluster(3);
$cluster2->failNode(0);
$cluster2->failNode(1);
echo "All but one node down, no election possible\n";
echo "Leader: " . $cluster2->getLeader() . "\n";

echo "\n--- Full Event Log ---\n";
foreach ($cluster->getEvents() as $e) echo "  $e\n";

echo "=== f059 Done ===\n";
