<?php
// 规约模式：条件组合、AND/OR/NOT、业务规则链
echo "=== f176: Specification Pattern + Rule Chain ===\n";

interface Specification {
    public function isSatisfiedBy(mixed $candidate): bool;
    public function and(Specification $other): Specification;
    public function or(Specification $other): Specification;
    public function not(): Specification;
}

abstract class BaseSpecification implements Specification {
    public function and(Specification $other): Specification { return new AndSpec($this, $other); }
    public function or(Specification $other): Specification { return new OrSpec($this, $other); }
    public function not(): Specification { return new NotSpec($this); }
}

class AndSpec extends BaseSpecification {
    public function __construct(private Specification $a, private Specification $b) {}
    public function isSatisfiedBy(mixed $c): bool { return $this->a->isSatisfiedBy($c) && $this->b->isSatisfiedBy($c); }
}

class OrSpec extends BaseSpecification {
    public function __construct(private Specification $a, private Specification $b) {}
    public function isSatisfiedBy(mixed $c): bool { return $this->a->isSatisfiedBy($c) || $this->b->isSatisfiedBy($c); }
}

class NotSpec extends BaseSpecification {
    public function __construct(private Specification $inner) {}
    public function isSatisfiedBy(mixed $c): bool { return !$this->inner->isSatisfiedBy($c); }
}

// 具体规约
class IsAdult extends BaseSpecification {
    public function isSatisfiedBy(mixed $c): bool { return ($c['age'] ?? 0) >= 18; }
}

class HasEmail extends BaseSpecification {
    public function isSatisfiedBy(mixed $c): bool { return !empty($c['email']) && filter_var($c['email'], FILTER_VALIDATE_EMAIL); }
}

class IsActive extends BaseSpecification {
    public function isSatisfiedBy(mixed $c): bool { return ($c['status'] ?? '') === 'active'; }
}

class HasRole extends BaseSpecification {
    public function __construct(private string $role) {}
    public function isSatisfiedBy(mixed $c): bool { return ($c['role'] ?? '') === $this->role; }
}

class AgeBetween extends BaseSpecification {
    public function __construct(private int $min, private int $max) {}
    public function isSatisfiedBy(mixed $c): bool { $age = $c['age'] ?? 0; return $age >= $this->min && $age <= $this->max; }
}

class HasPermission extends BaseSpecification {
    public function __construct(private string $permission) {}
    public function isSatisfiedBy(mixed $c): bool { return in_array($this->permission, $c['permissions'] ?? []); }
}

// 规则引擎
class RuleEngine {
    private array $rules = [];

    public function addRule(string $name, Specification $spec, callable $action): self {
        $this->rules[] = ['name' => $name, 'spec' => $spec, 'action' => $action];
        return $this;
    }

    public function evaluate(mixed $candidate): array {
        $matched = [];
        foreach ($this->rules as $rule) {
            if ($rule['spec']->isSatisfiedBy($candidate)) {
                $matched[] = $rule['name'];
                ($rule['action'])($candidate);
            }
        }
        return $matched;
    }

    public function getRules(): array { return $this->rules; }
}

// 测试
echo "--- Specification: User Validation ---\n";
$users = [
    ['name' => 'Alice', 'age' => 25, 'email' => 'alice@test.com', 'status' => 'active', 'role' => 'admin', 'permissions' => ['read', 'write', 'delete']],
    ['name' => 'Bob', 'age' => 16, 'email' => 'bob@test.com', 'status' => 'active', 'role' => 'user', 'permissions' => ['read']],
    ['name' => 'Charlie', 'age' => 35, 'email' => 'invalid', 'status' => 'inactive', 'role' => 'editor', 'permissions' => ['read', 'write']],
    ['name' => 'Diana', 'age' => 28, 'email' => 'diana@test.com', 'status' => 'active', 'role' => 'user', 'permissions' => ['read', 'write']],
];

// 复合规约
$canAccessAdmin = (new IsAdult())->and(new IsActive())->and(new HasRole('admin'));
$canEdit = (new IsAdult())->and(new IsActive())->and(
    (new HasRole('admin'))->or(new HasRole('editor'))->or(new HasPermission('write'))
);
$canDelete = (new HasRole('admin'))->and(new HasPermission('delete'));
$youngAdult = (new IsAdult())->and(new AgeBetween(18, 30));

echo "  User evaluation:\n";
foreach ($users as $user) {
    echo "    {$user['name']}:\n";
    echo "      Admin access: " . ($canAccessAdmin->isSatisfiedBy($user) ? 'Y' : 'N') . "\n";
    echo "      Can edit: " . ($canEdit->isSatisfiedBy($user) ? 'Y' : 'N') . "\n";
    echo "      Can delete: " . ($canDelete->isSatisfiedBy($user) ? 'Y' : 'N') . "\n";
    echo "      Young adult: " . ($youngAdult->isSatisfiedBy($user) ? 'Y' : 'N') . "\n";
}

echo "\n--- Negation ---\n";
$notAdult = (new IsAdult())->not();
$noEmail = (new HasEmail())->not();
foreach ($users as $user) {
    echo "  {$user['name']}: not adult=" . ($notAdult->isSatisfiedBy($user) ? 'Y' : 'N')
       . ", no valid email=" . ($noEmail->isSatisfiedBy($user) ? 'Y' : 'N') . "\n";
}

echo "\n--- Rule Engine ---\n";
$engine = new RuleEngine();

$engine
    ->addRule('welcome_email', new HasEmail(), function($user) {
        echo "    → Send welcome email to {$user['name']}\n";
    })
    ->addRule('age_warning', (new IsAdult())->not(), function($user) {
        echo "    → Parental consent required for {$user['name']}\n";
    })
    ->addRule('admin_notification', new HasRole('admin'), function($user) {
        echo "    → Notify admins about new admin: {$user['name']}\n";
    })
    ->addRule('inactive_reminder', (new IsActive())->not(), function($user) {
        echo "    → Send reactivation email to {$user['name']}\n";
    })
    ->addRule('delete_permission_grant', new HasPermission('delete'), function($user) {
        echo "    → Log delete permission for {$user['name']}\n";
    });

foreach ($users as $user) {
    echo "\n  Evaluating {$user['name']}:\n";
    $matched = $engine->evaluate($user);
    echo "    Matched rules: " . (empty($matched) ? 'none' : implode(', ', $matched)) . "\n";
}

echo "\n--- Complex Specification Chain ---\n";
$complexSpec = (new IsAdult())
    ->and(new IsActive())
    ->and(new HasEmail())
    ->and((new HasRole('admin'))->or(new HasRole('editor')))
    ->and(new AgeBetween(20, 40));

echo "  Complex spec (adult AND active AND has email AND (admin OR editor) AND age 20-40):\n";
foreach ($users as $user) {
    $result = $complexSpec->isSatisfiedBy($user);
    echo "    {$user['name']}: " . ($result ? 'PASS' : 'FAIL') . "\n";
}

echo "=== f176 Done ===\n";
