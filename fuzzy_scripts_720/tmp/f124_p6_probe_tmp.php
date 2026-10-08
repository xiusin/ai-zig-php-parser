<?php
echo "=== f124 p6: double if-continue + tail ===\n";

class C {
    public string $s = 'running';
    public int $r = 0;
    public function __construct(public string $id) {}
}

function w1(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->s !== 'running') { $res[$c->id] = 'unhealthy'; continue; }
        if ($c->r > 5) { $res[$c->id] = 'unhealthy'; continue; }
        $res[$c->id] = 'healthy';
    }
    return $res;
}

function w2(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->r > 5) { $res[$c->id] = 'unhealthy'; continue; }
        if ($c->r > 3) { $res[$c->id] = 'sick'; continue; }
        $res[$c->id] = 'healthy';
    }
    return $res;
}

function w3(array $cs): array {
    $res = [];
    foreach ($cs as $c) {
        if ($c->r > 5) { continue; }
        if ($c->r > 3) { continue; }
        $res[] = $c->id;
    }
    return $res;
}

$cs = [];
$a = new C('a'); $cs[] = $a;
$b = new C('b'); $b->r = 9; $cs[] = $b;
$d = new C('d'); $d->s = 'exited'; $cs[] = $d;

echo "w1: "; var_export(w1($cs)); echo "\n";
echo "w2: "; var_export(w2($cs)); echo "\n";
echo "w3: "; var_export(w3($cs)); echo "\n";
echo "=== done ===\n";
