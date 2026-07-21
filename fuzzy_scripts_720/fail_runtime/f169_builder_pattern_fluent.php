<?php
// 建造者模式：流式接口、复杂对象构建、分步配置
echo "=== f169: Builder Pattern + Fluent Interface ===\n";

// SQL 查询构建器
class QueryBuilder {
    private string $table = '';
    private array $columns = ['*'];
    private array $wheres = [];
    private array $orders = [];
    private ?int $limitVal = null;
    private ?int $offsetVal = null;
    private array $joins = [];
    private array $groups = [];
    private ?string $having = null;

    public function table(string $name): self { $this->table = $name; return $this; }
    public function select(string ...$cols): self { $this->columns = $cols; return $this; }
    public function where(string $col, string $op, mixed $val): self { $this->wheres[] = "$col $op " . $this->formatVal($val); return $this; }
    public function whereIn(string $col, array $vals): self { $this->wheres[] = "$col IN (" . implode(', ', array_map(fn($v) => $this->formatVal($v), $vals)) . ")"; return $this; }
    public function whereNull(string $col): self { $this->wheres[] = "$col IS NULL"; return $this; }
    public function whereNotNull(string $col): self { $this->wheres[] = "$col IS NOT NULL"; return $this; }
    public function join(string $table, string $left, string $op, string $right): self { $this->joins[] = "JOIN $table ON $left $op $right"; return $this; }
    public function leftJoin(string $table, string $left, string $op, string $right): self { $this->joins[] = "LEFT JOIN $table ON $left $op $right"; return $this; }
    public function orderBy(string $col, string $dir = 'ASC'): self { $this->orders[] = "$col $dir"; return $this; }
    public function groupBy(string ...$cols): self { $this->groups = $cols; return $this; }
    public function having(string $cond): self { $this->having = $cond; return $this; }
    public function limit(int $n): self { $this->limitVal = $n; return $this; }
    public function offset(int $n): self { $this->offsetVal = $n; return $this; }

    public function toSQL(): string {
        $sql = "SELECT " . implode(', ', $this->columns) . " FROM {$this->table}";
        if (!empty($this->joins)) $sql .= ' ' . implode(' ', $this->joins);
        if (!empty($this->wheres)) $sql .= " WHERE " . implode(' AND ', $this->wheres);
        if (!empty($this->groups)) $sql .= " GROUP BY " . implode(', ', $this->groups);
        if ($this->having) $sql .= " HAVING $this->having";
        if (!empty($this->orders)) $sql .= " ORDER BY " . implode(', ', $this->orders);
        if ($this->limitVal !== null) $sql .= " LIMIT $this->limitVal";
        if ($this->offsetVal !== null) $sql .= " OFFSET $this->offsetVal";
        return $sql;
    }

    private function formatVal(mixed $v): string {
        if (is_string($v)) return "'$v'";
        if (is_bool($v)) return $v ? 'TRUE' : 'FALSE';
        if ($v === null) return 'NULL';
        return (string)$v;
    }
}

// HTML 构建器
class HtmlBuilder {
    private string $html = '';

    public function html(string $lang = 'en'): self { $this->html = "<!DOCTYPE html>\n<html lang=\"$lang\">"; return $this; }
    public function head(string $title, array $meta = []): self {
        $this->html .= "\n<head>\n<title>$title</title>";
        foreach ($meta as $name => $content) {
            $this->html .= "\n<meta name=\"$name\" content=\"$content\">";
        }
        $this->html .= "\n</head>";
        return $this;
    }
    public function body(): self { $this->html .= "\n<body>"; return $this; }
    public function div(string $class = '', string $content = ''): self {
        $cls = $class ? " class=\"$class\"" : '';
        $this->html .= "\n<div$cls>$content</div>";
        return $this;
    }
    public function h1(string $text, string $class = ''): self { return $this->heading(1, $text, $class); }
    public function h2(string $text, string $class = ''): self { return $this->heading(2, $text, $class); }
    public function h3(string $text, string $class = ''): self { return $this->heading(3, $text, $class); }
    private function heading(int $level, string $text, string $class): self {
        $cls = $class ? " class=\"$class\"" : '';
        $this->html .= "\n<h$level$cls>$text</h$level>";
        return $this;
    }
    public function p(string $text, string $class = ''): self {
        $cls = $class ? " class=\"$class\"" : '';
        $this->html .= "\n<p$cls>$text</p>";
        return $this;
    }
    public function ul(array $items, string $class = ''): self {
        $cls = $class ? " class=\"$class\"" : '';
        $this->html .= "\n<ul$cls>";
        foreach ($items as $item) $this->html .= "\n  <li>$item</li>";
        $this->html .= "\n</ul>";
        return $this;
    }
    public function table(array $headers, array $rows, string $class = ''): self {
        $cls = $class ? " class=\"$class\"" : '';
        $this->html .= "\n<table$cls>\n  <tr>";
        foreach ($headers as $h) $this->html .= "<th>$h</th>";
        $this->html .= "</tr>";
        foreach ($rows as $row) {
            $this->html .= "\n  <tr>";
            foreach ($row as $cell) $this->html .= "<td>$cell</td>";
            $this->html .= "</tr>";
        }
        $this->html .= "\n</table>";
        return $this;
    }
    public function link(string $href, string $rel = 'stylesheet'): self {
        $this->html .= "\n<link rel=\"$rel\" href=\"$href\">";
        return $this;
    }
    public function script(string $src): self {
        $this->html .= "\n<script src=\"$src\"></script>";
        return $this;
    }
    public function endBody(): self { $this->html .= "\n</body>"; return $this; }
    public function endHtml(): self { $this->html .= "\n</html>"; return $this; }
    public function build(): string { return $this->html . "\n"; }
    public function raw(string $html): self { $this->html .= $html; return $this; }
}

// 配置构建器
class ConfigBuilder {
    private array $config = [];

    public function set(string $key, mixed $value): self {
        $parts = explode('.', $key);
        $current = &$this->config;
        foreach ($parts as $i => $part) {
            if ($i === count($parts) - 1) {
                $current[$part] = $value;
            } else {
                if (!isset($current[$part]) || !is_array($current[$part])) {
                    $current[$part] = [];
                }
                $current = &$current[$part];
            }
        }
        return $this;
    }

    public function database(string $host, string $name, string $user, string $pass, int $port = 3306): self {
        return $this->set('database.host', $host)
            ->set('database.name', $name)
            ->set('database.user', $user)
            ->set('database.password', $pass)
            ->set('database.port', $port);
    }

    public function cache(string $driver = 'file', int $ttl = 3600): self {
        return $this->set('cache.driver', $driver)->set('cache.ttl', $ttl);
    }

    public function debug(bool $enabled = true): self {
        return $this->set('app.debug', $enabled);
    }

    public function build(): array { return $this->config; }
}

// 测试
echo "--- SQL Query Builder ---\n";
$sql1 = (new QueryBuilder())
    ->table('users')
    ->select('id', 'name', 'email')
    ->where('age', '>', 18)
    ->where('status', '=', 'active')
    ->orderBy('name', 'ASC')
    ->limit(10)
    ->toSQL();
echo "  $sql1\n";

$sql2 = (new QueryBuilder())
    ->table('orders')
    ->select('orders.id', 'users.name', 'products.title', 'orders.total')
    ->join('users', 'orders.user_id', '=', 'users.id')
    ->join('products', 'orders.product_id', '=', 'products.id')
    ->whereIn('orders.status', ['completed', 'shipped'])
    ->groupBy('users.id')
    ->having('COUNT(*) > 1')
    ->orderBy('orders.total', 'DESC')
    ->limit(5)
    ->offset(10)
    ->toSQL();
echo "  $sql2\n";

$sql3 = (new QueryBuilder())
    ->table('articles')
    ->select('id', 'title', 'author_id')
    ->whereNull('published_at')
    ->orderBy('created_at', 'DESC')
    ->toSQL();
echo "  $sql3\n";

echo "\n--- HTML Builder ---\n";
$html = (new HtmlBuilder())
    ->html('en')
    ->head('My Page', ['description' => 'Test page', 'author' => 'AOT'])
    ->link('/css/style.css')
    ->body()
    ->div('container', '')
    ->h1('Welcome', 'title')
    ->p('This is a test page built with fluent HTML builder.', 'lead')
    ->h2('Features')
    ->ul(['Fast compilation', 'Type safety', 'No runtime overhead'], 'feature-list')
    ->h3('User Table')
    ->table(['ID', 'Name', 'Email'], [
        ['1', 'Alice', 'alice@test.com'],
        ['2', 'Bob', 'bob@test.com'],
        ['3', 'Charlie', 'charlie@test.com'],
    ], 'data-table')
    ->script('/js/app.js')
    ->endBody()
    ->endHtml()
    ->build();
echo $html;

echo "\n--- Config Builder ---\n";
$config = (new ConfigBuilder())
    ->set('app.name', 'MyApp')
    ->set('app.version', '1.0.0')
    ->debug(true)
    ->database('localhost', 'mydb', 'root', 'secret', 3306)
    ->cache('redis', 7200)
    ->set('log.level', 'debug')
    ->set('log.path', '/var/log/myapp')
    ->build();
echo json_encode($config, JSON_PRETTY_PRINT) . "\n";

echo "=== f169 Done ===\n";
