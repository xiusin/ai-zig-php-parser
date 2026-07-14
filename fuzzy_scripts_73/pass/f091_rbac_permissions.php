<?php
// RBAC 权限控制系统
echo "=== RBAC Permission System ===\n\n";

class Permission {
    public function __construct(
        public readonly string $resource,
        public readonly string $action
    ) {}

    public function matches(string $resource, string $action): bool {
        $resMatch = $this->resource === '*' || $this->resource === $resource;
        $actMatch = $this->action === '*' || $this->action === $action;
        return $resMatch && $actMatch;
    }

    public function __toString(): string { return "$this->resource:$this->action"; }
}

class Role {
    private array $permissions = [];
    private array $childRoles = [];

    public function __construct(public readonly string $name) {}

    public function addPermission(string $resource, string $action): self {
        $this->permissions[] = new Permission($resource, $action);
        return $this;
    }

    public function addChildRole(Role $role): self {
        $this->childRoles[] = $role;
        return $this;
    }

    public function getPermissions(): array { return $this->permissions; }
    public function getChildRoles(): array { return $this->childRoles; }

    public function can(string $resource, string $action): bool {
        foreach ($this->permissions as $perm) {
            if ($perm->matches($resource, $action)) return true;
        }
        foreach ($this->childRoles as $child) {
            if ($child->can($resource, $action)) return true;
        }
        return false;
    }

    public function getAllPermissions(): array {
        $all = [...$this->permissions];
        foreach ($this->childRoles as $child) {
            $all = [...$all, ...$child->getAllPermissions()];
        }
        return $all;
    }
}

class User3 {
    private array $roles = [];

    public function __construct(public readonly string $id, public readonly string $name) {}

    public function assignRole(Role $role): self {
        $this->roles[$role->name] = $role;
        return $this;
    }

    public function revokeRole(string $roleName): bool {
        if (!isset($this->roles[$roleName])) return false;
        unset($this->roles[$roleName]);
        return true;
    }

    public function can(string $resource, string $action): bool {
        foreach ($this->roles as $role) {
            if ($role->can($resource, $action)) return true;
        }
        return false;
    }

    public function getRoles(): array { return array_keys($this->roles); }
    public function hasRole(string $roleName): bool { return isset($this->roles[$roleName]); }
}

class RBACManager {
    private array $roles = [];
    private array $users = [];
    private array $auditLog = [];

    public function createRole(string $name): Role {
        $role = new Role($name);
        $this->roles[$name] = $role;
        return $role;
    }

    public function getRole(string $name): ?Role { return $this->roles[$name] ?? null; }

    public function createUser(string $id, string $name): User3 {
        $user = new User3($id, $name);
        $this->users[$id] = $user;
        return $user;
    }

    public function getUser(string $id): ?User3 { return $this->users[$id] ?? null; }

    public function checkAccess(string $userId, string $resource, string $action): bool {
        $user = $this->getUser($userId);
        if ($user === null) return false;
        $allowed = $user->can($resource, $action);
        $this->auditLog[] = [
            'user' => $userId,
            'resource' => $resource,
            'action' => $action,
            'allowed' => $allowed,
            'timestamp' => time(),
        ];
        return $allowed;
    }

    public function getAuditLog(): array { return $this->auditLog; }
    public function getRoleCount(): int { return count($this->roles); }
    public function getUserCount(): int { return count($this->users); }
}

// === 测试 ===
$rbac = new RBACManager();

// 创建角色层级
$admin = $rbac->createRole('admin');
$admin->addPermission('*', '*');  // 管理员有所有权限

$editor = $rbac->createRole('editor');
$editor->addPermission('article', 'read');
$editor->addPermission('article', 'write');
$editor->addPermission('article', 'edit');
$editor->addPermission('comment', 'read');
$editor->addPermission('comment', 'write');
$editor->addPermission('comment', 'delete');

$author = $rbac->createRole('author');
$author->addPermission('article', 'read');
$author->addPermission('article', 'write');
$author->addPermission('comment', 'read');
$author->addPermission('comment', 'write');
$author->addChildRole($editor);  // author 继承 editor 的权限

$viewer = $rbac->createRole('viewer');
$viewer->addPermission('article', 'read');
$viewer->addPermission('comment', 'read');

// 创建用户
$alice = $rbac->createUser('U001', 'Alice');
$alice->assignRole($admin);

$bob = $rbac->createUser('U002', 'Bob');
$bob->assignRole($editor);

$charlie = $rbac->createUser('U003', 'Charlie');
$charlie->assignRole($author);

$diana = $rbac->createUser('U004', 'Diana');
$diana->assignRole($viewer);

$eve = $rbac->createUser('U005', 'Eve');
$eve->assignRole($viewer)->assignRole($editor);  // 多角色

echo "--- Role Hierarchy ---\n";
echo "Roles: " . $rbac->getRoleCount() . "\n";
echo "  admin: " . implode(', ', array_map(fn($p) => (string)$p, $admin->getPermissions())) . "\n";
echo "  editor: " . implode(', ', array_map(fn($p) => (string)$p, $editor->getPermissions())) . "\n";
echo "  author: " . implode(', ', array_map(fn($p) => (string)$p, $author->getPermissions())) . " (+ inherits editor)\n";
echo "  viewer: " . implode(', ', array_map(fn($p) => (string)$p, $viewer->getPermissions())) . "\n";

echo "\n--- Access Control Tests ---\n";
$tests = [
    ['U001', 'article', 'delete', true],   // admin can do anything
    ['U001', 'settings', 'change', true],  // admin wildcard
    ['U002', 'article', 'read', true],     // editor can read
    ['U002', 'article', 'delete', false],  // editor cannot delete articles
    ['U003', 'article', 'edit', true],     // author inherits editor's edit permission
    ['U003', 'article', 'delete', false],  // author cannot delete
    ['U004', 'article', 'read', true],     // viewer can read
    ['U004', 'article', 'write', false],   // viewer cannot write
    ['U004', 'comment', 'delete', false],  // viewer cannot delete comments
    ['U005', 'article', 'edit', true],     // eve has both viewer+editor
    ['U005', 'comment', 'delete', true],   // eve can delete comments (editor)
    ['U999', 'article', 'read', false],    // unknown user
];

$allPass = true;
foreach ($tests as [$userId, $resource, $action, $expected]) {
    $result = $rbac->checkAccess($userId, $resource, $action);
    $status = $result === $expected ? 'OK' : 'FAIL';
    if ($status === 'FAIL') $allPass = false;
    $user = $rbac->getUser($userId);
    $name = $user ? $user->name : 'unknown';
    echo sprintf("  %-6s %-8s %-8s %-12s expected=%s got=%s %s\n",
        $userId, $name, $resource, $action, $expected ? 'true' : 'false', $result ? 'true' : 'false', $status);
}

echo "\nAll tests " . ($allPass ? 'PASSED' : 'FAILED') . "\n";

echo "\n--- User Roles ---\n";
foreach ($rbac->users as $user) {
    echo "  {$user->id} ({$user->name}): roles=[" . implode(', ', $user->getRoles()) . "]\n";
}

echo "\n--- Audit Log ---\n";
$allowedCount = 0;
$deniedCount = 0;
foreach ($rbac->getAuditLog() as $entry) {
    if ($entry['allowed']) $allowedCount++;
    else $deniedCount++;
}
echo "  Total checks: " . count($rbac->getAuditLog()) . "\n";
echo "  Allowed: $allowedCount\n";
echo "  Denied: $deniedCount\n";

// 动态角色变更
echo "\n--- Dynamic Role Change ---\n";
$diana->assignRole($editor);
echo "Diana now has roles: " . implode(', ', $diana->getRoles()) . "\n";
echo "Diana can write articles: " . ($diana->can('article', 'write') ? 'true' : 'false') . "\n";
$diana->revokeRole('editor');
echo "After revoke editor, can write: " . ($diana->can('article', 'write') ? 'true' : 'false') . "\n";
