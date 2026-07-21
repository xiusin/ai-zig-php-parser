<?php
// 极度混搭: 查询构建器 + 链式SQL + 条件组合 + 排序分组 + 参数绑定
echo "=== f053: Query Builder + SQL + Conditions ===\n";

class QueryBuilder {
    private string $table = '';
    private array $select = ['*'];
    private array $wheres = [];
    private array $orders = [];
    private array $groups = [];
    private ?int $limit = null;
    private ?int $offset = null;
    private array $joins = [];
    private array $params = [];
    private array $havings = [];

    public function from(string $table): self { $this->table = $table; return $this; }
    public function table(string $table): self { return $this->from($table); }

    public function select(string ...$cols): self { $this->select = $cols; return $this; }

    public function where(string $col, string $op, mixed $val): self {
        $this->wheres[] = ['type' => 'basic', 'connector' => 'AND', 'col' => $col, 'op' => $op, 'val' => $val];
        return $this;
    }

    public function orWhere(string $col, string $op, mixed $val): self {
        $this->wheres[] = ['type' => 'basic', 'connector' => 'OR', 'col' => $col, 'op' => $op, 'val' => $val];
        return $this;
    }

    public function whereIn(string $col, array $vals): self {
        $this->wheres[] = ['type' => 'in', 'connector' => 'AND', 'col' => $col, 'vals' => $vals];
        return $this;
    }

    public function whereNull(string $col): self {
        $this->wheres[] = ['type' => 'null', 'connector' => 'AND', 'col' => $col];
        return $this;
    }

    public function whereNotNull(string $col): self {
        $this->wheres[] = ['type' => 'not_null', 'connector' => 'AND', 'col' => $col];
        return $this;
    }

    public function whereBetween(string $col, mixed $min, mixed $max): self {
        $this->wheres[] = ['type' => 'between', 'connector' => 'AND', 'col' => $col, 'min' => $min, 'max' => $max];
        return $this;
    }

    public function whereLike(string $col, string $pattern): self {
        $this->wheres[] = ['type' => 'like', 'connector' => 'AND', 'col' => $col, 'pattern' => $pattern];
        return $this;
    }

    public function join(string $table, string $left, string $op, string $right): self {
        $this->joins[] = ['type' => 'INNER', 'table' => $table, 'left' => $left, 'op' => $op, 'right' => $right];
        return $this;
    }

    public function leftJoin(string $table, string $left, string $op, string $right): self {
        $this->joins[] = ['type' => 'LEFT', 'table' => $table, 'left' => $left, 'op' => $op, 'right' => $right];
        return $this;
    }

    public function orderBy(string $col, string $dir = 'ASC'): self {
        $this->orders[] = "$col $dir";
        return $this;
    }

    public function groupBy(string ...$cols): self {
        $this->groups = array_merge($this->groups, $cols);
        return $this;
    }

    public function having(string $col, string $op, mixed $val): self {
        $this->havings[] = "$col $op ?";
        $this->params[] = $val;
        return $this;
    }

    public function limit(int $n): self { $this->limit = $n; return $this; }
    public function offset(int $n): self { $this->offset = $n; return $this; }

    public function toSQL(): string {
        $this->params = [];
        $sql = "SELECT " . implode(', ', $this->select);

        if ($this->table) $sql .= " FROM {$this->table}";

        foreach ($this->joins as $join) {
            $sql .= " {$join['type']} JOIN {$join['table']} ON {$join['left']} {$join['op']} {$join['right']}";
        }

        if (!empty($this->wheres)) {
            $whereParts = [];
            foreach ($this->wheres as $i => $w) {
                $connector = $i === 0 ? '' : " {$w['connector']} ";
                $part = match($w['type']) {
                    'basic' => "{$w['col']} {$w['op']} ?",
                    'in' => "{$w['col']} IN (" . implode(', ', array_fill(0, count($w['vals']), '?')) . ")",
                    'null' => "{$w['col']} IS NULL",
                    'not_null' => "{$w['col']} IS NOT NULL",
                    'between' => "{$w['col']} BETWEEN ? AND ?",
                    'like' => "{$w['col']} LIKE ?",
                };
                $whereParts[] = $connector . $part;

                match($w['type']) {
                    'basic' => $this->params[] = $w['val'],
                    'in' => foreach ($w['vals'] as $v) $this->params[] = $v,
                    'between' => $this->params[] = $w['min'],
                    'like' => $this->params[] = $w['pattern'],
                    default => null,
                };
            }
            $sql .= " WHERE " . implode('', $whereParts);
        }

        if (!empty($this->groups)) {
            $sql .= " GROUP BY " . implode(', ', $this->groups);
        }

        if (!empty($this->havings)) {
            $sql .= " HAVING " . implode(' AND ', $this->havings);
        }

        if (!empty($this->orders)) {
            $sql .= " ORDER BY " . implode(', ', $this->orders);
        }

        if ($this->limit !== null) $sql .= " LIMIT {$this->limit}";
        if ($this->offset !== null) $sql .= " OFFSET {$this->offset}";

        return $sql;
    }

    public function getParams(): array { return $this->params; }
}

// 测试
echo "--- Simple Select ---\n";
$q1 = (new QueryBuilder())->from('users')->select('id', 'name', 'email')->toSQL();
echo "SQL: $q1\n";

echo "\n--- Where Conditions ---\n";
$q2 = (new QueryBuilder())
    ->table('users')
    ->select('*')
    ->where('age', '>', 18)
    ->where('status', '=', 'active')
    ->toSQL();
echo "SQL: $q2\n";
echo "Params: " . json_encode((new QueryBuilder())->table('users')->where('age', '>', 18)->where('status', '=', 'active')->getParams()) . "\n";

echo "\n--- OR / IN / Between / Like ---\n";
$q3 = (new QueryBuilder())
    ->table('products')
    ->select('id', 'name', 'price')
    ->where('price', '>', 0)
    ->orWhere('category', '=', 'featured')
    ->whereIn('id', [1, 2, 3, 4, 5])
    ->whereBetween('price', 10, 100)
    ->whereLike('name', '%phone%')
    ->toSQL();
echo "SQL: $q3\n";

echo "\n--- Join ---\n";
$q4 = (new QueryBuilder())
    ->table('orders')
    ->select('orders.id', 'users.name', 'orders.total')
    ->join('users', 'orders.user_id', '=', 'users.id')
    ->leftJoin('products', 'orders.product_id', '=', 'products.id')
    ->where('orders.status', '=', 'completed')
    ->toSQL();
echo "SQL: $q4\n";

echo "\n--- Group By + Having + Order + Limit ---\n";
$q5 = (new QueryBuilder())
    ->table('orders')
    ->select('user_id', 'COUNT(*) as order_count', 'SUM(total) as total_spent')
    ->where('status', '=', 'completed')
    ->groupBy('user_id')
    ->having('order_count', '>', 5)
    ->orderBy('total_spent', 'DESC')
    ->limit(10)
    ->offset(20)
    ->toSQL();
echo "SQL: $q5\n";

echo "\n--- Complex ---\n";
$q6 = (new QueryBuilder())
    ->table('posts')
    ->select('posts.id', 'posts.title', 'users.name as author', 'COUNT(comments.id) as comment_count')
    ->join('users', 'posts.user_id', '=', 'users.id')
    ->leftJoin('comments', 'posts.id', '=', 'comments.post_id')
    ->where('posts.published', '=', 1)
    ->whereNull('posts.deleted_at')
    ->groupBy('posts.id')
    ->having('comment_count', '>=', 10)
    ->orderBy('posts.created_at', 'DESC')
    ->limit(5)
    ->toSQL();
echo "SQL: $q6\n";

echo "=== f053 Done ===\n";
