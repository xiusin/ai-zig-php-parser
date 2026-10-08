<?php
echo "=== f124 p3: if-continue chain trailing store ===\n";

class C {
    public string $s = 'running';
    public int $r = 0;
    public function __construct(public string $id) {}
}

function check(array $cs): array {
    $results = [];
    foreach ($cs as $c) {
        if ($c->s !== 'running') { $results[$c->id] = 'unhealthy'; continue; }
        if ($c->r > 5) { $results[$c->id] = 'unhealthy'; continue; }
        $results[$c->id] = 'healthy';
    }
    return $results;
}

$cs = [];
$cs[] = new C('a');
$cs[] = new C('b');
$cs[1]->r = 9;
var_dump(check($cs));
echo "=== done ===\n";
