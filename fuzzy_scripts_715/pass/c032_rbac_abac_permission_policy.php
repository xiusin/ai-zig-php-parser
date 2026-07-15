<?php
// 极度混搭: 权限系统 + RBAC + ABAC + 权限继承 + 策略组合
echo "=== c032: RBAC + ABAC + PermissionInherit + PolicyCompose ===\n\n";

class Permission {
    public string $name;
    public string $description;

    public function __construct(string $name, string $description = '') {
        $this->name = $name;
        $this->description = $description;
    }
}

class Role {
    private string $name;
    private array $permissions = [];
    private array $childRoles = [];

    public function __construct(string $name) {
        $this->name = $name;
    }

    public function addPermission(string|Permission $perm): self {
        $name = is_string($perm) ? $perm : $perm->name;
        $this->permissions[$name] = true;
        return $this;
    }

    public function removePermission(string $perm): self {
        unset($this->permissions[$perm]);
        return $this;
    }

    public function addChildRole(Role $role): self {
        $this->childRoles[$role->name] = $role;
        return $this;
    }

    public function hasPermission(string $perm): bool {
        if (isset($this->permissions[$perm])) return true;
        foreach ($this->childRoles as $child) {
            if ($child->hasPermission($perm)) return true;
        }
        return false;
    }

    public function getAllPermissions(): array {
        $perms = $this->permissions;
        foreach ($this->childRoles as $child) {
            $perms = array_merge($perms, $child->getAllPermissions());
        }
        return array_keys($perms);
    }

    public function getName(): string { return $this->name; }
}

class User {
    private string $id;
    private string $name;
    private array $roles = [];
    private array $attributes = [];

    public function __construct(string $id, string $name) {
        $this->id = $id;
        $this->name = $name;
    }

    public function assignRole(Role $role): self {
        $this->roles[$role->getName()] = $role;
        return $this;
    }

    public function removeRole(string $roleName): self {
        unset($this->roles[$roleName]);
        return $this;
    }

    public function setAttribute(string $key, mixed $value): self {
        $this->attributes[$key] = $value;
        return $this;
    }

    public function getAttribute(string $key): mixed {
        return $this->attributes[$key] ?? null;
    }

    public function can(string $permission): bool {
        foreach ($this->roles as $role) {
            if ($role->hasPermission($permission)) return true;
        }
        return false;
    }

    public function getRoles(): array {
        return array_keys($this->roles);
    }

    public function getAllPermissions(): array {
        $perms = [];
        foreach ($this->roles as $role) {
            $perms = array_merge($perms, $role->getAllPermissions());
        }
        return array_unique($perms);
    }

    public function getId(): string { return $this->id; }
    public function getName(): string { return $this->name; }
}

class Policy {
    private $condition;
    private string $effect;
    private array $actions;

    public function __construct(callable $condition, string $effect = 'allow', array $actions = ['*']) {
        $this->condition = $condition;
        $this->effect = $effect;
        $this->actions = $actions;
    }

    public function evaluate(User $user, string $action, array $resource): string {
        if (!in_array('*', $this->actions) && !in_array($action, $this->actions)) {
            return 'neutral';
        }
        $result = ($this->condition)($user, $action, $resource);
        return $result ? $this->effect : 'deny';
    }
}

class PolicyEngine {
    private array $policies = [];
    private string $defaultDecision = 'deny';

    public function addPolicy(Policy $policy): self {
        $this->policies[] = $policy;
        return $this;
    }

    public function evaluate(User $user, string $action, array $resource): bool {
        $hasAllow = false;
        $hasDeny = false;

        foreach ($this->policies as $policy) {
            $result = $policy->evaluate($user, $action, $resource);
            if ($result === 'deny') {
                $hasDeny = true;
            } elseif ($result === 'allow') {
                $hasAllow = true;
            }
        }

        if ($hasDeny) return false;
        if ($hasAllow) return true;
        return $this->defaultDecision === 'allow';
    }
}

// === 测试 ===

echo "--- Role Hierarchy ---\n";
$admin = new Role('admin');
$editor = new Role('editor');
$viewer = new Role('viewer');

$viewer->addPermission('read');
$editor->addPermission('read')->addPermission('write')->addChildRole($viewer);
$admin->addPermission('read')->addPermission('write')->addPermission('delete')->addPermission('manage')->addChildRole($editor);

echo "Viewer perms: " . implode(",", $viewer->getAllPermissions()) . "\n";
echo "Editor perms: " . implode(",", $editor->getAllPermissions()) . "\n";
echo "Admin perms: " . implode(",", $admin->getAllPermissions()) . "\n";

echo "\n--- User Assignment ---\n";
$alice = new User('u1', 'Alice');
$alice->assignRole($admin);
$bob = new User('u2', 'Bob');
$bob->assignRole($editor);
$charlie = new User('u3', 'Charlie');
$charlie->assignRole($viewer);

echo "Alice can delete: " . var_export($alice->can('delete'), true) . "\n";
echo "Bob can delete: " . var_export($bob->can('delete'), true) . "\n";
echo "Bob can write: " . var_export($bob->can('write'), true) . "\n";
echo "Charlie can write: " . var_export($charlie->can('write'), true) . "\n";
echo "Charlie can read: " . var_export($charlie->can('read'), true) . "\n";

echo "\n--- ABAC Policy Engine ---\n";
$engine = new PolicyEngine();

// Policy 1: Allow if user is in 'IT' department
$engine->addPolicy(new Policy(
    fn($u, $a, $r) => $u->getAttribute('department') === 'IT',
    'allow',
    ['read', 'write']
));

// Policy 2: Deny if user is suspended
$engine->addPolicy(new Policy(
    fn($u, $a, $r) => $u->getAttribute('status') === 'suspended',
    'deny',
    ['*']
));

// Policy 3: Allow if user has clearance >= resource clearance
$engine->addPolicy(new Policy(
    fn($u, $a, $r) => ($u->getAttribute('clearance') ?? 0) >= ($r['clearance'] ?? 0),
    'allow',
    ['read']
));

$dave = new User('u4', 'Dave');
$dave->setAttribute('department', 'IT');
$dave->setAttribute('status', 'active');
$dave->setAttribute('clearance', 5);

$eve = new User('u5', 'Eve');
$eve->setAttribute('department', 'HR');
$eve->setAttribute('status', 'active');
$eve->setAttribute('clearance', 2);

$frank = new User('u6', 'Frank');
$frank->setAttribute('department', 'IT');
$frank->setAttribute('status', 'suspended');
$frank->setAttribute('clearance', 5);

echo "Dave read (IT, active): " . var_export($engine->evaluate($dave, 'read', ['clearance' => 3]), true) . "\n";
echo "Dave write (IT): " . var_export($engine->evaluate($dave, 'write', ['clearance' => 3]), true) . "\n";
echo "Eve read (HR, clearance 2 vs 3): " . var_export($engine->evaluate($eve, 'read', ['clearance' => 3]), true) . "\n";
echo "Eve read (HR, clearance 2 vs 1): " . var_export($engine->evaluate($eve, 'read', ['clearance' => 1]), true) . "\n";
echo "Frank read (suspended): " . var_export($engine->evaluate($frank, 'read', ['clearance' => 1]), true) . "\n";

echo "\n--- Combined RBAC + ABAC ---\n";
$combinedEngine = new PolicyEngine();
$combinedEngine->addPolicy(new Policy(
    fn($u, $a, $r) => $u->can('read'),
    'allow',
    ['read']
));
$combinedEngine->addPolicy(new Policy(
    fn($u, $a, $r) => $u->getAttribute('status') === 'suspended',
    'deny',
    ['*']
));

$alice->setAttribute('status', 'active');
echo "Alice read (admin, active): " . var_export($combinedEngine->evaluate($alice, 'read', []), true) . "\n";
$charlie->setAttribute('status', 'suspended');
echo "Charlie read (viewer, suspended): " . var_export($combinedEngine->evaluate($charlie, 'read', []), true) . "\n";

echo "\n--- Dynamic Permission Check ---\n";
$users = [$alice, $bob, $charlie];
$actions = ['read', 'write', 'delete', 'manage'];
foreach ($users as $u) {
    $perms = [];
    foreach ($actions as $a) {
        $perms[] = $a . ":" . ($u->can($a) ? "Y" : "N");
    }
    echo "  {$u->getName()}: " . implode(" ", $perms) . "\n";
}

echo "\n=== c032 Done ===\n";
