<?php
// 极度混搭: 负载均衡 + 多种策略 + 健康检查 + 熔断
echo "=== f098: LoadBalancer + Strategies + Health + Circuit ===\n";

class BackendServer {
    public bool $healthy = true;
    public int $requestCount = 0;
    public int $errorCount = 0;
    public int $successCount = 0;
    public int $currentLoad = 0;
    public int $weight = 1;
    public float $responseTime = 0;
    public string $circuitState = 'closed'; // closed, open, half-open

    public function __construct(public string $id, public string $host, int $weight = 1) {
        $this->weight = $weight;
    }

    public function request(): array {
        $this->requestCount++;
        if (!$this->healthy || $this->circuitState === 'open') {
            $this->errorCount++;
            return ['server' => $this->id, 'status' => 'rejected', 'reason' => 'unhealthy'];
        }
        // 模拟请求
        $this->currentLoad++;
        $failRate = 0.05;
        if ((mt_rand() / mt_getrandmax()) < $failRate) {
            $this->errorCount++;
            $this->responseTime = mt_rand(100, 500) / 100;
            $this->currentLoad--;
            return ['server' => $this->id, 'status' => 'error', 'time' => $this->responseTime];
        }
        $this->successCount++;
        $this->responseTime = mt_rand(10, 100) / 100;
        $this->currentLoad--;
        return ['server' => $this->id, 'status' => 'success', 'time' => $this->responseTime];
    }

    public function errorRate(): float {
        $total = $this->successCount + $this->errorCount;
        return $total > 0 ? $this->errorCount / $total : 0;
    }
}

abstract class LoadBalanceStrategy {
    abstract public function select(array $servers): ?BackendServer;
}

class RoundRobinStrategy extends LoadBalanceStrategy {
    private int $index = 0;
    public function select(array $servers): ?BackendServer {
        $healthy = array_values(array_filter($servers, fn($s) => $s->healthy && $s->circuitState !== 'open'));
        if (empty($healthy)) return null;
        $server = $healthy[$this->index % count($healthy)];
        $this->index++;
        return $server;
    }
}

class WeightedRoundRobinStrategy extends LoadBalanceStrategy {
    private array $currentWeights = [];
    public function select(array $servers): ?BackendServer {
        $healthy = array_filter($servers, fn($s) => $s->healthy && $s->circuitState !== 'open');
        if (empty($healthy)) return null;
        $total = 0;
        foreach ($healthy as $s) { $total += $s->weight; $this->currentWeights[$s->id] = ($this->currentWeights[$s->id] ?? 0) + $s->weight; }
        $best = null; $max = -1;
        foreach ($healthy as $s) {
            if ($this->currentWeights[$s->id] > $max) { $max = $this->currentWeights[$s->id]; $best = $s; }
        }
        $this->currentWeights[$best->id] -= $total;
        return $best;
    }
}

class LeastConnectionStrategy extends LoadBalanceStrategy {
    public function select(array $servers): ?BackendServer {
        $healthy = array_filter($servers, fn($s) => $s->healthy && $s->circuitState !== 'open');
        if (empty($healthy)) return null;
        usort($healthy, fn($a, $b) => $a->currentLoad <=> $b->currentLoad);
        return $healthy[0];
    }
}

class RandomStrategy extends LoadBalanceStrategy {
    public function select(array $servers): ?BackendServer {
        $healthy = array_values(array_filter($servers, fn($s) => $s->healthy && $s->circuitState !== 'open'));
        if (empty($healthy)) return null;
        return $healthy[array_rand($healthy)];
    }
}

class CircuitBreaker {
    private array $failureCounts = [];
    private array $lastFailureTime = [];

    public function __construct(private int $threshold = 5, private float $timeout = 5.0) {}

    public function recordSuccess(string $serverId): void {
        $this->failureCounts[$serverId] = 0;
    }

    public function recordFailure(string $serverId): void {
        $this->failureCounts[$serverId] = ($this->failureCounts[$serverId] ?? 0) + 1;
        $this->lastFailureTime[$serverId] = microtime(true);
    }

    public function check(string $serverId): string {
        $failures = $this->failureCounts[$serverId] ?? 0;
        if ($failures >= $this->threshold) {
            $elapsed = microtime(true) - ($this->lastFailureTime[$serverId] ?? 0);
            if ($elapsed < $this->timeout) return 'open';
            return 'half-open';
        }
        return 'closed';
    }
}

class LoadBalancer {
    private array $servers = [];
    private LoadBalanceStrategy $strategy;
    private CircuitBreaker $breaker;
    private array $stats = ['total' => 0, 'success' => 0, 'error' => 0, 'rejected' => 0];

    public function __construct(LoadBalanceStrategy $strategy) {
        $this->strategy = $strategy;
        $this->breaker = new CircuitBreaker();
    }

    public function addServer(BackendServer $server): void { $this->servers[] = $server; }

    public function request(): array {
        $this->stats['total']++;
        // 更新熔断器状态
        foreach ($this->servers as $s) {
            $s->circuitState = $this->breaker->check($s->id);
        }
        $server = $this->strategy->select($this->servers);
        if ($server === null) { $this->stats['rejected']++; return ['status' => 'no_server']; }
        $result = $server->request();
        if ($result['status'] === 'success') { $this->stats['success']++; $this->breaker->recordSuccess($server->id); }
        elseif ($result['status'] === 'error') { $this->stats['error']++; $this->breaker->recordFailure($server->id); }
        else { $this->stats['rejected']++; }
        return $result;
    }

    public function getStats(): array { return $this->stats; }
    public function getServers(): array { return $this->servers; }
    public function markUnhealthy(string $id): void {
        foreach ($this->servers as $s) { if ($s->id === $id) $s->healthy = false; }
    }
    public function markHealthy(string $id): void {
        foreach ($this->servers as $s) { if ($s->id === $id) { $s->healthy = true; $s->errorCount = 0; } }
    }
}

// 测试
function testStrategy(string $name, LoadBalanceStrategy $strategy, int $requests = 20): void {
    echo "\n--- $name ---\n";
    $lb = new LoadBalancer($strategy);
    $lb->addServer(new BackendServer('s1', '10.0.0.1', 1));
    $lb->addServer(new BackendServer('s2', '10.0.0.2', 3));
    $lb->addServer(new BackendServer('s3', '10.0.0.3', 1));
    for ($i = 0; $i < $requests; $i++) $lb->request();
    echo "Stats: " . json_encode($lb->getStats()) . "\n";
    echo "Server distribution:\n";
    foreach ($lb->getServers() as $s) {
        echo "  {$s->id}: requests={$s->requestCount} success={$s->successCount} errors={$s->errorCount} load={$s->currentLoad}\n";
    }
}

testStrategy('Round Robin', new RoundRobinStrategy());
testStrategy('Weighted RR', new WeightedRoundRobinStrategy());
testStrategy('Least Connection', new LeastConnectionStrategy());
testStrategy('Random', new RandomStrategy());

echo "\n--- Health Check & Failover ---\n";
$lb = new LoadBalancer(new RoundRobinStrategy());
$lb->addServer(new BackendServer('s1', '10.0.0.1'));
$lb->addServer(new BackendServer('s2', '10.0.0.2'));
$lb->addServer(new BackendServer('s3', '10.0.0.3'));

echo "Before failure:\n";
for ($i = 0; $i < 9; $i++) $lb->request();
foreach ($lb->getServers() as $s) echo "  {$s->id}: {$s->requestCount} requests\n";

$lb->markUnhealthy('s2');
echo "\nAfter s2 marked unhealthy:\n";
for ($i = 0; $i < 9; $i++) $lb->request();
foreach ($lb->getServers() as $s) echo "  {$s->id}: {$s->requestCount} requests (healthy=" . var_export($s->healthy, true) . ")\n";

$lb->markHealthy('s2');
echo "\nAfter s2 recovered:\n";
for ($i = 0; $i < 9; $i++) $lb->request();
foreach ($lb->getServers() as $s) echo "  {$s->id}: {$s->requestCount} requests\n";

echo "\n--- Circuit Breaker ---\n";
$lb2 = new LoadBalancer(new RoundRobinStrategy());
$lb2->addServer(new BackendServer('s1', '10.0.0.1'));
// 模拟大量失败触发熔断
for ($i = 0; $i < 100; $i++) $lb2->request();
echo "Stats after 100 requests: " . json_encode($lb2->getStats()) . "\n";
foreach ($lb2->getServers() as $s) {
    echo "  {$s->id}: circuit={$s->circuitState} errors={$s->errorCount} rate=" . number_format($s->errorRate() * 100, 1) . "%\n";
}

echo "=== f098 Done ===\n";
