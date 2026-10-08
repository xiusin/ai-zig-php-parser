<?php
echo "=== f124 p4: D1 minimization variants ===\n";

class C {
    public string $s = 'running';
    public int $r = 0;
    public function __construct(public string $id) {}
}

function v1(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->s !== 'running') { $res[$c->id] = 'unhealthy'; continue; }
        $res[$c->id] = 'healthy';
    }
    return $res;
}

function v2(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->r > 5) { $res[$c->id] = 'unhealthy'; continue; }
        $res[$c->id] = 'healthy';
    }
    return $res;
}

function v3(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->s !== 'running') { $res[$c->id] = 'unhealthy'; continue; }
        if ($c->r > 5) { $res[$c->id] = 'unhealthy'; }
        else { $res[$c->id] = 'mid'; }
        $res[$c->id] = 'healthy';
    }
    return $res;
}

function v4(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->s !== 'running') { continue; }
        if ($c->r > 5) { continue; }
        $res[] = $c->id;
    }
    return $res;
}

$cs = [];
$a = new C('a'); $cs[] = $a;
$b = new C('b'); $b->r = 9; $cs[] = $b;

echo "v1: "; var_export(v1($cs)); echo "\n";
echo "v2: "; var_export(v2($cs)); echo "\n";
echo "v3: "; var_export(v3($cs)); echo "\n";
echo "v4: "; var_export(v4($cs)); echo "\n";
echo "=== done ===\n";
