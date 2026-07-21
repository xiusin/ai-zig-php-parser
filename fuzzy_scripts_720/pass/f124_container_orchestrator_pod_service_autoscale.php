<?php
// 极度混搭: 容器编排 + Pod + 服务发现 + 健康检查 + 扩缩容
echo "=== f124: Container Orchestrator + Pod + ServiceDiscovery + Autoscale ===\n";

class Container {
    public string $status = 'pending';
    public int $restartCount = 0;
    public float $cpuUsage = 0;
    public int $memoryUsage = 0;
    public float $startTime = 0;

    public function __construct(public string $id, public string $image, public array $ports = [], public array $env = []) {}
}

class Pod {
    public string $phase = 'pending';
    public string $nodeIP = '';
    public array $containers = [];
    public float $cpuRequest = 0;
    public int $memoryRequest = 0;
    public array $labels = [];
    public array $conditions = [];

    public function __construct(public string $name, public string $namespace = 'default') {}

    public function addContainer(Container $c): self { $this->containers[$c->id] = $c; return $this; }

    public function isReady(): bool {
        if ($this->phase !== 'running') return false;
        foreach ($this->containers as $c) if ($c->status !== 'running') return false;
        return true;
    }

    public function getTotalCPU(): float {
        return array_sum(array_map(fn($c) => $c->cpuUsage, $this->containers));
    }

    public function getTotalMemory(): int {
        return array_sum(array_map(fn($c) => $c->memoryUsage, $this->containers));
    }
}

class Node {
    public float $cpuCapacity = 4.0; // cores
    public int $memoryCapacity = 8192; // MB
    public array $pods = [];
    public bool $ready = true;

    public function __construct(public string $name, public string $ip) {}

    public function getCPUUsage(): float { return array_sum(array_map(fn($p) => $p->getTotalCPU(), $this->pods)); }
    public function getMemoryUsage(): int { return array_sum(array_map(fn($p) => $p->getTotalMemory(), $this->pods)); }
    public function getCPUPercent(): float { return $this->getCPUUsage() / $this->cpuCapacity * 100; }
    public function getMemoryPercent(): float { return $this->getMemoryUsage() / $this->memoryCapacity * 100; }

    public function canSchedule(Pod $pod): bool {
        return $this->ready && ($this->getCPUUsage() + $pod->cpuRequest) <= $this->cpuCapacity &&
               ($this->getMemoryUsage() + $pod->memoryRequest) <= $this->memoryCapacity;
    }

    public function addPod(Pod $pod): void { $this->pods[$pod->name] = $pod; $pod->nodeIP = $this->ip; $pod->phase = 'running'; }
    public function removePod(string $name): ?Pod { $p = $this->pods[$name] ?? null; unset($this->pods[$name]); return $p; }
}

class Service {
    public array $endpoints = [];
    public function __construct(public string $name, public int $port, public array $selector = []) {}
    public function addEndpoint(string $ip, int $port): void { $this->endpoints[] = ['ip' => $ip, 'port' => $port]; }
    public function removeEndpoint(string $ip): void { $this->endpoints = array_values(array_filter($this->endpoints, fn($e) => $e['ip'] !== $ip)); }
    public function getEndpoints(): array { return $this->endpoints; }
}

class HealthCheck {
    public static function check(Pod $pod): array {
        $results = [];
        foreach ($pod->containers as $c) {
            if ($c->status !== 'running') { $results[$c->id] = 'unhealthy'; continue; }
            if ($c->restartCount > 5) { $results[$c->id] = 'unhealthy'; continue; }
            $results[$c->id] = 'healthy';
        }
        return $results;
    }
}

class Scheduler {
    public function schedule(array $nodes, Pod $pod): ?Node {
        // 简化: 最适合调度 (Best Fit)
        usort($nodes, fn($a, $b) => $b->getCPUPercent() <=> $a->getCPUPercent());
        foreach ($nodes as $node) {
            if ($node->canSchedule($pod)) return $node;
        }
        return null;
    }
}

class Autoscaler {
    public function __construct(private int $minReplicas = 2, private int $maxReplicas = 10, private float $targetCPUPercent = 70.0) {}

    public function calculateDesiredReplicas(array $pods, int $currentReplicas): int {
        if (empty($pods)) return $this->minReplicas;
        $totalCPU = array_sum(array_map(fn($p) => $p->getTotalCPU(), $pods));
        $totalRequest = array_sum(array_map(fn($p) => $p->cpuRequest, $pods));
        if ($totalRequest === 0) return $currentReplicas;
        $avgCPUPercent = ($totalCPU / $totalRequest) * 100;
        $desired = (int)ceil($currentReplicas * $avgCPUPercent / $this->targetCPUPercent);
        return max($this->minReplicas, min($this->maxReplicas, $desired));
    }
}

class ContainerOrchestrator {
    private array $nodes = [];
    private array $pods = [];
    private array $services = [];
    private Scheduler $scheduler;
    private Autoscaler $autoscaler;
    private array $events = [];

    public function __construct() {
        $this->scheduler = new Scheduler();
        $this->autoscaler = new Autoscaler();
    }

    public function addNode(Node $node): void { $this->nodes[$node->name] = $node; $this->log("Node {$node->name} joined"); }

    public function createPod(Pod $pod): bool {
        $node = $this->scheduler->schedule(array_values($this->nodes), $pod);
        if ($node === null) { $this->log("Failed to schedule pod {$pod->name}"); return false; }
        foreach ($pod->containers as $c) { $c->status = 'running'; $c->startTime = microtime(true); }
        $node->addPod($pod);
        $this->pods[$pod->name] = $pod;
        $this->log("Pod {$pod->name} scheduled on {$node->name}");
        $this->updateServiceEndpoints();
        return true;
    }

    public function deletePod(string $name): void {
        foreach ($this->nodes as $node) {
            if (isset($node->pods[$name])) { $node->removePod($name); break; }
        }
        unset($this->pods[$name]);
        $this->log("Pod $name deleted");
        $this->updateServiceEndpoints();
    }

    public function createService(Service $svc): void { $this->services[$svc->name] = $svc; $this->updateServiceEndpoints(); $this->log("Service {$svc->name} created"); }

    private function updateServiceEndpoints(): void {
        foreach ($this->services as $svc) {
            $svc->endpoints = [];
            foreach ($this->pods as $pod) {
                if (!$pod->isReady()) continue;
                $match = true;
                foreach ($svc->selector as $key => $value) {
                    if (($pod->labels[$key] ?? null) !== $value) { $match = false; break; }
                }
                if ($match) $svc->addEndpoint($pod->nodeIP, $svc->port);
            }
        }
    }

    public function healthCheckAll(): array {
        $results = [];
        foreach ($this->pods as $pod) {
            $health = HealthCheck::check($pod);
            $allHealthy = !in_array('unhealthy', $health);
            if (!$allHealthy) {
                $this->log("Pod {$pod->name} unhealthy, restarting containers");
                foreach ($pod->containers as $c) {
                    if ($health[$c->id] === 'unhealthy') { $c->status = 'running'; $c->restartCount++; }
                }
            }
            $results[$pod->name] = $allHealthy ? 'healthy' : 'restarted';
        }
        return $results;
    }

    public function autoscale(string $labelKey, string $labelValue): int {
        $matchingPods = array_filter($this->pods, fn($p) => ($p->labels[$labelKey] ?? null) === $labelValue);
        $current = count($matchingPods);
        $desired = $this->autoscaler->calculateDesiredReplicas($matchingPods, $current);
        if ($desired > $current) {
            $this->log("Scaling UP: $current → $desired replicas");
            for ($i = $current; $i < $desired; $i++) {
                $pod = $this->createAppPod("app-" . count($this->pods), $labelKey, $labelValue);
                $this->createPod($pod);
            }
        } elseif ($desired < $current) {
            $this->log("Scaling DOWN: $current → $desired replicas");
            $toRemove = array_slice(array_keys($matchingPods), 0, $current - $desired);
            foreach ($toRemove as $name) $this->deletePod($name);
        }
        return $desired;
    }

    private function createAppPod(string $name, string $labelKey, string $labelValue): Pod {
        $pod = new Pod($name);
        $pod->cpuRequest = 0.5;
        $pod->memoryRequest = 512;
        $pod->labels[$labelKey] = $labelValue;
        $container = new Container("c-$name", 'nginx:latest', [80]);
        $container->cpuUsage = 0.3 + mt_rand(0, 100) / 1000;
        $container->memoryUsage = 256 + mt_rand(0, 100);
        $pod->addContainer($container);
        return $pod;
    }

    private function log(string $msg): void { $this->events[] = ['time' => microtime(true), 'msg' => $msg]; }
    public function getEvents(): array { return $this->events; }
    public function getNodes(): array { return $this->nodes; }
    public function getPods(): array { return $this->pods; }
    public function getServices(): array { return $this->services; }
}

// 测试
echo "--- Setup Cluster ---\n";
$orch = new ContainerOrchestrator();
$orch->addNode(new Node('node-1', '10.0.0.1'));
$orch->addNode(new Node('node-2', '10.0.0.2'));
$orch->addNode(new Node('node-3', '10.0.0.3'));
echo "Nodes: " . count($orch->getNodes()) . "\n";

echo "\n--- Deploy Application ---\n";
for ($i = 0; $i < 3; $i++) {
    $pod = new Pod("web-$i");
    $pod->cpuRequest = 0.5;
    $pod->memoryRequest = 512;
    $pod->labels = ['app' => 'web'];
    $c = new Container("c-$i", 'nginx:latest', [80]);
    $c->cpuUsage = 0.3;
    $c->memoryUsage = 256;
    $pod->addContainer($c);
    $orch->createPod($pod);
    echo "  Created pod web-$i\n";
}

echo "\n--- Node Utilization ---\n";
foreach ($orch->getNodes() as $node) {
    echo "  {$node->name} ({$node->ip}): CPU=" . number_format($node->getCPUPercent(), 1) . "% Mem=" . number_format($node->getMemoryPercent(), 1) . "% Pods=" . count($node->pods) . "\n";
}

echo "\n--- Create Service ---\n";
$svc = new Service('web-service', 80, ['app' => 'web']);
$orch->createService($svc);
echo "Endpoints: " . count($svc->getEndpoints()) . "\n";
foreach ($svc->getEndpoints() as $ep) echo "  {$ep['ip']}:{$ep['port']}\n";

echo "\n--- Health Check ---\n";
$health = $orch->healthCheckAll();
foreach ($health as $pod => $status) echo "  $pod: $status\n";

echo "\n--- Simulate Failure ---\n";
$nodes = $orch->getNodes();
$firstNode = reset($nodes);
$firstPod = reset($firstNode->pods);
if ($firstPod) {
    foreach ($firstPod->containers as $c) { $c->status = 'exited'; $c->restartCount = 6; }
    echo "Simulated failure on {$firstPod->name}\n";
}
$health2 = $orch->healthCheckAll();
foreach ($health2 as $pod => $status) echo "  $pod: $status\n";

echo "\n--- Autoscale ---\n";
// Simulate high CPU
foreach ($orch->getPods() as $pod) {
    if (($pod->labels['app'] ?? null) === 'web') {
        foreach ($pod->containers as $c) $c->cpuUsage = 0.6;
    }
}
$desired = $orch->autoscale('app', 'web');
echo "Desired replicas: $desired\n";
echo "Current pods: " . count(array_filter($orch->getPods(), fn($p) => ($p->labels['app'] ?? null) === 'web')) . "\n";

echo "\n--- Scale Down ---\n";
foreach ($orch->getPods() as $pod) {
    if (($pod->labels['app'] ?? null) === 'web') {
        foreach ($pod->containers as $c) $c->cpuUsage = 0.1;
    }
}
$desired2 = $orch->autoscale('app', 'web');
echo "Desired replicas: $desired2\n";

echo "\n--- Final State ---\n";
foreach ($orch->getNodes() as $node) {
    echo "  {$node->name}: " . count($node->pods) . " pods, CPU=" . number_format($node->getCPUPercent(), 1) . "%\n";
}
echo "Services: " . count($orch->getServices()) . "\n";
echo "Total pods: " . count($orch->getPods()) . "\n";

echo "\n--- Events ---\n";
foreach ($orch->getEvents() as $e) echo "  {$e['msg']}\n";

echo "=== f124 Done ===\n";
