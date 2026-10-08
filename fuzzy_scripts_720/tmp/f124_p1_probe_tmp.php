<?php
echo "=== f124 p1: healthCheckAll restart loop ===\n";

class Container {
    public string $status = 'pending';
    public int $restartCount = 0;
    public function __construct(public string $id, public string $image, public array $ports = [], public array $env = []) {}
}

class Pod {
    public string $phase = 'pending';
    public string $nodeIP = '';
    public array $containers = [];
    public function __construct(public string $name, public string $namespace = 'default') {}
    public function addContainer(Container $c): self { $this->containers[$c->id] = $c; return $this; }
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

$pods = [];
for ($i = 0; $i < 3; $i++) {
    $pod = new Pod("web-$i");
    $c = new Container("c-$i", 'nginx:latest', [80]);
    $c->status = 'running';
    $c->restartCount = 0;
    $pod->addContainer($c);
    $pods["web-$i"] = $pod;
}

function healthCheckAll(array $pods): array {
    $events = [];
    $results = [];
    foreach ($pods as $pod) {
        $health = HealthCheck::check($pod);
        $allHealthy = !in_array('unhealthy', $health);
        if (!$allHealthy) {
            $events[] = "Pod {$pod->name} unhealthy, restarting containers";
            foreach ($pod->containers as $c) {
                if ($health[$c->id] === 'unhealthy') { $c->status = 'running'; $c->restartCount++; }
            }
        }
        $results[$pod->name] = $allHealthy ? 'healthy' : 'restarted';
    }
    return $results;
}

echo "H1\n"; $h1 = healthCheckAll($pods); echo "H2\n";
foreach ($h1 as $pod => $status) echo "  $pod: $status\n";

$firstPod = reset($pods);
if ($firstPod) {
    foreach ($firstPod->containers as $c) { $c->status = 'exited'; $c->restartCount = 6; }
    echo "Simulated failure on {$firstPod->name}\n";
}
echo "H3\n"; $h2 = healthCheckAll($pods); echo "H4\n";
foreach ($h2 as $pod => $status) echo "  $pod: $status\n";
echo "=== done ===\n";
