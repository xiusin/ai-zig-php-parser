<?php
// 极度混搭: 安全框架 + 认证 + 授权 + RBAC + 审计日志
echo "=== f126: Security + Auth + RBAC + Audit ===\n";

class User {
    public array $roles = [];
    public array $permissions = [];
    public function __construct(public string $id, public string $username, public string $email, public string $passwordHash = '') {}
    public function hasRole(string $role): bool { return in_array($role, $this->roles); }
    public function hasPermission(string $perm): bool { return in_array($perm, $this->permissions); }
}

class Role {
    public array $permissions = [];
    public function __construct(public string $name, public string $description = '') {}
    public function addPermission(string $perm): self { $this->permissions[] = $perm; return $this; }
}

class AuthManager {
    private array $users = [];
    private array $tokens = [];
    private array $roles = [];

    public function registerRole(Role $role): void { $this->roles[$role->name] = $role; }

    public function registerUser(User $user, array $roles = []): void {
        foreach ($roles as $roleName) {
            if (isset($this->roles[$roleName])) {
                $user->roles[] = $roleName;
                $user->permissions = array_unique(array_merge($user->permissions, $this->roles[$roleName]->permissions));
            }
        }
        $this->users[$user->id] = $user;
    }

    public function login(string $username, string $password): ?string {
        foreach ($this->users as $user) {
            if ($user->username === $username && $user->passwordHash === $this->hashPassword($password)) {
                $token = bin2hex(random_bytes(16));
                $this->tokens[$token] = ['userId' => $user->id, 'expires' => time() + 3600, 'created' => time()];
                return $token;
            }
        }
        return null;
    }

    public function validateToken(string $token): ?User {
        if (!isset($this->tokens[$token])) return null;
        if (time() > $this->tokens[$token]['expires']) { unset($this->tokens[$token]); return null; }
        return $this->users[$this->tokens[$token]['userId']] ?? null;
    }

    public function logout(string $token): void { unset($this->tokens[$token]); }

    public function hashPassword(string $password): string { return hash('sha256', $password . 'salt123'); }

    public function getUser(string $id): ?User { return $this->users[$id] ?? null; }
    public function getUsers(): array { return $this->users; }
}

class RBAC {
    private array $policies = [];

    public function addPolicy(string $role, string $resource, string $action, bool $allow = true): void {
        $this->policies[] = ['role' => $role, 'resource' => $resource, 'action' => $action, 'allow' => $allow];
    }

    public function check(User $user, string $resource, string $action): bool {
        foreach ($user->roles as $role) {
            foreach ($this->policies as $policy) {
                $roleMatch = $policy['role'] === '*' || $policy['role'] === $role;
                $resourceMatch = $policy['resource'] === '*' || $policy['resource'] === $resource;
                $actionMatch = $policy['action'] === '*' || $policy['action'] === $action;
                if ($roleMatch && $resourceMatch && $actionMatch) return $policy['allow'];
            }
        }
        return false;
    }
}

class ABAC {
    private array $policies = [];

    public function addPolicy(string $name, callable $condition): void {
        $this->policies[$name] = $condition;
    }

    public function evaluate(array $attributes): array {
        $results = [];
        foreach ($this->policies as $name => $condition) {
            $results[$name] = $condition($attributes);
        }
        return $results;
    }
}

class AuditLogger {
    private array $logs = [];

    public function log(string $action, string $userId, string $resource, array $details = [], bool $allowed = true): void {
        $this->logs[] = [
            'timestamp' => microtime(true),
            'action' => $action,
            'user' => $userId,
            'resource' => $resource,
            'allowed' => $allowed,
            'details' => $details,
        ];
    }

    public function getLogs(): array { return $this->logs; }
    public function getLogsByUser(string $userId): array {
        return array_values(array_filter($this->logs, fn($l) => $l['user'] === $userId));
    }
    public function getDeniedAttempts(): array {
        return array_values(array_filter($this->logs, fn($l) => !$l['allowed']));
    }
    public function getStats(): array {
        $total = count($this->logs);
        $allowed = count(array_filter($this->logs, fn($l) => $l['allowed']));
        return ['total' => $total, 'allowed' => $allowed, 'denied' => $total - $allowed];
    }
}

class RateLimiter {
    private array $requests = [];

    public function isAllowed(string $key, int $maxRequests, int $windowSeconds): bool {
        $now = time();
        if (!isset($this->requests[$key])) $this->requests[$key] = [];
        $this->requests[$key] = array_filter($this->requests[$key], fn($t) => $t > $now - $windowSeconds);
        if (count($this->requests[$key]) >= $maxRequests) return false;
        $this->requests[$key][] = $now;
        return true;
    }
}

// 测试
echo "--- Setup Auth ---\n";
$auth = new AuthManager();

$auth->registerRole((new Role('admin', 'Administrator'))->addPermission('read')->addPermission('write')->addPermission('delete')->addPermission('manage'));
$auth->registerRole((new Role('editor', 'Editor'))->addPermission('read')->addPermission('write'));
$auth->registerRole((new Role('viewer', 'Viewer'))->addPermission('read'));

$alice = new User('u1', 'alice', 'alice@test.com', $auth->hashPassword('pass123'));
$bob = new User('u2', 'bob', 'bob@test.com', $auth->hashPassword('secret'));
$charlie = new User('u3', 'charlie', 'charlie@test.com', $auth->hashPassword('test456'));

$auth->registerUser($alice, ['admin']);
$auth->registerUser($bob, ['editor']);
$auth->registerUser($charlie, ['viewer']);

echo "Users: " . count($auth->getUsers()) . "\n";

echo "\n--- Login ---\n";
$token = $auth->login('alice', 'pass123');
echo "Alice login: " . ($token ? "OK (token=" . substr($token, 0, 16) . "...)" : 'FAIL') . "\n";
$badToken = $auth->login('alice', 'wrong');
echo "Alice bad password: " . ($badToken ? 'OK' : 'FAIL') . "\n";

$user = $auth->validateToken($token);
echo "Validated: " . ($user ? $user->username : 'null') . "\n";
echo "Roles: " . implode(', ', $user->roles) . "\n";
echo "Permissions: " . implode(', ', $user->permissions) . "\n";

echo "\n--- RBAC Authorization ---\n";
$rbac = new RBAC();
$rbac->addPolicy('admin', '*', '*', true);
$rbac->addPolicy('editor', 'articles', '*', true);
$rbac->addPolicy('editor', 'users', 'read', true);
$rbac->addPolicy('viewer', 'articles', 'read', true);
$rbac->addPolicy('viewer', 'users', 'read', false);
$rbac->addPolicy('*', 'public', 'read', true);

$checks = [
    [$alice, 'articles', 'delete', true],
    [$alice, 'users', 'manage', true],
    [$bob, 'articles', 'write', true],
    [$bob, 'articles', 'delete', false],
    [$bob, 'users', 'read', true],
    [$bob, 'users', 'delete', false],
    [$charlie, 'articles', 'read', true],
    [$charlie, 'articles', 'write', false],
    [$charlie, 'public', 'read', true],
];
foreach ($checks as [$u, $res, $act, $expected]) {
    $result = $rbac->check($u, $res, $act);
    $status = $result === $expected ? '✓' : '✗';
    echo "  $status {$u->username} → $act $res: " . var_export($result, true) . " (expected " . var_export($expected, true) . ")\n";
}

echo "\n--- ABAC ---\n";
$abac = new ABAC();
$abac->addPolicy('own_resource', fn($attr) => ($attr['owner'] ?? null) === ($attr['user'] ?? null));
$abac->addPolicy('business_hours', fn($attr) => ($attr['hour'] ?? 0) >= 9 && ($attr['hour'] ?? 0) <= 17);
$abac->addPolicy('same_department', fn($attr) => ($attr['user_dept'] ?? null) === ($attr['resource_dept'] ?? null));

$abacResults = $abac->evaluate(['owner' => 'alice', 'user' => 'alice', 'hour' => 14, 'user_dept' => 'eng', 'resource_dept' => 'eng']);
echo "Alice accessing own resource during business hours:\n";
foreach ($abacResults as $policy => $result) echo "  $policy: " . var_export($result, true) . "\n";

$abacResults2 = $abac->evaluate(['owner' => 'alice', 'user' => 'bob', 'hour' => 20, 'user_dept' => 'eng', 'resource_dept' => 'sales']);
echo "\nBob accessing Alice's resource at night, different dept:\n";
foreach ($abacResults2 as $policy => $result) echo "  $policy: " . var_export($result, true) . "\n";

echo "\n--- Audit Log ---\n";
$audit = new AuditLogger();
$audit->log('login', 'u1', 'auth', ['ip' => '192.168.1.1'], true);
$audit->log('read', 'u1', 'articles/123', [], true);
$audit->log('delete', 'u2', 'articles/456', [], false);
$audit->log('write', 'u3', 'users/789', [], false);
$audit->log('login', 'u2', 'auth', ['ip' => '10.0.0.5'], true);

echo "Stats: " . json_encode($audit->getStats()) . "\n";
echo "\nDenied attempts:\n";
foreach ($audit->getDeniedAttempts() as $log) {
    echo "  {$log['user']} → {$log['action']} {$log['resource']}\n";
}
echo "\nAlice's logs:\n";
foreach ($audit->getLogsByUser('u1') as $log) {
    echo "  [{$log['action']}] {$log['resource']} allowed=" . var_export($log['allowed'], true) . "\n";
}

echo "\n--- Rate Limiter ---\n";
$limiter = new RateLimiter();
for ($i = 1; $i <= 10; $i++) {
    $allowed = $limiter->isAllowed('user:alice', 5, 60);
    echo "  Request $i: " . ($allowed ? 'ALLOWED' : 'BLOCKED') . "\n";
}

echo "=== f126 Done ===\n";
