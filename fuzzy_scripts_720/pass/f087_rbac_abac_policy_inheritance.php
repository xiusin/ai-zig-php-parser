<?php
// 极度混搭: RBAC + ABAC + 策略评估 + 权限继承
echo "=== f087: RBAC + ABAC + Policy + Inheritance ===\n";

class Permission {
    public function __construct(public string $resource, public string $action) {}
    public function __toString(): string { return "$this->resource:$this->action"; }
}

class Role {
    public array $permissions = [];
    public array $children = [];

    public function __construct(public string $name) {}

    public function addPermission(Permission $p): self { $this->permissions[] = $p; return $this; }
    public function addChild(Role $role): self { $this->children[] = $role; return $this; }

    public function getAllPermissions(): array {
        $all = $this->permissions;
        foreach ($this->children as $child) {
            $all = array_merge($all, $child->getAllPermissions());
        }
        return $all;
    }

    public function hasPermission(string $resource, string $action): bool {
        foreach ($this->permissions as $p) {
            if (($p->resource === $resource || $p->resource === '*') && ($p->action === $action || $p->action === '*')) return true;
        }
        foreach ($this->children as $child) {
            if ($child->hasPermission($resource, $action)) return true;
        }
        return false;
    }
}

class User {
    public array $roles = [];
    public array $attributes = [];

    public function __construct(public string $id, public string $name) {}

    public function assignRole(Role $role): self { $this->roles[] = $role; return $this; }
    public function setAttribute(string $key, mixed $value): self { $this->attributes[$key] = $value; return $this; }

    public function can(string $resource, string $action): bool {
        foreach ($this->roles as $role) {
            if ($role->hasPermission($resource, $action)) return true;
        }
        return false;
    }
}

class Policy {
    public function __construct(
        public string $name,
        public array $conditions,
        public string $effect // 'allow' or 'deny'
    ) {}

    public function evaluate(User $user, string $resource, string $action, array $context = []): ?bool {
        $ctx = array_merge($user->attributes, $context, ['resource' => $resource, 'action' => $action]);
        foreach ($this->conditions as $cond) {
            if (!$this->evalCondition($cond, $ctx)) return null;
        }
        return $this->effect === 'allow';
    }

    private function evalCondition(array $cond, array $ctx): bool {
        $field = $cond['field']; $op = $cond['op']; $val = $cond['value'];
        $actual = $ctx[$field] ?? null;
        return match($op) {
            '==' => $actual == $val, '!=' => $actual != $val,
            '>' => $actual > $val, '<' => $actual < $val,
            '>=' => $actual >= $val, '<=' => $actual <= $val,
            'in' => is_array($val) && in_array($actual, $val),
            'contains' => is_array($actual) && in_array($val, $actual),
            default => false,
        };
    }
}

class ABACEvaluator {
    private array $policies = [];

    public function addPolicy(Policy $p): self { $this->policies[] = $p; return $this; }

    public function evaluate(User $user, string $resource, string $action, array $context = []): bool {
        $hasAllow = false; $hasDeny = false;
        foreach ($this->policies as $policy) {
            $result = $policy->evaluate($user, $resource, $action, $context);
            if ($result === false) $hasDeny = true;
            elseif ($result === true) $hasAllow = true;
        }
        // Deny 优先
        if ($hasDeny) return false;
        return $hasAllow;
    }
}

// 测试
echo "--- RBAC ---\n";
$admin = new Role('admin');
$admin->addPermission(new Permission('*', '*'));

$editor = new Role('editor');
$editor->addPermission(new Permission('article', 'read'));
$editor->addPermission(new Permission('article', 'write'));
$editor->addPermission(new Permission('article', 'edit'));

$viewer = new Role('viewer');
$viewer->addPermission(new Permission('article', 'read'));
$viewer->addPermission(new Permission('comment', 'read'));

$editor->addChild($viewer);

$alice = new User('u1', 'Alice');
$alice->assignRole($admin);
$bob = new User('u2', 'Bob');
$bob->assignRole($editor);
$carol = new User('u3', 'Carol');
$carol->assignRole($viewer);

echo "Alice can article:write = " . var_export($alice->can('article', 'write'), true) . "\n";
echo "Alice can user:delete = " . var_export($alice->can('user', 'delete'), true) . "\n";
echo "Bob can article:read = " . var_export($bob->can('article', 'read'), true) . "\n";
echo "Bob can article:write = " . var_export($bob->can('article', 'write'), true) . "\n";
echo "Bob can article:delete = " . var_export($bob->can('article', 'delete'), true) . "\n";
echo "Carol can article:read = " . var_export($carol->can('article', 'read'), true) . "\n";
echo "Carol can article:write = " . var_export($carol->can('article', 'write'), true) . "\n";
echo "Bob can comment:read (inherited) = " . var_export($bob->can('comment', 'read'), true) . "\n";

echo "\n--- ABAC ---\n";
$abac = new ABACEvaluator();
// 工作时间允许访问
$abac->addPolicy(new Policy('work_hours', [
    ['field' => 'hour', 'op' => '>=', 'value' => 9],
    ['field' => 'hour', 'op' => '<=', 'value' => 18],
], 'allow'));
// IP白名单
$abac->addPolicy(new Policy('ip_whitelist', [
    ['field' => 'ip', 'op' => 'in', 'value' => ['10.0.0.1', '10.0.0.2', '192.168.1.1']],
], 'allow'));
// 管理员拒绝非工作时段
$abac->addPolicy(new Policy('deny_external', [
    ['field' => 'location', 'op' => '!=', 'value' => 'office'],
    ['field' => 'role', 'op' => '!=', 'value' => 'admin'],
], 'deny'));

$dave = new User('u4', 'Dave');
$dave->setAttribute('department', 'engineering');
$dave->setAttribute('level', 5);

echo "Work hours (10am): " . var_export($abac->evaluate($dave, 'report', 'view', ['hour' => 10]), true) . "\n";
echo "After hours (20pm): " . var_export($abac->evaluate($dave, 'report', 'view', ['hour' => 20]), true) . "\n";
echo "Whitelisted IP: " . var_export($abac->evaluate($dave, 'report', 'view', ['ip' => '10.0.0.1']), true) . "\n";
echo "Non-whitelisted IP: " . var_export($abac->evaluate($dave, 'report', 'view', ['ip' => '8.8.8.8']), true) . "\n";

echo "\n--- Combined RBAC+ABAC ---\n";
function checkAccess(User $user, string $resource, string $action, ABACEvaluator $abac, array $context = []): bool {
    if (!$user->can($resource, $action)) return false;
    return $abac->evaluate($user, $resource, $action, $context);
}

echo "Bob article:write during work = " . var_export(checkAccess($bob, 'article', 'write', $abac, ['hour' => 14]), true) . "\n";
echo "Bob article:write after work = " . var_export(checkAccess($bob, 'article', 'write', $abac, ['hour' => 22]), true) . "\n";

echo "=== f087 Done ===\n";
