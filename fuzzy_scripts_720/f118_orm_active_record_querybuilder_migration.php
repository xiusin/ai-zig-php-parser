<?php
// 极度混搭: ORM + ActiveRecord + 关系映射 + 查询构建器 + 迁移
echo "=== f118: ORM + ActiveRecord + QueryBuilder + Migration ===\n";

class Schema {
    private static array $tables = [];

    public static function createTable(string $name, array $columns): void {
        self::$tables[$name] = ['columns' => $columns, 'data' => [], 'pk' => 'id', 'autoIncrement' => 1];
    }

    public static function getTable(string $name): ?array { return self::$tables[$name] ?? null; }
    public static function getTables(): array { return array_keys(self::$tables); }
}

class QueryBuilder {
    private string $table = '';
    private array $wheres = [];
    private array $orders = [];
    private ?int $limit = null;
    private ?int $offset = null;
    private array $selects = ['*'];
    private array $joins = [];

    public function table(string $name): self { $this->table = $name; return $this; }
    public function select(...$cols): self { $this->selects = $cols; return $this; }

    public function where(string $col, string $op, mixed $val): self {
        $this->wheres[] = ['col' => $col, 'op' => $op, 'val' => $val];
        return $this;
    }

    public function whereIn(string $col, array $vals): self {
        $this->wheres[] = ['col' => $col, 'op' => 'IN', 'val' => $vals];
        return $this;
    }

    public function whereLike(string $col, string $pattern): self {
        $this->wheres[] = ['col' => $col, 'op' => 'LIKE', 'val' => $pattern];
        return $this;
    }

    public function orderBy(string $col, string $dir = 'ASC'): self { $this->orders[] = ['col' => $col, 'dir' => $dir]; return $this; }
    public function limit(int $n): self { $this->limit = $n; return $this; }
    public function offset(int $n): self { $this->offset = $n; return $this; }

    public function join(string $table, string $left, string $op, string $right): self {
        $this->joins[] = ['table' => $table, 'left' => $left, 'op' => $op, 'right' => $right];
        return $this;
    }

    public function get(): array {
        $tableData = Schema::getTable($this->table);
        if ($tableData === null) return [];
        $rows = $tableData['data'];

        // JOIN (简化: 只支持 inner join)
        foreach ($this->joins as $join) {
            $joinTable = Schema::getTable($join['table']);
            if ($joinTable === null) continue;
            $joined = [];
            foreach ($rows as $row) {
                foreach ($joinTable['data'] as $jRow) {
                    $leftVal = $row[$join['left']] ?? null;
                    $rightVal = $jRow[$join['right']] ?? null;
                    $match = match($join['op']) {
                        '=' => $leftVal === $rightVal,
                        '!=' => $leftVal !== $rightVal,
                        default => false,
                    };
                    if ($match) {
                        $merged = $row;
                        foreach ($jRow as $k => $v) $merged[$join['table'] . '_' . $k] = $v;
                        $joined[] = $merged;
                    }
                }
            }
            $rows = $joined;
        }

        // WHERE
        $rows = array_values(array_filter($rows, fn($row) => $this->matchWheres($row)));

        // ORDER BY
        if (!empty($this->orders)) {
            usort($rows, function($a, $b) {
                foreach ($this->orders as $order) {
                    $cmp = ($a[$order['col']] ?? null) <=> ($b[$order['col']] ?? null);
                    if ($cmp !== 0) return $order['dir'] === 'DESC' ? -$cmp : $cmp;
                }
                return 0;
            });
        }

        // OFFSET
        if ($this->offset !== null) $rows = array_slice($rows, $this->offset);
        // LIMIT
        if ($this->limit !== null) $rows = array_slice($rows, 0, $this->limit);

        // SELECT
        if ($this->selects !== ['*']) {
            $rows = array_map(function($row) {
                $filtered = [];
                foreach ($this->selects as $col) $filtered[$col] = $row[$col] ?? null;
                return $filtered;
            }, $rows);
        }

        return $rows;
    }

    private function matchWheres(array $row): bool {
        foreach ($this->wheres as $where) {
            $val = $row[$where['col']] ?? null;
            $match = match($where['op']) {
                '=' => $val === $where['val'],
                '!=' => $val !== $where['val'],
                '>' => $val > $where['val'],
                '<' => $val < $where['val'],
                '>=' => $val >= $where['val'],
                '<=' => $val <= $where['val'],
                'IN' => in_array($val, $where['val']),
                'LIKE' => fnmatch(str_replace('%', '*', $where['val']), (string)$val),
                default => false,
            };
            if (!$match) return false;
        }
        return true;
    }

    public function toSQL(): string {
        $sql = "SELECT " . implode(', ', $this->selects) . " FROM {$this->table}";
        foreach ($this->joins as $j) $sql .= " JOIN {$j['table']} ON {$j['left']} {$j['op']} {$j['right']}";
        if (!empty($this->wheres)) {
            $clauses = array_map(fn($w) => "{$w['col']} {$w['op']} " . (is_array($w['val']) ? '(' . implode(',', $w['val']) . ')' : (is_string($w['val']) ? "'{$w['val']}'" : $w['val'])), $this->wheres);
            $sql .= " WHERE " . implode(' AND ', $clauses);
        }
        if (!empty($this->orders)) {
            $sql .= " ORDER BY " . implode(', ', array_map(fn($o) => "{$o['col']} {$o['dir']}", $this->orders));
        }
        if ($this->limit !== null) $sql .= " LIMIT {$this->limit}";
        if ($this->offset !== null) $sql .= " OFFSET {$this->offset}";
        return $sql;
    }
}

class ActiveRecord {
    protected string $tableName = '';
    protected array $attributes = [];
    protected array $dirty = [];

    public function __construct(array $data = []) {
        $this->attributes = $data;
    }

    public function __get(string $name): mixed { return $this->attributes[$name] ?? null; }
    public function __set(string $name, mixed $value): void {
        $this->attributes[$name] = $value;
        $this->dirty[] = $name;
    }

    public static function query(): QueryBuilder {
        $instance = new static();
        return (new QueryBuilder())->table($instance->tableName);
    }

    public function save(): bool {
        $table = Schema::getTable($this->tableName);
        if ($table === null) return false;

        if (isset($this->attributes['id'])) {
            // Update
            foreach ($table['data'] as &$row) {
                if ($row['id'] === $this->attributes['id']) {
                    foreach ($this->dirty as $col) $row[$col] = $this->attributes[$col];
                    $this->dirty = [];
                    return true;
                }
            }
            return false;
        } else {
            // Insert
            $this->attributes['id'] = $table['autoIncrement']++;
            Schema::$tables[$this->tableName]['data'][] = $this->attributes;
            Schema::$tables[$this->tableName]['autoIncrement'] = $table['autoIncrement'];
            $this->dirty = [];
            return true;
        }
    }

    public function delete(): bool {
        $table = Schema::getTable($this->tableName);
        if ($table === null || !isset($this->attributes['id'])) return false;
        foreach ($table['data'] as $i => $row) {
            if ($row['id'] === $this->attributes['id']) {
                array_splice(Schema::$tables[$this->tableName]['data'], $i, 1);
                return true;
            }
        }
        return false;
    }

    public function toArray(): array { return $this->attributes; }
}

class User extends ActiveRecord {
    protected string $tableName = 'users';
}

class Post extends ActiveRecord {
    protected string $tableName = 'posts';
}

class Migration {
    public static function up(): void {
        Schema::createTable('users', ['id' => 'int', 'name' => 'string', 'email' => 'string', 'age' => 'int', 'role' => 'string']);
        Schema::createTable('posts', ['id' => 'int', 'user_id' => 'int', 'title' => 'string', 'content' => 'string', 'views' => 'int']);
    }
}

// 测试
echo "--- Run Migration ---\n";
Migration::up();
echo "Tables: " . implode(', ', Schema::getTables()) . "\n";

echo "\n--- Insert Users (ActiveRecord) ---\n";
$users = [
    ['name' => 'Alice', 'email' => 'alice@test.com', 'age' => 30, 'role' => 'admin'],
    ['name' => 'Bob', 'email' => 'bob@test.com', 'age' => 25, 'role' => 'user'],
    ['name' => 'Charlie', 'email' => 'charlie@test.com', 'age' => 35, 'role' => 'user'],
    ['name' => 'Dave', 'email' => 'dave@test.com', 'age' => 28, 'role' => 'editor'],
    ['name' => 'Eve', 'email' => 'eve@test.com', 'age' => 22, 'role' => 'user'],
];
foreach ($users as $data) {
    $user = new User($data);
    $user->save();
    echo "  Created user: {$user->name} (id={$user->id})\n";
}

echo "\n--- Insert Posts ---\n";
$posts = [
    ['user_id' => 1, 'title' => 'Hello World', 'content' => 'First post', 'views' => 100],
    ['user_id' => 1, 'title' => 'ORM Tips', 'content' => 'How to use ORM', 'views' => 250],
    ['user_id' => 2, 'title' => 'Bob Blog', 'content' => 'My journey', 'views' => 50],
    ['user_id' => 3, 'title' => 'Charlie Thoughts', 'content' => 'Deep thoughts', 'views' => 300],
    ['user_id' => 4, 'title' => 'Editor Guide', 'content' => 'Editing tips', 'views' => 75],
];
foreach ($posts as $data) {
    $post = new Post($data);
    $post->save();
}

echo "\n--- Query Builder: WHERE ---\n";
$admins = User::query()->where('role', '=', 'admin')->get();
echo "Admins: " . json_encode($admins) . "\n";

$young = User::query()->where('age', '<', 30)->orderBy('age', 'ASC')->get();
echo "Users under 30: ";
foreach ($young as $u) echo $u['name'] . "({$u['age']}) ";
echo "\n";

echo "\n--- Query Builder: WHERE IN ---\n";
$selected = User::query()->whereIn('id', [1, 3, 5])->get();
echo "Selected users: " . implode(', ', array_map(fn($u) => $u['name'], $selected)) . "\n";

echo "\n--- Query Builder: LIKE ---\n";
$matched = User::query()->whereLike('email', '%test%')->get();
echo "Emails matching '%test%': " . count($matched) . "\n";

echo "\n--- Query Builder: ORDER + LIMIT ---\n";
$topUsers = User::query()->orderBy('age', 'DESC')->limit(3)->get();
echo "Top 3 oldest: ";
foreach ($topUsers as $u) echo $u['name'] . "({$u['age']}) ";
echo "\n";

echo "\n--- Query Builder: JOIN ---\n";
$userPosts = (new QueryBuilder())->table('users')
    ->select('name', 'title', 'views')
    ->join('posts', 'id', '=', 'user_id')
    ->orderBy('views', 'DESC')
    ->get();
echo "User posts (by views):\n";
foreach ($userPosts as $up) echo "  {$up['name']}: \"{$up['title']}\" ({$up['views']} views)\n";

echo "\n--- SQL Generation ---\n";
$qb = User::query()->where('age', '>', 25)->where('role', '=', 'user')->orderBy('name')->limit(10);
echo "SQL: " . $qb->toSQL() . "\n";

echo "\n--- Update (ActiveRecord) ---\n";
$bob = User::query()->where('name', '=', 'Bob')->get()[0];
$bobModel = new User($bob);
$bobModel->age = 26;
$bobModel->role = 'editor';
$bobModel->save();
$updated = User::query()->where('name', '=', 'Bob')->get()[0];
echo "Bob after update: age={$updated['age']} role={$updated['role']}\n";

echo "\n--- Delete (ActiveRecord) ---\n";
$eve = User::query()->where('name', '=', 'Eve')->get()[0];
$eveModel = new User($eve);
$eveModel->delete();
$remaining = User::query()->get();
echo "After deleting Eve: " . count($remaining) . " users\n";
echo "Users: " . implode(', ', array_map(fn($u) => $u['name'], $remaining)) . "\n";

echo "=== f118 Done ===\n";
