<?php
// 极度混搭: SQL查询构建器 + 条件组合 + JOIN模拟 + 聚合 + 子查询
echo "=== c036: QueryBuilder + Conditions + JOIN + Aggregate + SubQuery ===\n\n";

class QueryBuilder {
    private string $table = '';
    private string $alias = '';
    private array $select = ['*'];
    private array $wheres = [];
    private array $joins = [];
    private array $orderBy = [];
    private ?int $limit = null;
    private ?int $offset = null;
    private array $groupBy = [];
    private array $having = [];
    private array $params = [];
    private int $paramCount = 0;

    public function from(string $table, string $alias = ''): self {
        $this->table = $table;
        $this->alias = $alias;
        return $this;
    }

    public function select(string ...$columns): self {
        $this->select = $columns;
        return $this;
    }

    public function selectRaw(string $expr, string $alias = ''): self {
        $this->select[] = $expr . ($alias ? " AS $alias" : '');
        return $this;
    }

    public function where(string $column, string $op, mixed $value): self {
        $param = $this->addParam($value);
        $this->wheres[] = "$column $op $param";
        return $this;
    }

    public function whereIn(string $column, array $values): self {
        if (empty($values)) {
            $this->wheres[] = "1=0";
            return $this;
        }
        $params = [];
        foreach ($values as $v) {
            $params[] = $this->addParam($v);
        }
        $this->wheres[] = "$column IN (" . implode(", ", $params) . ")";
        return $this;
    }

    public function whereLike(string $column, string $pattern): self {
        $param = $this->addParam($pattern);
        $this->wheres[] = "$column LIKE $param";
        return $this;
    }

    public function whereNull(string $column): self {
        $this->wheres[] = "$column IS NULL";
        return $this;
    }

    public function whereNotNull(string $column): self {
        $this->wheres[] = "$column IS NOT NULL";
        return $this;
    }

    public function whereBetween(string $column, mixed $low, mixed $high): self {
        $p1 = $this->addParam($low);
        $p2 = $this->addParam($high);
        $this->wheres[] = "$column BETWEEN $p1 AND $p2";
        return $this;
    }

    public function whereExists(callable $callback): self {
        $sub = new self();
        $callback($sub);
        $this->wheres[] = "EXISTS (" . $sub->buildSQL() . ")";
        return $this;
    }

    public function join(string $table, string $first, string $op, string $second, string $type = 'INNER'): self {
        $this->joins[] = "$type JOIN $table ON $first $op $second";
        return $this;
    }

    public function leftJoin(string $table, string $first, string $op, string $second): self {
        return $this->join($table, $first, $op, $second, 'LEFT');
    }

    public function rightJoin(string $table, string $first, string $op, string $second): self {
        return $this->join($table, $first, $op, $second, 'RIGHT');
    }

    public function groupBy(string ...$columns): self {
        $this->groupBy = $columns;
        return $this;
    }

    public function having(string $column, string $op, mixed $value): self {
        $param = $this->addParam($value);
        $this->having[] = "$column $op $param";
        return $this;
    }

    public function orderBy(string $column, string $dir = 'ASC'): self {
        $this->orderBy[] = "$column $dir";
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

    private function addParam(mixed $value): string {
        $this->paramCount++;
        $key = "p{$this->paramCount}";
        $this->params[$key] = $value;
        return ":$key";
    }

    public function buildSQL(): string {
        $sql = "SELECT " . implode(", ", $this->select);

        $tablePart = $this->table;
        if ($this->alias) $tablePart .= " AS {$this->alias}";
        $sql .= " FROM $tablePart";

        foreach ($this->joins as $join) {
            $sql .= " $join";
        }

        if (!empty($this->wheres)) {
            $sql .= " WHERE " . implode(" AND ", $this->wheres);
        }

        if (!empty($this->groupBy)) {
            $sql .= " GROUP BY " . implode(", ", $this->groupBy);
        }

        if (!empty($this->having)) {
            $sql .= " HAVING " . implode(" AND ", $this->having);
        }

        if (!empty($this->orderBy)) {
            $sql .= " ORDER BY " . implode(", ", $this->orderBy);
        }

        if ($this->limit !== null) {
            $sql .= " LIMIT {$this->limit}";
        }

        if ($this->offset !== null) {
            $sql .= " OFFSET {$this->offset}";
        }

        return $sql;
    }

    public function getParams(): array {
        return $this->params;
    }

    public function toDebug(): string {
        $sql = $this->buildSQL();
        $params = $this->getParams();
        foreach ($params as $key => $val) {
            $sql = str_replace(":$key", var_export($val, true), $sql);
        }
        return $sql;
    }
}

class InMemoryDatabase {
    private array $tables = [];

    public function insert(string $table, array $rows): void {
        if (!isset($this->tables[$table])) {
            $this->tables[$table] = [];
        }
        foreach ($rows as $row) {
            $this->tables[$table][] = $row;
        }
    }

    public function select(string $table, array $columns = ['*'], ?callable $filter = null): array {
        if (!isset($this->tables[$table])) return [];
        $rows = $this->tables[$table];
        if ($filter !== null) {
            $rows = array_filter($rows, $filter);
        }
        if ($columns === ['*']) return $rows;
        $result = [];
        foreach ($rows as $row) {
            $filtered = [];
            foreach ($columns as $col) {
                if (isset($row[$col])) $filtered[$col] = $row[$col];
            }
            $result[] = $filtered;
        }
        return $result;
    }

    public function aggregate(string $table, string $func, string $column, ?callable $filter = null): mixed {
        $rows = $this->select($table, [$column], $filter);
        $values = array_column($rows, $column);
        return match($func) {
            'COUNT' => count($values),
            'SUM' => array_sum($values),
            'AVG' => count($values) > 0 ? array_sum($values) / count($values) : 0,
            'MIN' => count($values) > 0 ? min($values) : null,
            'MAX' => count($values) > 0 ? max($values) : null,
            default => null,
        };
    }

    public function joinTables(string $t1, string $t2, string $leftKey, string $rightKey, string $joinType = 'INNER'): array {
        $left = $this->tables[$t1] ?? [];
        $right = $this->tables[$t2] ?? [];
        $result = [];
        foreach ($left as $lRow) {
            $matched = false;
            foreach ($right as $rRow) {
                if (($lRow[$leftKey] ?? null) === ($rRow[$rightKey] ?? null)) {
                    $result[] = array_merge($lRow, $rRow);
                    $matched = true;
                }
            }
            if (!$matched && $joinType === 'LEFT') {
                $result[] = array_merge($lRow, array_fill_keys(array_keys($right[0] ?? []), null));
            }
        }
        return $result;
    }

    public function count(string $table): int {
        return count($this->tables[$table] ?? []);
    }
}

// === 测试 ===

echo "--- Query Builder: Basic ---\n";
$qb = (new QueryBuilder())
    ->from('users', 'u')
    ->select('u.id', 'u.name', 'u.email')
    ->where('u.age', '>', 18)
    ->where('u.status', '=', 'active')
    ->orderBy('u.name', 'ASC')
    ->limit(10);

echo "SQL: " . $qb->buildSQL() . "\n";
echo "Params: " . json_encode($qb->getParams()) . "\n";
echo "Debug: " . $qb->toDebug() . "\n";

echo "\n--- Query Builder: WHERE variations ---\n";
$qb2 = (new QueryBuilder())
    ->from('products', 'p')
    ->select('p.id', 'p.name', 'p.price')
    ->whereIn('p.category_id', [1, 2, 3])
    ->whereBetween('p.price', 10, 100)
    ->whereLike('p.name', '%phone%')
    ->whereNotNull('p.stock')
    ->orderBy('p.price', 'DESC')
    ->limit(20, );

echo "SQL: " . $qb2->buildSQL() . "\n";
echo "Debug: " . $qb2->toDebug() . "\n";

echo "\n--- Query Builder: JOIN ---\n";
$qb3 = (new QueryBuilder())
    ->from('orders', 'o')
    ->select('o.id', 'o.total', 'c.name', 'c.email')
    ->join('customers', 'c', '=', 'o.customer_id')
    ->leftJoin('shipping', 's', '=', 'o.id')
    ->where('o.total', '>', 100)
    ->orderBy('o.total', 'DESC')
    ->limit(50);

echo "SQL: " . $qb3->buildSQL() . "\n";

echo "\n--- Query Builder: GROUP BY + HAVING ---\n";
$qb4 = (new QueryBuilder())
    ->from('orders', 'o')
    ->selectRaw('o.customer_id', 'cust_id')
    ->selectRaw('COUNT(*)', 'order_count')
    ->selectRaw('SUM(o.total)', 'total_spent')
    ->groupBy('o.customer_id')
    ->having('total_spent', '>', 1000)
    ->orderBy('total_spent', 'DESC');

echo "SQL: " . $qb4->buildSQL() . "\n";

echo "\n--- In-Memory Database ---\n";
$db = new InMemoryDatabase();
$db->insert('users', [
    ['id' => 1, 'name' => 'Alice', 'age' => 25, 'status' => 'active'],
    ['id' => 2, 'name' => 'Bob', 'age' => 17, 'status' => 'active'],
    ['id' => 3, 'name' => 'Charlie', 'age' => 30, 'status' => 'inactive'],
    ['id' => 4, 'name' => 'Diana', 'age' => 22, 'status' => 'active'],
    ['id' => 5, 'name' => 'Eve', 'age' => 35, 'status' => 'active'],
]);

$active = $db->select('users', ['id', 'name'], fn($u) => $u['status'] === 'active');
echo "Active users: " . json_encode($active) . "\n";

$adults = $db->select('users', ['name'], fn($u) => $u['age'] >= 18);
echo "Adults: " . implode(", ", array_column($adults, 'name')) . "\n";

echo "Total users: " . $db->count('users') . "\n";
echo "Avg age: " . round($db->aggregate('users', 'AVG', 'age'), 1) . "\n";
echo "Max age: " . $db->aggregate('users', 'MAX', 'age') . "\n";
echo "Min age: " . $db->aggregate('users', 'MIN', 'age') . "\n";
echo "Sum of ages: " . $db->aggregate('users', 'SUM', 'age') . "\n";

echo "\n--- JOIN Simulation ---\n";
$db->insert('orders', [
    ['order_id' => 101, 'user_id' => 1, 'total' => 150.00],
    ['order_id' => 102, 'user_id' => 2, 'total' => 75.50],
    ['order_id' => 103, 'user_id' => 1, 'total' => 200.00],
    ['order_id' => 104, 'user_id' => 3, 'total' => 50.00],
    ['order_id' => 105, 'user_id' => 5, 'total' => 300.00],
]);

$joined = $db->joinTables('orders', 'users', 'user_id', 'id', 'LEFT');
echo "Joined records: " . count($joined) . "\n";
foreach ($joined as $r) {
    echo "  Order #{$r['order_id']} by {$r['name']} - \${r['total']}\n";
}

echo "\n--- Aggregated Report ---\n";
$userTotals = [];
foreach ($db->select('orders') as $order) {
    $uid = $order['user_id'];
    if (!isset($userTotals[$uid])) $userTotals[$uid] = 0;
    $userTotals[$uid] += $order['total'];
}
arsort($userTotals);
foreach ($userTotals as $uid => $total) {
    $users = $db->select('users', ['name'], fn($u) => $u['id'] === $uid);
    $name = $users[0]['name'] ?? "Unknown";
    echo "  $name: \$$total\n";
}

echo "\n=== c036 Done ===\n";
