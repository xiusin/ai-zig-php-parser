<?php
// 极度混搭: 分布式系统 + Raft共识 + 复制状态机 + 日志复制 + 选举
echo "=== f150: Distributed + Raft + LogReplication + Election + StateMachine ===\n";

class RaftLog {
    public array $entries = [];

    public function append(int $term, string $command): int {
        $index = count($this->entries);
        $this->entries[] = ['term' => $term, 'command' => $command, 'index' => $index];
        return $index;
    }

    public function get(int $index): ?array {
        return $this->entries[$index] ?? null;
    }

    public function getFrom(int $index): array {
        return array_slice($this->entries, $index);
    }

    public function truncateFrom(int $index): void {
        $this->entries = array_slice($this->entries, 0, $index);
    }

    public function getLastIndex(): int { return count($this->entries) - 1; }
    public function getLastTerm(): int { return empty($this->entries) ? 0 : end($this->entries)['term']; }
    public function count(): int { return count($this->entries); }
}

class StateMachine {
    private array $store = [];

    public function apply(string $command): mixed {
        $parts = explode(' ', $command);
        $op = $parts[0] ?? '';
        $key = $parts[1] ?? '';
        $value = $parts[2] ?? null;

        switch ($op) {
            case 'SET': $this->store[$key] = $value; return true;
            case 'GET': return $this->store[$key] ?? null;
            case 'DEL': unset($this->store[$key]); return true;
            case 'INC': $this->store[$key] = ($this->store[$key] ?? 0) + 1; return $this->store[$key];
            case 'CAS':
                $expected = $parts[3] ?? null;
                if (($this->store[$key] ?? null) == $expected) { $this->store[$key] = $value; return true; }
                return false;
            default: return null;
        }
    }

    public function snapshot(): array { return $this->store; }
    public function restore(array $state): void { $this->store = $state; }
}

class RaftNode {
    public string $state = 'follower'; // follower, candidate, leader
    public int $currentTerm = 0;
    public ?string $votedFor = null;
    public RaftLog $log;
    public int $commitIndex = -1;
    public int $lastApplied = -1;
    public array $nextIndex = [];
    public array $matchIndex = [];
    public array $votes = [];
    public StateMachine $stateMachine;
    public array $eventLog = [];

    public function __construct(public string $id, public array $peers = []) {
        $this->log = new RaftLog();
        $this->stateMachine = new StateMachine();
    }

    public function startElection(): void {
        $this->state = 'candidate';
        $this->currentTerm++;
        $this->votedFor = $this->id;
        $this->votes = [$this->id => true];
        $this->logEvent("Starting election for term {$this->currentTerm}");
    }

    public function receiveVote(string $from, int $term, bool $granted): void {
        if ($term > $this->currentTerm) {
            $this->currentTerm = $term;
            $this->state = 'follower';
            $this->votedFor = null;
            return;
        }
        if ($this->state !== 'candidate' || $term !== $this->currentTerm) return;
        if ($granted) {
            $this->votes[$from] = true;
            $this->logEvent("Received vote from $from");
            $voteCount = count($this->votes);
            $majority = (int)(ceil((count($this->peers) + 1) / 2));
            if ($voteCount >= $majority) $this->becomeLeader();
        }
    }

    public function becomeLeader(): void {
        $this->state = 'leader';
        $lastIdx = $this->log->getLastIndex() + 1;
        foreach ($this->peers as $peer) {
            $this->nextIndex[$peer] = $lastIdx;
            $this->matchIndex[$peer] = -1;
        }
        $this->logEvent("Became leader for term {$this->currentTerm}");
    }

    public function becomeFollower(int $term): void {
        $this->state = 'follower';
        $this->currentTerm = $term;
        $this->votedFor = null;
    }

    public function appendEntry(string $command): int {
        if ($this->state !== 'leader') return -1;
        $index = $this->log->append($this->currentTerm, $command);
        $this->logEvent("Appended log entry at index $index: $command");
        return $index;
    }

    public function replicateTo(string $peer): array {
        $nextIdx = $this->nextIndex[$peer] ?? 0;
        $entries = $this->log->getFrom($nextIdx);
        return [
            'term' => $this->currentTerm,
            'leaderId' => $this->id,
            'prevLogIndex' => $nextIdx - 1,
            'prevLogTerm' => $nextIdx > 0 ? ($this->log->get($nextIdx - 1)['term'] ?? 0) : 0,
            'entries' => $entries,
            'leaderCommit' => $this->commitIndex,
        ];
    }

    public function receiveAppendEntries(array $request): bool {
        $term = $request['term'];
        if ($term < $this->currentTerm) return false;
        if ($term > $this->currentTerm || $this->state !== 'follower') {
            $this->becomeFollower($term);
        }
        $this->logEvent("Received AppendEntries from {$request['leaderId']} (term $term, " . count($request['entries']) . " entries)");

        $prevLogIndex = $request['prevLogIndex'];
        if ($prevLogIndex >= 0) {
            $prevEntry = $this->log->get($prevLogIndex);
            if ($prevEntry === null) return false;
            if ($prevEntry['term'] !== $request['prevLogTerm']) {
                $this->log->truncateFrom($prevLogIndex);
                return false;
            }
        }

        foreach ($request['entries'] as $entry) {
            $existing = $this->log->get($entry['index']);
            if ($existing !== null && $existing['term'] !== $entry['term']) {
                $this->log->truncateFrom($entry['index']);
            }
            if ($this->log->get($entry['index']) === null) {
                $this->log->entries[] = $entry;
            }
        }

        if ($request['leaderCommit'] > $this->commitIndex) {
            $this->commitIndex = min($request['leaderCommit'], $this->log->getLastIndex());
            $this->applyCommitted();
        }
        return true;
    }

    public function receiveAppendResponse(string $peer, bool $success, int $matchIndex): void {
        if ($success) {
            $this->matchIndex[$peer] = $matchIndex;
            $this->nextIndex[$peer] = $matchIndex + 1;
            $this->advanceCommit();
        } else {
            $this->nextIndex[$peer] = max(0, ($this->nextIndex[$peer] ?? 1) - 1);
        }
    }

    private function advanceCommit(): void {
        for ($n = $this->log->getLastIndex(); $n > $this->commitIndex; $n--) {
            $replicas = 1; // self
            foreach ($this->peers as $peer) {
                if (($this->matchIndex[$peer] ?? -1) >= $n) $replicas++;
            }
            $majority = (int)(ceil((count($this->peers) + 1) / 2));
            if ($replicas >= $majority && $this->log->get($n)['term'] === $this->currentTerm) {
                $this->commitIndex = $n;
                $this->applyCommitted();
                break;
            }
        }
    }

    private function applyCommitted(): void {
        while ($this->lastApplied < $this->commitIndex) {
            $this->lastApplied++;
            $entry = $this->log->get($this->lastApplied);
            if ($entry) {
                $result = $this->stateMachine->apply($entry['command']);
                $this->logEvent("Applied log[{$this->lastApplied}]: {$entry['command']} → " . json_encode($result));
            }
        }
    }

    public function logEvent(string $msg): void { $this->eventLog[] = ['node' => $this->id, 'msg' => $msg, 'term' => $this->currentTerm, 'state' => $this->state]; }
    public function getEvents(): array { return $this->eventLog; }
    public function getStore(): array { return $this->stateMachine->snapshot(); }
}

class RaftCluster {
    public array $nodes = [];
    public array $network = [];
    public array $messages = [];

    public function addNode(RaftNode $node): void {
        $this->nodes[$node->id] = $node;
        foreach ($this->nodes as $id => $n) {
            if ($id !== $node->id) {
                $node->peers[] = $id;
                $n->peers[] = $node->id;
            }
        }
    }

    public function tick(): void {
        // 处理选举
        foreach ($this->nodes as $node) {
            if ($node->state === 'candidate') {
                foreach ($node->peers as $peer) {
                    if (!isset($node->votes[$peer])) {
                        $peerNode = $this->nodes[$peer];
                        // 模拟投票
                        if ($peerNode->state === 'follower' && ($peerNode->votedFor === null || $peerNode->votedFor === $node->id)) {
                            $peerNode->votedFor = $node->id;
                            $node->receiveVote($peer, $node->currentTerm, true);
                        } else {
                            $node->receiveVote($peer, $node->currentTerm, false);
                        }
                    }
                }
            }
        }

        // 处理日志复制
        foreach ($this->nodes as $node) {
            if ($node->state === 'leader') {
                foreach ($node->peers as $peer) {
                    $request = $node->replicateTo($peer);
                    $peerNode = $this->nodes[$peer];
                    $success = $peerNode->receiveAppendEntries($request);
                    $matchIndex = $success ? ($request['prevLogIndex'] + count($request['entries'])) : -1;
                    $node->receiveAppendResponse($peer, $success, $matchIndex);
                }
            }
        }
    }

    public function run(int $ticks = 10): void {
        for ($i = 0; $i < $ticks; $i++) $this->tick();
    }
}

// 测试
echo "--- Setup Raft Cluster (5 nodes) ---\n";
$cluster = new RaftCluster();
for ($i = 1; $i <= 5; $i++) $cluster->addNode(new RaftNode("node$i"));
echo "Nodes: " . implode(', ', array_keys($cluster->nodes)) . "\n";

echo "\n--- Leader Election ---\n";
$cluster->nodes['node1']->startElection();
$cluster->run(3);
foreach ($cluster->nodes as $node) echo "  {$node->id}: state={$node->state} term={$node->currentTerm}\n";
$leader = null;
foreach ($cluster->nodes as $node) if ($node->state === 'leader') { $leader = $node; break; }
echo "Leader: " . ($leader ? $leader->id : 'none') . "\n";

echo "\n--- Log Replication ---\n";
if ($leader) {
    $leader->appendEntry('SET x 100');
    $leader->appendEntry('SET y 200');
    $leader->appendEntry('INC x');
    $leader->appendEntry('SET z 300');
    $cluster->run(5);
    echo "Leader log entries: " . $leader->log->count() . "\n";
    echo "Leader commitIndex: {$leader->commitIndex}\n";
    echo "Leader lastApplied: {$leader->lastApplied}\n";
}

echo "\n--- State Machine Consistency ---\n";
foreach ($cluster->nodes as $node) {
    echo "  {$node->id}: state={$node->state} commit={$node->commitIndex} applied={$node->lastApplied} store=" . json_encode($node->getStore()) . "\n";
}

echo "\n--- Leader Failover ---\n";
if ($leader) {
    $oldLeader = $leader->id;
    unset($cluster->nodes[$oldLeader]);
    foreach ($cluster->nodes as $node) {
        $node->peers = array_values(array_filter($node->peers, fn($p) => $p !== $oldLeader));
    }
    echo "Removed $oldLeader from cluster\n";
    echo "Remaining nodes: " . implode(', ', array_keys($cluster->nodes)) . "\n";
    // 选举新leader
    $cluster->nodes['node2']->startElection();
    $cluster->run(5);
    foreach ($cluster->nodes as $node) echo "  {$node->id}: state={$node->state} term={$node->currentTerm}\n";
    $newLeader = null;
    foreach ($cluster->nodes as $node) if ($node->state === 'leader') { $newLeader = $node; break; }
    echo "New leader: " . ($newLeader ? $newLeader->id : 'none') . "\n";
}

echo "\n--- Network Partition Simulation ---\n";
$cluster2 = new RaftCluster();
for ($i = 1; $i <= 5; $i++) $cluster2->addNode(new RaftNode("n$i"));
$cluster2->nodes['n1']->startElection();
$cluster2->run(3);
$leader2 = null;
foreach ($cluster2->nodes as $node) if ($node->state === 'leader') { $leader2 = $node; break; }
if ($leader2) {
    $leader2->appendEntry('SET counter 0');
    $leader2->appendEntry('INC counter');
    $leader2->appendEntry('INC counter');
    $cluster2->run(5);
    echo "Before partition:\n";
    foreach ($cluster2->nodes as $node) echo "  {$node->id}: counter=" . ($node->getStore()['counter'] ?? 'null') . "\n";
    // 模拟分区: n4, n5 与 n1, n2, n3 断开
    echo "\nPartition: {n1,n2,n3} | {n4,n5}\n";
    $partitioned = ['n4', 'n5'];
    $mainPartition = ['n1', 'n2', 'n3'];
    foreach ($partitioned as $id) {
        $cluster2->nodes[$id]->peers = array_values(array_filter($cluster2->nodes[$id]->peers, fn($p) => in_array($p, $partitioned)));
    }
    if ($leader2 && $leader2->id === 'n1') {
        $leader2->appendEntry('INC counter');
        $leader2->appendEntry('INC counter');
    }
    // 只在主分区运行
    $tempCluster = new RaftCluster();
    foreach ($mainPartition as $id) $tempCluster->nodes[$id] = $cluster2->nodes[$id];
    $tempCluster->run(3);
    echo "After partition:\n";
    echo "  Main partition (n1,n2,n3):\n";
    foreach ($mainPartition as $id) echo "    {$id}: counter=" . ($cluster2->nodes[$id]->getStore()['counter'] ?? 'null') . "\n";
    echo "  Isolated (n4,n5):\n";
    foreach ($partitioned as $id) echo "    {$id}: counter=" . ($cluster2->nodes[$id]->getStore()['counter'] ?? 'null') . "\n";
}

echo "\n--- Event Log ---\n";
if (isset($cluster2->nodes['n1'])) {
    foreach (array_slice($cluster2->nodes['n1']->getEvents(), -10) as $event) {
        echo "  [{$event['node']}] (term={$event['term']}, {$event['state']}): {$event['msg']}\n";
    }
}

echo "\n--- Consensus Guarantee Check ---\n";
$cluster3 = new RaftCluster();
for ($i = 1; $i <= 3; $i++) $cluster3->addNode(new RaftNode("s$i"));
$cluster3->nodes['s1']->startElection();
$cluster3->run(3);
$leader3 = null;
foreach ($cluster3->nodes as $node) if ($node->state === 'leader') { $leader3 = $node; break; }
if ($leader3) {
    $cmds = ['SET a 1', 'SET b 2', 'SET c 3', 'INC a', 'DEL b'];
    foreach ($cmds as $cmd) $leader3->appendEntry($cmd);
    $cluster3->run(5);
    echo "After applying commands:\n";
    $allConsistent = true;
    $firstStore = null;
    foreach ($cluster3->nodes as $node) {
        $store = $node->getStore();
        if ($firstStore === null) $firstStore = $store;
        elseif ($store !== $firstStore) $allConsistent = false;
        echo "  {$node->id}: " . json_encode($store) . "\n";
    }
    echo "All nodes consistent: " . var_export($allConsistent, true) . "\n";
}

echo "=== f150 Done ===\n";
