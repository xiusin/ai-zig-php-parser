<?php
// 电商系统 - 数据层
class ShopDB {
    private static ?ShopDB $instance = null;
    private array $tables = [];
    private int $autoId = 1;
    public array $eventLog = [];

    public static function getInstance(): self {
        if (self::$instance === null) self::$instance = new self();
        return self::$instance;
    }

    public function insert(string $table, array $data): int {
        $id = $this->autoId++;
        $data['id'] = $id;
        if (!isset($this->tables[$table])) $this->tables[$table] = [];
        $this->tables[$table][] = $data;
        $this->eventLog[] = "INSERT $table id=$id";
        return $id;
    }

    public function update(string $table, array $conditions, array $data): int {
        $count = 0;
        foreach ($this->tables[$table] ?? [] as &$row) {
            if ($this->match($row, $conditions)) {
                $row = array_merge($row, $data);
                $count++;
            }
        }
        $this->eventLog[] = "UPDATE $table affected=$count";
        return $count;
    }

    public function delete(string $table, array $conditions): int {
        $before = count($this->tables[$table] ?? []);
        $this->tables[$table] = array_values(array_filter(
            $this->tables[$table] ?? [],
            fn($r) => !$this->match($r, $conditions)
        ));
        $deleted = $before - count($this->tables[$table]);
        $this->eventLog[] = "DELETE $table deleted=$deleted";
        return $deleted;
    }

    public function select(string $table, array $conditions = [], ?int $limit = null, int $offset = 0, ?string $orderBy = null, string $dir = 'ASC'): array {
        $results = array_filter($this->tables[$table] ?? [], fn($r) => $this->match($r, $conditions));
        if ($orderBy !== null) {
            usort($results, function($a, $b) use ($orderBy, $dir) {
                $cmp = ($a[$orderBy] ?? 0) <=> ($b[$orderBy] ?? 0);
                return $dir === 'DESC' ? -$cmp : $cmp;
            });
        }
        if ($offset > 0) $results = array_slice($results, $offset);
        if ($limit !== null) $results = array_slice($results, 0, $limit);
        return array_values($results);
    }

    public function selectOne(string $table, array $conditions): ?array {
        $r = $this->select($table, $conditions, 1);
        return $r[0] ?? null;
    }

    public function count(string $table, array $conditions = []): int {
        return count($this->select($table, $conditions));
    }

    public function raw(string $table): array {
        return $this->tables[$table] ?? [];
    }

    private function match(array $row, array $conditions): bool {
        foreach ($conditions as $key => $value) {
            if (is_array($value)) {
                if (!in_array($row[$key] ?? null, $value)) return false;
            } else {
                if (($row[$key] ?? null) != $value) return false;
            }
        }
        return true;
    }
}
