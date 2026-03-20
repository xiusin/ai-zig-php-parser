<?php
class DisjointSet {
    private array $parent = [];
    private array $rank = [];

    public function __construct(array $items) {
        foreach ($items as $item) {
            $this->parent[$item] = $item;
            $this->rank[$item] = 0;
        }
    }

    public function find(string $x): string {
        if ($this->parent[$x] !== $x) {
            $this->parent[$x] = $this->find($this->parent[$x]);
        }
        return $this->parent[$x];
    }

    public function union(string $x, string $y): void {
        $rootX = $this->find($x);
        $rootY = $this->find($y);

        if ($rootX === $rootY) return;

        if ($this->rank[$rootX] < $this->rank[$rootY]) {
            $this->parent[$rootX] = $rootY;
        } elseif ($this->rank[$rootX] > $this->rank[$rootY]) {
            $this->parent[$rootY] = $rootX;
        } else {
            $this->parent[$rootY] = $rootX;
            $this->rank[$rootX]++;
        }
    }

    public function connected(string $x, string $y): bool {
        return $this->find($x) === $this->find($y);
    }
}

$ds = new DisjointSet(['a', 'b', 'c', 'd', 'e']);
$ds->union('a', 'b');
$ds->union('b', 'c');
$ds->union('d', 'e');

echo $ds->connected('a', 'c') ? 'true' : 'false' . "\n";
echo $ds->connected('a', 'e') ? 'true' : 'false' . "\n";
echo $ds->find('a') . "\n";
echo $ds->find('d') . "\n";
echo "OK\n";
