<?php
// Test 021: PDO, database-like operations, and prepared statements simulation
class DatabaseLab {
    private array $tables = [];

    public function createTable(string $name, array $columns): void {
        $this->tables[$name] = [
            'columns' => $columns,
            'rows' => [],
        ];
    }

    public function insert(string $table, array $data): bool {
        if (!isset($this->tables[$table])) return false;
        $this->tables[$table]['rows'][] = $data;
        return true;
    }

    public function select(string $table, ?callable $where = null): array {
        if (!isset($this->tables[$table])) return [];
        $rows = $this->tables[$table]['rows'];
        if ($where) {
            $rows = array_filter($rows, $where);
        }
        return array_values($rows);
    }

    public function update(string $table, array $data, callable $where): int {
        if (!isset($this->tables[$table])) return 0;
        $count = 0;
        foreach ($this->tables[$table]['rows'] as &$row) {
            if ($where($row)) {
                $row = array_merge($row, $data);
                $count++;
            }
        }
        return $count;
    }

    public function delete(string $table, callable $where): int {
        if (!isset($this->tables[$table])) return 0;
        $initial = count($this->tables[$table]['rows']);
        $this->tables[$table]['rows'] = array_values(
            array_filter($this->tables[$table]['rows'], fn($row) => !$where($row))
        );
        return $initial - count($this->tables[$table]['rows']);
    }

    public function query(string $sql): array {
        $out = [];
        $out[] = "SQL: $sql";
        if (preg_match('/^SELECT.*FROM\s+(\w+)/i', $sql, $matches)) {
            $table = $matches[1];
            $out[] = "Parsed table: $table";
            if (isset($this->tables[$table])) {
                $out[] = "Found " . count($this->tables[$table]['rows']) . " rows";
            }
        }
        return $out;
    }
}

echo "=== Database Lab ===\n";
$db = new DatabaseLab();

// Create tables
$db->createTable('users', [
    'id' => 'INT AUTO_INCREMENT PRIMARY KEY',
    'name' => 'VARCHAR(255)',
    'email' => 'VARCHAR(255)',
    'active' => 'BOOLEAN',
]);

$db->createTable('posts', [
    'id' => 'INT AUTO_INCREMENT PRIMARY KEY',
    'user_id' => 'INT',
    'title' => 'VARCHAR(255)',
    'content' => 'TEXT',
]);

// Insert data
$db->insert('users', ['id' => 1, 'name' => 'Alice', 'email' => 'alice@example.com', 'active' => true]);
$db->insert('users', ['id' => 2, 'name' => 'Bob', 'email' => 'bob@example.com', 'active' => false]);
$db->insert('users', ['id' => 3, 'name' => 'Charlie', 'email' => 'charlie@example.com', 'active' => true]);

$db->insert('posts', ['id' => 1, 'user_id' => 1, 'title' => 'First Post', 'content' => 'Hello World']);
$db->insert('posts', ['id' => 2, 'user_id' => 1, 'title' => 'Second Post', 'content' => 'More content']);
$db->insert('posts', ['id' => 3, 'user_id' => 2, 'title' => 'Bob Post', 'content' => 'From Bob']);

// Select all users
$users = $db->select('users');
echo "All users: " . count($users) . " rows\n";

// Select active users
$activeUsers = $db->select('users', fn($u) => $u['active'] === true);
echo "Active users: " . count($activeUsers) . " rows\n";

// Update
$updated = $db->update('users', ['active' => false], fn($u) => $u['name'] === 'Charlie');
echo "Updated $updated rows\n";

// Delete
$deleted = $db->delete('posts', fn($p) => $p['user_id'] === 2);
echo "Deleted $deleted posts\n";

// Final state
$remaining = $db->select('posts');
echo "Remaining posts: " . count($remaining) . "\n";

echo "\n=== SQL Parsing ===\n";
$queries = [
    "SELECT * FROM users WHERE active = true",
    "SELECT id, name, email FROM users",
    "INSERT INTO posts (user_id, title) VALUES (1, 'New')",
    "UPDATE users SET active = false WHERE id = 1",
    "DELETE FROM users WHERE id = 3",
];

foreach ($queries as $sql) {
    $result = $db->query($sql);
    foreach ($result as $line) {
        echo "  $line\n";
    }
}