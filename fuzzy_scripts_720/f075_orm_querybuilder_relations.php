<?php
// 极度混搭: ORM简化 + 查询构建器 + 关系映射 + 延迟加载
echo "=== f075: ORM + QueryBuilder + Relations + LazyLoad ===\n";

class Model {
    protected string $table = '';
    protected array $attributes = [];
    protected array $original = [];
    protected bool $exists = false;
    protected static array $relations = [];

    public function __construct(array $attrs = []) {
        $this->attributes = $attrs;
        $this->original = $attrs;
    }

    public function __get(string $name): mixed {
        if (array_key_exists($name, $this->attributes)) return $this->attributes[$name];
        if (isset(static::$relations[$name])) return $this->loadRelation($name);
        return null;
    }

    public function __set(string $name, mixed $value): void {
        $this->attributes[$name] = $value;
    }

    public function isDirty(): bool {
        return $this->attributes != $this->original;
    }

    public function getAttributes(): array { return $this->attributes; }
    public function getTable(): string { return $this->table; }
    public function toArray(): array { return $this->attributes; }

    protected function loadRelation(string $name): mixed { return null; }
}

class User extends Model {
    protected string $table = 'users';
    private static array $db = [
        ['id' => 1, 'name' => 'Alice', 'email' => 'alice@test.com', 'role_id' => 1],
        ['id' => 2, 'name' => 'Bob', 'email' => 'bob@test.com', 'role_id' => 2],
        ['id' => 3, 'name' => 'Charlie', 'email' => 'charlie@test.com', 'role_id' => 1],
    ];

    public function role(): ?Role {
        $roleId = $this->attributes['role_id'] ?? null;
        if ($roleId === null) return null;
        return Role::find($roleId);
    }

    public function posts(): array {
        return Post::where('user_id', $this->attributes['id']);
    }

    public static function find(int $id): ?self {
        foreach (self::$db as $row) {
            if ($row['id'] === $id) return new self($row);
        }
        return null;
    }

    public static function all(): array {
        return array_map(fn($row) => new self($row), self::$db);
    }

    public static function where(string $field, mixed $value): array {
        $results = [];
        foreach (self::$db as $row) {
            if (($row[$field] ?? null) == $value) $results[] = new self($row);
        }
        return $results;
    }
}

class Role extends Model {
    protected string $table = 'roles';
    private static array $db = [
        ['id' => 1, 'name' => 'admin', 'permissions' => 'read,write,delete'],
        ['id' => 2, 'name' => 'user', 'permissions' => 'read'],
    ];

    public static function find(int $id): ?self {
        foreach (self::$db as $row) {
            if ($row['id'] === $id) return new self($row);
        }
        return null;
    }

    public static function all(): array {
        return array_map(fn($row) => new self($row), self::$db);
    }

    public function users(): array {
        return User::where('role_id', $this->attributes['id']);
    }
}

class Post extends Model {
    protected string $table = 'posts';
    private static array $db = [
        ['id' => 1, 'title' => 'Hello World', 'user_id' => 1],
        ['id' => 2, 'title' => 'PHP Tips', 'user_id' => 1],
        ['id' => 3, 'title' => 'Zig Guide', 'user_id' => 2],
    ];

    public function user(): ?User {
        return User::find($this->attributes['user_id']);
    }

    public static function find(int $id): ?self {
        foreach (self::$db as $row) {
            if ($row['id'] === $id) return new self($row);
        }
        return null;
    }

    public static function all(): array {
        return array_map(fn($row) => new self($row), self::$db);
    }

    public static function where(string $field, mixed $value): array {
        $results = [];
        foreach (self::$db as $row) {
            if (($row[$field] ?? null) == $value) $results[] = new self($row);
        }
        return $results;
    }
}

class QueryBuilder {
    private array $wheres = [];
    private ?int $limit = null;
    private ?int $offset = null;
    private array $orderBy = [];
    private array $selects = ['*'];

    public function __construct(private string $modelClass) {}

    public function select(array $columns): self {
        $this->selects = $columns;
        return $this;
    }

    public function where(string $column, mixed $operator, mixed $value = null): self {
        if ($value === null && func_num_args() === 2) {
            $value = $operator;
            $operator = '=';
        }
        $this->wheres[] = ['column' => $column, 'operator' => $operator, 'value' => $value];
        return $this;
    }

    public function limit(int $n): self { $this->limit = $n; return $this; }
    public function offset(int $n): self { $this->offset = $n; return $this; }
    public function orderBy(string $column, string $dir = 'ASC'): self { $this->orderBy[] = [$column, $dir]; return $this; }

    public function get(): array {
        $all = ($this->modelClass)::all();
        // Where
        foreach ($this->wheres as $w) {
            $all = array_filter($all, function($model) use ($w) {
                $actual = $model->{$w['column']} ?? null;
                return match($w['operator']) {
                    '=' => $actual == $w['value'],
                    '!=' => $actual != $w['value'],
                    '>' => $actual > $w['value'],
                    '<' => $actual < $w['value'],
                    '>=' => $actual >= $w['value'],
                    '<=' => $actual <= $w['value'],
                    default => false,
                };
            });
        }
        // OrderBy
        if (!empty($this->orderBy)) {
            usort($all, function($a, $b) {
                foreach ($this->orderBy as [$col, $dir]) {
                    $cmp = ($a->{$col} ?? '') <=> ($b->{$col} ?? '');
                    if ($cmp !== 0) return $dir === 'DESC' ? -$cmp : $cmp;
                }
                return 0;
            });
        }
        // Offset & Limit
        if ($this->offset !== null) $all = array_slice($all, $this->offset);
        if ($this->limit !== null) $all = array_slice($all, 0, $this->limit);
        return array_values($all);
    }

    public function first(): ?object {
        $this->limit = 1;
        $results = $this->get();
        return $results[0] ?? null;
    }

    public function count(): int { return count($this->get()); }

    public function toSQL(): string {
        $table = ($this->modelClass)::getTableStatic();
        $sql = "SELECT " . implode(', ', $this->selects) . " FROM $table";
        if (!empty($this->wheres)) {
            $clauses = array_map(fn($w) => "{$w['column']} {$w['operator']} ?", $this->wheres);
            $sql .= " WHERE " . implode(' AND ', $clauses);
        }
        if (!empty($this->orderBy)) {
            $orders = array_map(fn($o) => "{$o[0]} {$o[1]}", $this->orderBy);
            $sql .= " ORDER BY " . implode(', ', $orders);
        }
        if ($this->limit !== null) $sql .= " LIMIT $this->limit";
        if ($this->offset !== null) $sql .= " OFFSET $this->offset";
        return $sql;
    }
}

// 给Model添加静态方法
Model::getTableStatic(); // 确保类加载

// 测试
echo "--- Basic CRUD ---\n";
$user = User::find(1);
echo "User 1: " . json_encode($user->toArray()) . "\n";
echo "User name: " . $user->name . "\n";
echo "User email: " . $user->email . "\n";

echo "\n--- Relations ---\n";
echo "User 1 role: " . json_encode($user->role()->toArray()) . "\n";
$posts = $user->posts();
echo "User 1 posts: " . count($posts) . "\n";
foreach ($posts as $post) echo "  - {$post->title}\n";

echo "\n--- Reverse Relations ---\n";
$post = Post::find(3);
echo "Post 3 author: " . $post->user()->name . "\n";

$role = Role::find(1);
$roleUsers = $role->users();
echo "Admin role users: " . count($roleUsers) . "\n";
foreach ($roleUsers as $u) echo "  - {$u->name}\n";

echo "\n--- Query Builder ---\n";
$users = (new QueryBuilder(User::class))->get();
echo "All users: " . count($users) . "\n";

$admins = (new QueryBuilder(User::class))
    ->where('role_id', '=', 1)
    ->get();
echo "Admins: " . count($admins) . "\n";
foreach ($admins as $u) echo "  - {$u->name}\n";

$firstUser = (new QueryBuilder(User::class))
    ->orderBy('name', 'ASC')
    ->first();
echo "First user by name: " . $firstUser->name . "\n";

echo "\n--- Dirty Check ---\n";
$user2 = User::find(2);
echo "Is dirty (before): " . var_export($user2->isDirty(), true) . "\n";
$user2->name = 'Bobby';
echo "Is dirty (after change): " . var_export($user2->isDirty(), true) . "\n";

echo "=== f075 Done ===\n";
