<?php
// 内存数据库模拟 + QueryBuilder
class Database {
    private static ?Database $instance = null;
    private array $tables = [];
    private int $autoId = 1;
    public array $queryLog = [];

    public static function getInstance(): self {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function table(string $name): QueryBuilder {
        if (!isset($this->tables[$name])) {
            $this->tables[$name] = [];
        }
        return new QueryBuilder($this, $name);
    }

    public function insert(string $table, array $data): int {
        $id = $this->autoId++;
        $data['id'] = $id;
        $this->tables[$table][] = $data;
        $this->log("INSERT INTO $table (id=$id)");
        return $id;
    }

    public function select(string $table, array $conditions = [], ?int $limit = null): array {
        $results = [];
        foreach ($this->tables[$table] ?? [] as $row) {
            $match = true;
            foreach ($conditions as $key => $value) {
                if (($row[$key] ?? null) != $value) {
                    $match = false;
                    break;
                }
            }
            if ($match) $results[] = $row;
        }
        if ($limit !== null) $results = array_slice($results, 0, $limit);
        $this->log("SELECT FROM $table (count=" . count($results) . ")");
        return $results;
    }

    public function update(string $table, array $conditions, array $data): int {
        $count = 0;
        foreach ($this->tables[$table] ?? [] as &$row) {
            $match = true;
            foreach ($conditions as $key => $value) {
                if (($row[$key] ?? null) != $value) { $match = false; break; }
            }
            if ($match) {
                $row = array_merge($row, $data);
                $count++;
            }
        }
        $this->log("UPDATE $table (affected=$count)");
        return $count;
    }

    public function delete(string $table, array $conditions): int {
        $before = count($this->tables[$table] ?? []);
        $this->tables[$table] = array_values(array_filter($this->tables[$table] ?? [], function($row) use ($conditions) {
            foreach ($conditions as $key => $value) {
                if (($row[$key] ?? null) == $value) return false;
            }
            return true;
        }));
        $deleted = $before - count($this->tables[$table]);
        $this->log("DELETE FROM $table (deleted=$deleted)");
        return $deleted;
    }

    public function raw(string $table): array {
        return $this->tables[$table] ?? [];
    }

    public function truncate(string $table): void {
        $this->tables[$table] = [];
    }

    private function log(string $query): void {
        $this->queryLog[] = $query;
    }

    public function getQueryLog(): array {
        return $this->queryLog;
    }
}

class QueryBuilder {
    private Database $db;
    private string $table;
    private array $wheres = [];
    private ?int $limit = null;
    private ?int $offset = null;
    private array $orders = [];
    private array $selects = ['*'];

    public function __construct(Database $db, string $table) {
        $this->db = $db;
        $this->table = $table;
    }

    public function where(string $column, mixed $operator, mixed $value = null): self {
        if ($value === null) {
            $value = $operator;
            $operator = '=';
        }
        $this->wheres[] = ['column' => $column, 'operator' => $operator, 'value' => $value];
        return $this;
    }

    public function whereIn(string $column, array $values): self {
        $this->wheres[] = ['column' => $column, 'operator' => 'IN', 'value' => $values];
        return $this;
    }

    public function orderBy(string $column, string $direction = 'ASC'): self {
        $this->orders[] = ['column' => $column, 'direction' => $direction];
        return $this;
    }

    public function limit(int $limit): self {
        $this->limit = $limit;
        return $this;
    }

    public function offset(int $offset): self {
        $this->offset = $offset;
        return $this;
    }

    public function get(): array {
        $results = $this->db->raw($this->table);

        // WHERE
        $results = array_filter($results, function($row) {
            foreach ($this->wheres as $where) {
                $col = $where['column'];
                $op = $where['operator'];
                $val = $where['value'];
                $rowVal = $row[$col] ?? null;
                switch ($op) {
                    case '=': if ($rowVal != $val) return false; break;
                    case '!=': case '<>': if ($rowVal == $val) return false; break;
                    case '>': if ($rowVal <= $val) return false; break;
                    case '<': if ($rowVal >= $val) return false; break;
                    case '>=': if ($rowVal < $val) return false; break;
                    case '<=': if ($rowVal > $val) return false; break;
                    case 'IN': if (!in_array($rowVal, $val)) return false; break;
                }
            }
            return true;
        });

        // ORDER BY
        if (!empty($this->orders)) {
            usort($results, function($a, $b) {
                foreach ($this->orders as $order) {
                    $col = $order['column'];
                    $dir = $order['direction'];
                    $aVal = $a[$col] ?? null;
                    $bVal = $b[$col] ?? null;
                    if ($aVal === $bVal) continue;
                    $cmp = ($aVal <=> $bVal);
                    return $dir === 'DESC' ? -$cmp : $cmp;
                }
                return 0;
            });
        }

        // OFFSET
        if ($this->offset !== null) {
            $results = array_slice($results, $this->offset);
        }

        // LIMIT
        if ($this->limit !== null) {
            $results = array_slice($results, 0, $this->limit);
        }

        return array_values($results);
    }

    public function first(): ?array {
        $results = $this->limit(1)->get();
        return $results[0] ?? null;
    }

    public function count(): int {
        return count($this->get());
    }

    public function insert(array $data): int {
        return $this->db->insert($this->table, $data);
    }

    public function update(array $data): int {
        $conditions = [];
        foreach ($this->wheres as $w) {
            if ($w['operator'] === '=') $conditions[$w['column']] = $w['value'];
        }
        return $this->db->update($this->table, $conditions, $data);
    }

    public function delete(): int {
        $conditions = [];
        foreach ($this->wheres as $w) {
            if ($w['operator'] === '=') $conditions[$w['column']] = $w['value'];
        }
        return $this->db->delete($this->table, $conditions);
    }
}
