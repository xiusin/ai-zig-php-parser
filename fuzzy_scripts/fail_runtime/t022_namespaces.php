<?php
// 命名空间：命名空间内函数调用、常量访问、类引用

namespace App\Services;

const MAX_USERS = 100;
const VERSION = '2.0.0';

function format_name(string $name): string {
    return ucfirst(strtolower(trim($name)));
}

function create_user(string $name, int $age): array {
    return [
        'name' => format_name($name),
        'age' => $age,
        'id' => uniqid(),
    ];
}

class UserService {
    private array $users = [];

    public function add(string $name, int $age): array {
        $user = create_user($name, $age);
        $this->users[] = $user;
        return $user;
    }

    public function count(): int {
        return count($this->users);
    }

    public function find(string $name): ?array {
        foreach ($this->users as $user) {
            if ($user['name'] === $name) return $user;
        }
        return null;
    }

    public function all(): array {
        return $this->users;
    }
}

// 测试命名空间内函数调用
$service = new UserService();
$user1 = $service->add('  alice  ', 30);
$user2 = $service->add('BOB', 25);
$user3 = $service->add('Charlie', 35);

echo "user1: " . $user1['name'] . ", " . $user1['age'] . "\n";
echo "user2: " . $user2['name'] . ", " . $user2['age'] . "\n";
echo "user3: " . $user3['name'] . ", " . $user3['age'] . "\n";

// 测试 count（全局函数）
echo "user_count: " . $service->count() . "\n";

// 测试查找
$found = $service->find('Alice');
echo "found: " . ($found ? $found['name'] : 'null') . "\n";

$notFound = $service->find('NonExistent');
echo "not_found: " . ($notFound ? 'found' : 'null') . "\n";

// 测试常量
echo "max_users: " . MAX_USERS . "\n";
echo "version: " . VERSION . "\n";

// 测试格式化函数
echo "formatted: " . format_name('  john doe  ') . "\n";

// 测试数组操作
$all = $service->all();
echo "all_names: " . implode(', ', array_map(fn($u) => $u['name'], $all)) . "\n";
