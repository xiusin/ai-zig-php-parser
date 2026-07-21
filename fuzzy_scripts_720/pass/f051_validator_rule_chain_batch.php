<?php
// 极度混搭: 验证器 + 规则链 + 复合规则 + 条件验证 + 批量校验
echo "=== f051: Validator + Rule Chain + Batch ===\n";

class ValidationRule {
    public function __construct(
        public string $field,
        public string $rule,
        public mixed $param = null,
        public ?string $message = null
    ) {}

    public function passes(mixed $value): bool {
        return match($this->rule) {
            'required' => $value !== null && $value !== '',
            'string' => is_string($value),
            'integer' => is_int($value),
            'numeric' => is_numeric($value),
            'boolean' => is_bool($value),
            'array' => is_array($value),
            'min' => is_numeric($value) && $value >= $this->param,
            'max' => is_numeric($value) && $value <= $this->param,
            'min_len' => is_string($value) && strlen($value) >= $this->param,
            'max_len' => is_string($value) && strlen($value) <= $this->param,
            'email' => is_string($value) && (bool)preg_match('/^[^\s@]+@[^\s@]+\.[^\s@]+$/', $value),
            'url' => is_string($value) && (bool)filter_var($value, FILTER_VALIDATE_URL),
            'in' => in_array($value, (array)$this->param, true),
            'not_in' => !in_array($value, (array)$this->param, true),
            'regex' => is_string($value) && (bool)preg_match($this->param, $value),
            'alpha' => is_string($value) && ctype_alpha($value),
            'alnum' => is_string($value) && ctype_alnum($value),
            'digit' => is_string($value) && ctype_digit($value),
            'date' => is_string($value) && (bool)strtotime($value),
            'ip' => is_string($value) && (bool)filter_var($value, FILTER_VALIDATE_IP),
            'uuid' => is_string($value) && (bool)preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value),
            default => true,
        };
    }

    public function getMessage(): string {
        return $this->message ?? "Field '{$this->field}' failed rule '{$this->rule}'";
    }
}

class Validator {
    private array $rules = [];
    private array $errors = [];
    private array $data;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function addRule(string $field, string $rule, mixed $param = null, ?string $message = null): self {
        $this->rules[] = new ValidationRule($field, $rule, $param, $message);
        return $this;
    }

    public function validate(): bool {
        $this->errors = [];
        foreach ($this->rules as $rule) {
            $value = $this->data[$rule->field] ?? null;
            if (!$rule->passes($value)) {
                $this->errors[$rule->field][] = $rule->getMessage();
            }
        }
        return empty($this->errors);
    }

    public function getErrors(): array { return $this->errors; }
    public function hasErrors(): bool { return !empty($this->errors); }

    public static function make(array $data, array $rules): self {
        $v = new self($data);
        foreach ($rules as $field => $ruleStr) {
            $parts = explode('|', $ruleStr);
            foreach ($parts as $part) {
                if (str_contains($part, ':')) {
                    [$rule, $param] = explode(':', $part, 2);
                    $v->addRule($field, $rule, $param);
                } else {
                    $v->addRule($field, $part);
                }
            }
        }
        return $v;
    }
}

// 测试
echo "--- Form Validation ---\n";
$formData = [
    'name' => 'Alice',
    'email' => 'alice@example.com',
    'age' => 30,
    'password' => 'Secur3P@ss',
    'website' => 'https://example.com',
    'role' => 'admin',
];

$rules = [
    'name' => 'required|string|min_len:2|max_len:50',
    'email' => 'required|email',
    'age' => 'required|integer|min:18|max:120',
    'password' => 'required|string|min_len:8',
    'website' => 'url',
    'role' => 'required|in:admin,user,guest',
];

$validator = Validator::make($formData, $rules);
$valid = $validator->validate();
echo "Valid: " . var_export($valid, true) . "\n";
if ($validator->hasErrors()) {
    echo "Errors:\n";
    foreach ($validator->getErrors() as $field => $errors) {
        echo "  $field: " . implode('; ', $errors) . "\n";
    }
}

echo "\n--- Invalid Data ---\n";
$badData = [
    'name' => 'A',
    'email' => 'not-an-email',
    'age' => 15,
    'password' => 'short',
    'role' => 'superadmin',
];

$validator2 = Validator::make($badData, $rules);
$validator2->validate();
echo "Errors:\n";
foreach ($validator2->getErrors() as $field => $errors) {
    foreach ($errors as $e) echo "  $field: $e\n";
}

echo "\n--- Individual Rules ---\n";
$tests = [
    ['email', 'test@test.com', true],
    ['email', 'bad', false],
    ['url', 'https://x.com', true],
    ['url', 'not-url', false],
    ['uuid', '550e8400-e29b-41d4-a716-446655440000', true],
    ['uuid', 'not-uuid', false],
    ['alpha', 'HelloWorld', true],
    ['alpha', 'Hello123', false],
    ['alnum', 'Hello123', true],
    ['digit', '12345', true],
    ['digit', '12a45', false],
    ['ip', '192.168.1.1', true],
    ['ip', '999.0.0.1', false],
];

foreach ($tests as [$rule, $value, $expected]) {
    $r = new ValidationRule('test', $rule);
    $result = $r->passes($value);
    $status = $result === $expected ? 'OK' : 'FAIL';
    echo "  $rule('$value'): " . var_export($result, true) . " [$status]\n";
}

echo "=== f051 Done ===\n";
