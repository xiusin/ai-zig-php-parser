<?php
// 极度混搭: 规则引擎 + 条件评估 + 动作执行 + 优先级 + 冲突解决
echo "=== f074: Rule Engine + Conditions + Actions ===\n";

class RuleCondition {
    public function __construct(
        public string $field,
        public string $operator,
        public mixed $value
    ) {}

    public function evaluate(array $context): bool {
        $actual = $context[$this->field] ?? null;
        return match($this->operator) {
            '==' => $actual == $this->value,
            '!=' => $actual != $this->value,
            '>' => $actual > $this->value,
            '<' => $actual < $this->value,
            '>=' => $actual >= $this->value,
            '<=' => $actual <= $this->value,
            'in' => is_array($this->value) && in_array($actual, $this->value),
            'contains' => is_string($actual) && str_contains($actual, $this->value),
            'starts_with' => is_string($actual) && str_starts_with($actual, $this->value),
            'ends_with' => is_string($actual) && str_ends_with($actual, $this->value),
            default => false,
        };
    }
}

class Rule {
    public array $conditions = [];
    public array $actions = [];

    public function __construct(
        public string $id,
        public string $name,
        public int $priority = 0,
        public bool $enabled = true
    ) {}

    public function addCondition(RuleCondition $cond): self {
        $this->conditions[] = $cond;
        return $this;
    }

    public function addAction(string $action, array $params = []): self {
        $this->actions[] = ['action' => $action, 'params' => $params];
        return $this;
    }

    public function evaluate(array $context): bool {
        if (!$this->enabled) return false;
        foreach ($this->conditions as $cond) {
            if (!$cond->evaluate($context)) return false;
        }
        return true;
    }
}

class RuleEngine {
    private array $rules = [];
    private array $actionLog = [];

    public function addRule(Rule $rule): void {
        $this->rules[] = $rule;
    }

    public function execute(array $context): array {
        $matched = [];
        foreach ($this->rules as $rule) {
            if ($rule->evaluate($context)) {
                $matched[] = $rule;
            }
        }
        // 按优先级排序
        usort($matched, fn($a, $b) => $b->priority <=> $a->priority);

        $results = [];
        foreach ($matched as $rule) {
            $actions = [];
            foreach ($rule->actions as $action) {
                $result = $this->executeAction($action['action'], $action['params'], $context);
                $actions[] = ['action' => $action['action'], 'result' => $result];
                $this->actionLog[] = "Rule '{$rule->name}' → {$action['action']}";
            }
            $results[] = ['rule_id' => $rule->id, 'rule_name' => $rule->name, 'actions' => $actions];
        }
        return $results;
    }

    private function executeAction(string $action, array $params, array &$context): string {
        return match($action) {
            'set_flag' => $this->setFlag($params, $context),
            'add_tag' => $this->addTag($params, $context),
            'discount' => $this->applyDiscount($params, $context),
            'send_alert' => $this->sendAlert($params, $context),
            'log' => $this->logMessage($params),
            'block' => 'BLOCKED',
            'approve' => 'APPROVED',
            default => "unknown_action:$action",
        };
    }

    private function setFlag(array $params, array &$context): string {
        $context[$params['flag']] = $params['value'];
        return "flag_set:{$params['flag']}={$params['value']}";
    }

    private function addTag(array $params, array &$context): string {
        if (!isset($context['tags'])) $context['tags'] = [];
        $context['tags'][] = $params['tag'];
        return "tag_added:{$params['tag']}";
    }

    private function applyDiscount(array $params, array &$context): string {
        $discount = $params['percent'];
        $original = $context['price'] ?? 0;
        $context['final_price'] = $original * (1 - $discount / 100);
        return "discount:$discount% ({$original}→{$context['final_price']})";
    }

    private function sendAlert(array $params, array &$context): string {
        return "alert_sent:{$params['message']}";
    }

    private function logMessage(array $params): string {
        return "logged:{$params['message']}";
    }

    public function getActionLog(): array { return $this->actionLog; }
    public function clearLog(): void { $this->actionLog = []; }
}

// 测试
echo "--- E-commerce Discount Rules ---\n";
$engine = new RuleEngine();

// VIP客户折扣
$engine->addRule(
    (new Rule('r1', 'VIP Discount', 10))
        ->addCondition(new RuleCondition('user_level', '==', 'vip'))
        ->addCondition(new RuleCondition('price', '>=', 100))
        ->addAction('discount', ['percent' => 20])
        ->addAction('add_tag', ['tag' => 'vip_deal'])
);

// 新客户折扣
$engine->addRule(
    (new Rule('r2', 'New Customer Discount', 5))
        ->addCondition(new RuleCondition('is_new', '==', true))
        ->addAction('discount', ['percent' => 10])
        ->addAction('add_tag', ['tag' => 'welcome'])
);

// 大额订单
$engine->addRule(
    (new Rule('r3', 'Big Order', 8))
        ->addCondition(new RuleCondition('price', '>=', 500))
        ->addAction('discount', ['percent' => 15])
        ->addAction('send_alert', ['message' => 'Large order detected'])
);

// 电子产品加价
$engine->addRule(
    (new Rule('r4', 'Electronics Surcharge', 3))
        ->addCondition(new RuleCondition('category', 'in', ['phone', 'laptop', 'tv']))
        ->addAction('add_tag', ['tag' => 'electronics'])
);

// 被封禁用户
$engine->addRule(
    (new Rule('r5', 'Blocked User', 20))
        ->addCondition(new RuleCondition('user_status', '==', 'blocked'))
        ->addAction('block')
        ->addAction('log', ['message' => 'Blocked user attempted purchase'])
);

$testCases = [
    ['name' => 'VIP buying $200 phone', 'context' => ['user_level' => 'vip', 'price' => 200, 'category' => 'phone', 'user_status' => 'active']],
    ['name' => 'New customer $50', 'context' => ['is_new' => true, 'price' => 50, 'user_status' => 'active']],
    ['name' => 'VIP $600 laptop', 'context' => ['user_level' => 'vip', 'price' => 600, 'category' => 'laptop', 'user_status' => 'active']],
    ['name' => 'Blocked user $100', 'context' => ['price' => 100, 'user_status' => 'blocked']],
    ['name' => 'Regular $30 book', 'context' => ['price' => 30, 'category' => 'book', 'user_status' => 'active']],
];

foreach ($testCases as $tc) {
    $engine->clearLog();
    $results = $engine->execute($tc['context']);
    echo "\n  {$tc['name']}:\n";
    echo "    Context: " . json_encode($tc['context']) . "\n";
    if (empty($results)) echo "    No rules matched\n";
    foreach ($results as $r) {
        echo "    Rule '{$r['rule_name']}' matched:\n";
        foreach ($r['actions'] as $a) echo "      → {$a['result']}\n";
    }
    if (isset($tc['context']['final_price'])) echo "    Final price: \${$tc['context']['final_price']}\n";
    if (isset($tc['context']['tags'])) echo "    Tags: " . json_encode($tc['context']['tags']) . "\n";
}

echo "\n--- String Conditions ---\n";
$engine2 = new RuleEngine();
$engine2->addRule(
    (new Rule('s1', 'Email Check'))
        ->addCondition(new RuleCondition('email', 'ends_with', '@gmail.com'))
        ->addAction('log', ['message' => 'Gmail user'])
);
$engine2->addRule(
    (new Rule('s2', 'Name Check'))
        ->addCondition(new RuleCondition('name', 'starts_with', 'Admin'))
        ->addAction('log', ['message' => 'Admin access'])
);
$engine2->addRule(
    (new Rule('s3', 'Bio Check'))
        ->addCondition(new RuleCondition('bio', 'contains', 'developer'))
        ->addAction('add_tag', ['tag' => 'dev'])
);

$r = $engine2->execute(['email' => 'user@gmail.com', 'name' => 'AdminUser', 'bio' => 'I am a developer']);
foreach ($engine2->getActionLog() as $log) echo "  $log\n";

echo "=== f074 Done ===\n";
