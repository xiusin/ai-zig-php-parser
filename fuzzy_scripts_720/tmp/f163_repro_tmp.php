<?php
echo "=== f163 replay minimal repro ===\n";

class Ev { public function __construct(public string $name, public array $data = []) {} }

class Store {
    private array $events = [];
    private array $snapshots = [];
    public function append(string $id, Ev $e): void { $this->events[$id][] = $e; }
    public function saveSnapshot(string $id, array $state): void {
        $this->snapshots[$id] = ['state' => $state, 'version' => count($this->events[$id] ?? [])];
    }
    public function getSnapshot(string $id): ?array { return $this->snapshots[$id] ?? null; }
    public function replay(string $id, callable $reducer): array {
        $state = [];
        $snapshot = $this->getSnapshot($id);
        if ($snapshot) {
            $state = $snapshot['state'];
            $events = array_slice($this->events[$id] ?? [], $snapshot['version']);
        } else {
            $events = $this->events[$id] ?? [];
        }
        foreach ($events as $e) { $state = $reducer($state, $e); }
        return $state;
    }
}

$s = new Store();
$s->append('a1', new Ev('create', ['owner' => 'Alice']));
$s->append('a1', new Ev('dep', ['amount' => 100]));

$reducer = function(array $state, Ev $e): array {
    if ($e->name === 'create') { $state['owner'] = $e->data['owner']; $state['balance'] = 0; }
    if ($e->name === 'dep') { $state['balance'] = ($state['balance'] ?? 0) + $e->data['amount']; }
    return $state;
};

$st1 = $s->replay('a1', $reducer);
echo "no-snapshot: owner=" . ($st1['owner'] ?? 'MISS') . " bal=" . ($st1['balance'] ?? 'MISS') . "\n";

$s->saveSnapshot('a1', $st1);
$s->append('a1', new Ev('dep', ['amount' => 50]));
$st2 = $s->replay('a1', $reducer);
echo "with-snapshot: owner=" . ($st2['owner'] ?? 'MISS') . " bal=" . ($st2['balance'] ?? 'MISS') . "\n";
echo "=== done ===\n";
