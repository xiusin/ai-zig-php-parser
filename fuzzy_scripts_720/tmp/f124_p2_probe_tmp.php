<?php
echo "=== f124 p2: healthCheckAll internals ===\n";

class Container {
    public string $status = 'pending';
    public int $restartCount = 0;
    public function __construct(public string $id) {}
}

class Pod {
    public array $containers = [];
    public function __construct(public string $name) {}
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

function hac(array $pods): array {
    $results = [];
    $i = 0;
    foreach ($pods as $pod) {
        echo "outer:$i\n";
        $health = HealthCheck::check($pod);
        echo "checked:" . count($health) . "\n";
        $allHealthy = !in_array('unhealthy', $health);
        if (!$allHealthy) {
            echo "restarting\n";
            foreach ($pod->containers as $c) {
                echo " inner\n";
                if ($health[$c->id] === 'unhealthy') { $c->status = 'running'; $c->restartCount++; }
            }
            echo "restarted\n";
        }
        $results[$pod->name] = $allHealthy ? 'healthy' : 'restarted';
        echo "assigned\n";
        $i++;
    }
    echo "outerdone\n";
    return $results;
}

$pods = [];
for ($i = 0; $i < 2; $i++) {
    $pod = new Pod("web-$i");
    $c = new Container("c-$i");
    $c->status = 'running';
    $pod->addContainer($c);
    $pods["web-$i"] = $pod;
}

echo "A\n"; $h1 = hac($pods); echo "B\n";
echo "count1=" . count($h1) . "\n";
foreach ($h1 as $pod => $status) echo "  $pod: $status\n";
echo "C\n";

$firstPod = reset($pods);
if ($firstPod) {
    foreach ($firstPod->containers as $c) { $c->status = 'exited'; $c->restartCount = 6; }
    echo "Simulated failure\n";
}
echo "D\n"; $h2 = hac($pods); echo "E\n";
echo "count2=" . count($h2) . "\n";
foreach ($h2 as $pod => $status) echo "  $pod: $status\n";
echo "=== done ===\n";
