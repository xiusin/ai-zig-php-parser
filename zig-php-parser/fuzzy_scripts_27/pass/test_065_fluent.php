<?php
// Test 065: Method chaining, fluent interface
class QueryBuilder {
    private array $parts = [];

    public function select(string $columns): self {
        $this->parts['select'] = $columns;
        return $this;
    }

    public function from(string $table): self {
        $this->parts['from'] = $table;
        return $this;
    }

    public function where(string $condition): self {
        $this->parts['where'] = $condition;
        return $this;
    }

    public function orderBy(string $column): self {
        $this->parts['orderBy'] = $column;
        return $this;
    }

    public function limit(int $limit): self {
        $this->parts['limit'] = $limit;
        return $this;
    }

    public function build(): string {
        $sql = "SELECT " . ($this->parts['select'] ?? '*');
        $sql .= " FROM " . ($this->parts['from'] ?? '');
        if (isset($this->parts['where'])) {
            $sql .= " WHERE " . $this->parts['where'];
        }
        if (isset($this->parts['orderBy'])) {
            $sql .= " ORDER BY " . $this->parts['orderBy'];
        }
        if (isset($this->parts['limit'])) {
            $sql .= " LIMIT " . $this->parts['limit'];
        }
        return $sql;
    }
}

echo "=== Fluent interface ===\n";
$sql = (new QueryBuilder())
    ->select('id, name, email')
    ->from('users')
    ->where('active = 1')
    ->orderBy('created_at DESC')
    ->limit(10)
    ->build();

echo "Query: $sql\n";

echo "\n=== Builder pattern ===\n";
$builder = new QueryBuilder();
$builder->select('*')->from('posts');
echo "Simple query: " . $builder->build() . "\n";

echo "\n=== Chain different orders ===\n";
$sql1 = (new QueryBuilder())->from('users')->select('*')->build();
echo "From before select: $sql1\n";

$sql2 = (new QueryBuilder())->limit(5)->from('users')->select('id')->build();
echo "Limit before from: $sql2\n";

echo "\n=== Partial build ===\n";
$partial = (new QueryBuilder())->select('name')->from('products')->build();
echo "Partial: $partial\n";