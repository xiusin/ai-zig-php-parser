<?php
class QueryBuilder {
    private array $conditions = [];
    private array $orders = [];
    private ?int $limit = null;
    private ?int $offset = null;
    private string $table = '';

    public function from(string $table): self {
        $this->table = $table;
        return $this;
    }

    public function where(string $column, string $operator, mixed $value): self {
        $this->conditions[] = "$column $operator " . (is_string($value) ? "'$value'" : $value);
        return $this;
    }

    public function orderBy(string $column, string $direction = 'ASC'): self {
        $this->orders[] = "$column $direction";
        return $this;
    }

    public function limit(int $limit, ?int $offset = null): self {
        $this->limit = $limit;
        $this->offset = $offset;
        return $this;
    }

    public function toSql(): string {
        $sql = "SELECT * FROM {$this->table}";

        if (!empty($this->conditions)) {
            $sql .= " WHERE " . implode(' AND ', $this->conditions);
        }

        if (!empty($this->orders)) {
            $sql .= " ORDER BY " . implode(', ', $this->orders);
        }

        if ($this->limit !== null) {
            $sql .= " LIMIT {$this->limit}";
            if ($this->offset !== null) {
                $sql .= " OFFSET {$this->offset}";
            }
        }

        return $sql;
    }
}

$query = (new QueryBuilder())
    ->from('users')
    ->where('age', '>', 18)
    ->where('status', '=', 'active')
    ->orderBy('created_at', 'DESC')
    ->limit(10, 20)
    ->toSql();
echo $query . "\n";

$query2 = (new QueryBuilder())->from('products')->where('price', '>=', 100)->toSql();
echo $query2 . "\n";
echo "OK\n";
