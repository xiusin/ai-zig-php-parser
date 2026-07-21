<?php
// 极度混搭: 规则引擎 + 条件 + 动作 + 优先级 + 冲突解决
echo "=== f140: Rule Engine + Condition + Action + Priority ===\n";

class Fact {
    public function __construct(public array $attributes = []) {}
    public function get(string $key): mixed { return $this->attributes[$key] ?? null; }
    public function set(string $key, mixed $value): void { $this->attributes[$key] = $value; }
    public function has(string $key): bool { return isset($this->attributes[$key]); }
    public function toArray(): array { return $this->attributes; }
}

class Condition {
    public function __construct(public string $field, public string $operator, public mixed $value) {}

    public function evaluate(Fact $fact): bool {
        $factValue = $fact->get($this->field);
        return match($this->operator) {
            '==' => $factValue == $this->value,
            '!=' => $factValue != $this->value,
            '>' => $factValue > $this->value,
            '<' => $factValue < $this->value,
            '>=' => $factValue >= $this->value,
            '<=' => $factValue <= $this->value,
            'in' => is_array($this->value) && in_array($factValue, $this->value),
            'not_in' => is_array($this->value) && !in_array($factValue, $this->value),
            'contains' => is_array($factValue) && in_array($this->value, $factValue),
            'starts_with' => is_string($factValue) && str_starts_with($factValue, $this->value),
            'ends_with' => is_string($factValue) && str_ends_with($factValue, $this->value),
            'exists' => $fact->has($this->field),
            'not_exists' => !$fact->has($this->field),
            default => false,
        };
    }
}

class Rule {
    public array $conditions = [];
    public array $actions = [];
    public bool $enabled = true;

    public function __construct(public string $name, public int $priority = 0, public string $description = '') {}

    public function when(string $field, string $op, mixed $value): self {
        $this->conditions[] = new Condition($field, $op, $value);
        return $this;
    }

    public function then(callable $action, string $description = ''): self {
        $this->actions[] = ['fn' => $action, 'desc' => $description];
        return $this;
    }

    public function evaluate(Fact $fact): bool {
        if (!$this->enabled) return false;
        foreach ($this->conditions as $cond) {
            if (!$cond->evaluate($fact)) return false;
        }
        return true;
    }

    public function execute(Fact $fact): array {
        $results = [];
        foreach ($this->actions as $action) {
            $results[] = $action['fn']($fact);
        }
        return $results;
    }
}

class RuleEngine {
    private array $rules = [];
    private array $executionLog = [];
    private string $conflictResolution = 'priority'; // priority, recency, specificity

    public function addRule(Rule $rule): self { $this->rules[] = $rule; return $this; }
    public function setConflictResolution(string $strategy): self { $this->conflictResolution = $strategy; return $this; }

    public function fire(Fact $fact): array {
        $matchedRules = array_filter($this->rules, fn($r) => $r->evaluate($fact));
        $matchedRules = $this->resolveConflicts($matchedRules, $fact);
        $results = [];
        foreach ($matchedRules as $rule) {
            $actionResults = $rule->execute($fact);
            $this->executionLog[] = ['rule' => $rule->name, 'fact' => $fact->toArray(), 'actions' => count($rule->actions), 'results' => $actionResults];
            $results[] = ['rule' => $rule->name, 'actions' => count($rule->actions)];
        }
        return $results;
    }

    private function resolveConflicts(array $rules, Fact $fact): array {
        $rules = array_values($rules);
        return match($this->conflictResolution) {
            'priority' => (function() use ($rules) { usort($rules, fn($a, $b) => $b->priority <=> $a->priority); return $rules; })(),
            'recency' => array_reverse($rules),
            'specificity' => (function() use ($rules) { usort($rules, fn($a, $b) => count($b->conditions) <=> count($a->conditions)); return $rules; })(),
            'first_match' => array_slice($rules, 0, 1),
            default => $rules,
        };
    }

    public function getExecutionLog(): array { return $this->executionLog; }
    public function getRules(): array { return $this->rules; }
    public function getRuleCount(): int { return count($this->rules); }
}

// 测试
echo "--- Shopping Cart Discount Rules ---\n";
$engine = new RuleEngine();

$engine->addRule((new Rule('VIP Discount', 10, 'VIP customers get 20% off'))
    ->when('customerType', '==', 'VIP')
    ->then(function(Fact $f) { $discount = $f->get('total') * 0.20; $f->set('discount', $discount); $f->set('discountReason', 'VIP 20%'); return $discount; }, 'Apply 20% discount'));

$engine->addRule((new Rule('Bulk Discount', 8, 'Orders over $500 get 10% off'))
    ->when('total', '>=', 500)
    ->then(function(Fact $f) { $discount = $f->get('total') * 0.10; $f->set('discount', ($f->get('discount') ?? 0) + $discount); $f->set('discountReason', ($f->get('discountReason') ?? '') . ' + Bulk 10%'); return $discount; }, 'Apply 10% bulk discount'));

$engine->addRule((new Rule('Free Shipping', 5, 'Orders over $100 get free shipping'))
    ->when('total', '>=', 100)
    ->then(function(Fact $f) { $f->set('shipping', 0); $f->set('shippingReason', 'Free shipping over $100'); return 0; }, 'Free shipping'));

$engine->addRule((new Rule('New Customer', 3, 'New customers get $10 off'))
    ->when('isNew', '==', true)
    ->then(function(Fact $f) { $f->set('discount', ($f->get('discount') ?? 0) + 10); $f->set('discountReason', ($f->get('discountReason') ?? '') . ' + New customer $10'); return 10; }, '$10 new customer discount'));

$engine->addRule((new Rule('Weekend Surcharge', 1, 'Weekend orders have $5 surcharge'))
    ->when('isWeekend', '==', true)
    ->then(function(Fact $f) { $f->set('surcharge', 5); return 5; }, 'Add $5 weekend surcharge'));

$testCases = [
    ['total' => 600, 'customerType' => 'VIP', 'isNew' => false, 'isWeekend' => false, 'shipping' => 15],
    ['total' => 50, 'customerType' => 'regular', 'isNew' => true, 'isWeekend' => false, 'shipping' => 10],
    ['total' => 200, 'customerType' => 'regular', 'isNew' => false, 'isWeekend' => true, 'shipping' => 10],
    ['total' => 1000, 'customerType' => 'VIP', 'isNew' => true, 'isWeekend' => true, 'shipping' => 20],
    ['total' => 30, 'customerType' => 'regular', 'isNew' => false, 'isWeekend' => false, 'shipping' => 8],
];

foreach ($testCases as $i => $data) {
    $fact = new Fact($data);
    $results = $engine->fire($fact);
    $finalTotal = $fact->get('total') - ($fact->get('discount') ?? 0) + ($fact->get('surcharge') ?? 0) + ($fact->get('shipping') ?? 0);
    echo "\n  Case " . ($i + 1) . ": total=\${$fact->get('total')}";
    echo " → discount=\${$fact->get('discount')}";
    echo " shipping=\${$fact->get('shipping')}";
    echo " surcharge=\${$fact->get('surcharge')}";
    echo " final=\${$finalTotal}";
    echo "\n    Rules fired: " . implode(', ', array_map(fn($r) => $r['rule'], $results)) . "\n";
    echo "    Reason: {$fact->get('discountReason')}\n";
}

echo "\n--- Fraud Detection Rules ---\n";
$fraudEngine = new RuleEngine();
$fraudEngine->setConflictResolution('specificity');

$fraudEngine->addRule((new Rule('High Amount', 5, 'Transaction over $10000'))
    ->when('amount', '>', 10000)
    ->then(fn(Fact $f) => $f->set('riskLevel', 'medium'), 'Set risk=medium'));

$fraudEngine->addRule((new Rule('Foreign Country', 5, 'Transaction from foreign country'))
    ->when('country', '!=', 'US')
    ->then(fn(Fact $f) => $f->set('riskLevel', 'medium'), 'Set risk=medium'));

$fraudEngine->addRule((new Rule('High Amount + Foreign', 10, 'High amount AND foreign'))
    ->when('amount', '>', 10000)
    ->when('country', '!=', 'US')
    ->then(fn(Fact $f) => $f->set('riskLevel', 'high'), 'Set risk=high')
    ->then(fn(Fact $f) => $f->set('action', 'block'), 'Block transaction'));

$fraudEngine->addRule((new Rule('Multiple Failed Attempts', 8, '3+ failed attempts'))
    ->when('failedAttempts', '>=', 3)
    ->then(fn(Fact $f) => $f->set('riskLevel', 'high'), 'Set risk=high')
    ->then(fn(Fact $f) => $f->set('action', 'verify'), 'Require verification'));

$fraudEngine->addRule((new Rule('Blacklisted IP', 15, 'IP in blacklist'))
    ->when('ip', 'in', ['10.0.0.1', '192.168.1.100', '172.16.0.1'])
    ->then(fn(Fact $f) => $f->set('riskLevel', 'critical'), 'Set risk=critical')
    ->then(fn(Fact $f) => $f->set('action', 'block'), 'Block immediately'));

$fraudTests = [
    ['amount' => 500, 'country' => 'US', 'failedAttempts' => 0, 'ip' => '192.168.1.1'],
    ['amount' => 15000, 'country' => 'US', 'failedAttempts' => 0, 'ip' => '10.0.0.2'],
    ['amount' => 500, 'country' => 'CN', 'failedAttempts' => 0, 'ip' => '10.0.0.3'],
    ['amount' => 20000, 'country' => 'RU', 'failedAttempts' => 0, 'ip' => '10.0.0.4'],
    ['amount' => 100, 'country' => 'US', 'failedAttempts' => 5, 'ip' => '10.0.0.5'],
    ['amount' => 50, 'country' => 'US', 'failedAttempts' => 0, 'ip' => '10.0.0.1'],
];

foreach ($fraudTests as $i => $data) {
    $fact = new Fact($data);
    $results = $fraudEngine->fire($fact);
    $risk = $fact->get('riskLevel') ?? 'low';
    $action = $fact->get('action') ?? 'allow';
    echo "  Case " . ($i + 1) . ": amount=\${$data['amount']} country={$data['country']} → risk=$risk action=$action\n";
}

echo "\n--- Execution Log ---\n";
$log = $fraudEngine->getExecutionLog();
echo "Total rules fired: " . count($log) . "\n";
foreach (array_slice($log, -5) as $entry) {
    echo "  Rule '{$entry['rule']}' fired ({$entry['actions']} actions)\n";
}

echo "\n--- Rule Management ---\n";
echo "Total rules: " . $fraudEngine->getRuleCount() . "\n";
foreach ($fraudEngine->getRules() as $rule) {
    echo "  [{$rule->priority}] {$rule->name}: {$rule->description} (" . count($rule->conditions) . " conditions, " . count($rule->actions) . " actions)\n";
}

echo "=== f140 Done ===\n";
