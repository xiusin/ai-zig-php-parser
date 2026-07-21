<?php
// 博客系统 - 数据存储层（独立内存数据库，不依赖 Web 框架）
class BlogDB {
    private static ?BlogDB $instance = null;
    private array $tables = [];
    private int $autoId = 1;

    public static function getInstance(): self {
        if (self::$instance === null) self::$instance = new self();
        return self::$instance;
    }

    public function insert(string $table, array $data): int {
        $id = $this->autoId++;
        $data['id'] = $id;
        if (!isset($this->tables[$table])) $this->tables[$table] = [];
        $this->tables[$table][] = $data;
        return $id;
    }

    public function update(string $table, array $conditions, array $data): int {
        $count = 0;
        foreach ($this->tables[$table] ?? [] as &$row) {
            if ($this->matchConditions($row, $conditions)) {
                $row = array_merge($row, $data);
                $count++;
            }
        }
        return $count;
    }

    public function delete(string $table, array $conditions): int {
        $before = count($this->tables[$table] ?? []);
        $this->tables[$table] = array_values(array_filter(
            $this->tables[$table] ?? [],
            fn($row) => !$this->matchConditions($row, $conditions)
        ));
        return $before - count($this->tables[$table]);
    }

    public function select(string $table, array $conditions = [], ?int $limit = null, int $offset = 0, string $orderBy = null, string $orderDir = 'ASC'): array {
        $results = array_filter($this->tables[$table] ?? [], fn($row) => $this->matchConditions($row, $conditions));
        if ($orderBy !== null) {
            usort($results, function($a, $b) use ($orderBy, $orderDir) {
                $cmp = ($a[$orderBy] ?? 0) <=> ($b[$orderBy] ?? 0);
                return $orderDir === 'DESC' ? -$cmp : $cmp;
            });
        }
        if ($offset > 0) $results = array_slice($results, $offset);
        if ($limit !== null) $results = array_slice($results, 0, $limit);
        return array_values($results);
    }

    public function selectOne(string $table, array $conditions): ?array {
        $results = $this->select($table, $conditions, 1);
        return $results[0] ?? null;
    }

    public function count(string $table, array $conditions = []): int {
        return count($this->select($table, $conditions));
    }

    public function raw(string $table): array {
        return $this->tables[$table] ?? [];
    }

    public function join(string $table1, string $table2, string $key1, string $key2, array $conditions = []): array {
        $results = [];
        $t1 = $this->tables[$table1] ?? [];
        $t2 = $this->tables[$table2] ?? [];
        foreach ($t1 as $row1) {
            if (!$this->matchConditions($row1, $conditions)) continue;
            foreach ($t2 as $row2) {
                if (($row1[$key1] ?? null) === ($row2[$key2] ?? null)) {
                    $results[] = array_merge($row1, ['_joined_' . $table2 => $row2]);
                }
            }
        }
        return $results;
    }

    private function matchConditions(array $row, array $conditions): bool {
        foreach ($conditions as $key => $value) {
            if (is_array($value)) {
                if (!in_array($row[$key] ?? null, $value)) return false;
            } else {
                if (($row[$key] ?? null) != $value) return false;
            }
        }
        return true;
    }

    public function truncateAll(): void {
        $this->tables = [];
        $this->autoId = 1;
    }
}
