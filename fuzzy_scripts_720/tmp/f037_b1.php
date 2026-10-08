<?php
interface C { public function get(): mixed; }
class R implements C {
    private array $s = [];
    public function get(): mixed { return $this->s['k'] ?? null; }
    public function set(string $k, mixed $v): void { $this->s[$k] = $v; }
}
class M {
    private array $ad = [];
    private ?string $default = null;
    public function add(string $n, C $c, bool $d = false): self {
        $this->ad[$n] = $c;
        if ($d || $this->default === null) $this->default = $n;
        return $this;
    }
    public function getCache(string $name = ''): C {
        $name = $name ?: $this->default;
        return $this->ad[$name] ?? throw new RuntimeException("Unknown cache: $name");
    }
    public function set(string $k, mixed $v, string $n = ''): bool {
        $this->getCache($n)->set($k, $v);
        return true;
    }
    public function get(string $k, string $n = ''): mixed { return $this->getCache($n)->get(); }
}
$m = new M();
$m->add('redis', new R(), true);
$m->set('user:1', ['name' => 'Alice'], 'redis');
echo "get: "; var_dump($m->get('user:1', 'redis'));
echo "default flow: "; $m->set('dkey', 'dval'); var_dump($m->get('dkey'));
