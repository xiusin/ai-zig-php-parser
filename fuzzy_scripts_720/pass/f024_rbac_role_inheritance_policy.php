<?php
// 极度混搭: RBAC权限系统 + 角色继承 + 资源策略 + 权限检查缓存
echo "=== f024: RBAC + Role Inheritance + Policy ===\n";

class Permission {
    public function __construct(
        public string $resource,
        public string $action,
        public bool $allowed = true
    ) {}

    public function __toString(): string {
        $prefix = $this->allowed ? '' : '!';
        return "$prefix{$this->resource}:{$this->action}";
    }

    public function matches(string $resource, string $action): bool {
        $resMatch = $this->resource === '*' || $this->resource === $resource;
        $actMatch = $this->action === '*' || $this->action === $action;
        return $resMatch && $actMatch;
    }
}

class Role {
    private array $permissions = [];
    private array $parentRoles = [];

    public function __construct(public string $name) {}

    public function grant(string $resource, string $action): self {
        $this->permissions[] = new Permission($resource, $action, true);
        return $this;
    }

    public function deny(string $resource, string $action): self {
        $this->permissions[] = new Permission($resource, $action, false);
        return $this;
    }

    public function inheritsFrom(Role $parent): self {
        $this->parentRoles[] = $parent;
        return $this;
    }

    public function getPermissions(): array { return $this->permissions; }
    public function getParents(): array { return $this->parentRoles; }

    public function check(string $resource, string $action): ?bool {
        // 先检查自己的权限（后面的覆盖前面的）
        $result = null;
        foreach ($this->permissions as $perm) {
            if ($perm->matches($resource, $action)) {
                $result = $perm->allowed;
            }
        }
        // 检查父角色
        foreach ($this->parentRoles as $parent) {
            $parentResult = $parent->check($resource, $action);
            if ($parentResult !== null && $result === null) {
                $result = $parentResult;
            }
        }
        return $result;
    }
}

class User {
    private array $roles = [];

    public function __construct(public string $name, public int $id) {}

    public function assignRole(Role $role): self {
        $this->roles[] = $role;
        return $this;
    }

    public function getRoles(): array { return $this->roles; }

    public function can(string $resource, string $action): bool {
        foreach ($this->roles as $role) {
            $result = $role->check($resource, $action);
            if ($result === true) return true;
        }
        // 检查是否有显式拒绝
        foreach ($this->roles as $role) {
            $result = $role->check($resource, $action);
            if ($result === false) return false;
        }
        return false;
    }
}

class RBACManager {
    private array $roles = [];
    private array $users = [];
    private array $cache = [];

    public function addRole(Role $role): self {
        $this->roles[$role->name] = $role;
        return $this;
    }

    public function getRole(string $name): ?Role {
        return $this->roles[$name] ?? null;
    }

    public function addUser(User $user): self {
        $this->users[$user->id] = $user;
        return $this;
    }

    public function getUser(int $id): ?User {
        return $this->users[$id] ?? null;
    }

    public function check(int $userId, string $resource, string $action): bool {
        $cacheKey = "$userId:$resource:$action";
        if (isset($this->cache[$cacheKey])) return $this->cache[$cacheKey];

        $user = $this->getUser($userId);
        if ($user === null) return false;

        $result = $user->can($resource, $action);
        $this->cache[$cacheKey] = $result;
        return $result;
    }

    public function getCacheStats(): array {
        return ['entries' => count($this->cache), 'allowed' => count(array_filter($this->cache))];
    }
}

// === 测试 ===
$rbac = new RBACManager();

// 定义角色层级
$adminRole = (new Role('admin'))
    ->grant('*', '*'); // 管理员拥有所有权限

$editorRole = (new Role('editor'))
    ->grant('article', 'read')
    ->grant('article', 'write')
    ->grant('article', 'edit')
    ->grant('comment', 'read')
    ->grant('comment', 'write')
    ->grant('comment', 'delete')
    ->deny('article', 'delete'); // 编辑不能删除文章

$authorRole = (new Role('author'))
    ->grant('article', 'read')
    ->grant('article', 'write')
    ->grant('comment', 'read')
    ->grant('comment', 'write')
    ->inheritsFrom($editorRole); // 作者继承编辑的部分权限... 等等这个反了

// 修正：编辑继承作者的权限
$editorRole2 = (new Role('editor2'))
    ->grant('article', 'edit')
    ->grant('comment', 'delete')
    ->deny('article', 'delete')
    ->inheritsFrom($authorRole);

$readerRole = (new Role('reader'))
    ->grant('article', 'read')
    ->grant('comment', 'read');

$rbac->addRole($adminRole)->addRole($editorRole)->addRole($authorRole)->addRole($editorRole2)->addRole($readerRole);

// 创建用户
$alice = (new User('Alice', 1))->assignRole($adminRole);
$bob = (new User('Bob', 2))->assignRole($editorRole);
$charlie = (new User('Charlie', 3))->assignRole($authorRole);
$dave = (new User('Dave', 4))->assignRole($readerRole);
$eve = (new User('Eve', 5))->assignRole($editorRole2);

$rbac->addUser($alice)->addUser($bob)->addUser($charlie)->addUser($dave)->addUser($eve);

// 权限检查矩阵
echo "--- Permission Matrix ---\n";
$resources = ['article', 'comment', 'user', 'system'];
$actions = ['read', 'write', 'edit', 'delete'];
$users = [
    [1, 'Alice (admin)'],
    [2, 'Bob (editor)'],
    [3, 'Charlie (author)'],
    [4, 'Dave (reader)'],
    [5, 'Eve (editor2)'],
];

printf("%-20s", "");
foreach ($actions as $act) printf("%-8s", $act);
echo "\n";

foreach ($users as [$uid, $uname]) {
    foreach ($resources as $res) {
        printf("%-20s", "$uname/$res:");
        foreach ($actions as $act) {
            $allowed = $rbac->check($uid, $res, $act);
            printf("%-8s", $allowed ? 'YES' : 'no');
        }
        echo "\n";
    }
}

echo "\n--- Specific Checks ---\n";
echo "Alice can delete article: " . var_export($rbac->check(1, 'article', 'delete'), true) . "\n";
echo "Bob can delete article: " . var_export($rbac->check(2, 'article', 'delete'), true) . "\n";
echo "Bob can edit article: " . var_export($rbac->check(2, 'article', 'edit'), true) . "\n";
echo "Charlie can write article: " . var_export($rbac->check(3, 'article', 'write'), true) . "\n";
echo "Dave can read article: " . var_export($rbac->check(4, 'article', 'read'), true) . "\n";
echo "Dave can write article: " . var_export($rbac->check(4, 'article', 'write'), true) . "\n";
echo "Eve can write article (inherited): " . var_export($rbac->check(5, 'article', 'write'), true) . "\n";
echo "Eve can delete article (denied): " . var_export($rbac->check(5, 'article', 'delete'), true) . "\n";

echo "\nCache stats: " . json_encode($rbac->getCacheStats()) . "\n";

echo "=== f024 Done ===\n";
