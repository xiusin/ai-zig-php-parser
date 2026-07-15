<?php
// 极度混搭: 字段验证器 + 规则链 + 自定义规则 + 批量验证 + 错误聚合
echo "=== c039: Validator + RuleChain + Custom + Batch + ErrorAggregate ===\n\n";

class ValidationError {
    public string $field;
    public string $rule;
    public string $message;

    public function __construct(string $field, string $rule, string $message) {
        $this->field = $field;
        $this->rule = $rule;
        $this->message = $message;
    }

    public function __toString(): string {
        return "$this->field ($this->rule): $this->message";
    }
}

class ValidationRule {
    private string $name;
    private $predicate;
    private string $errorMessage;
    private array $params;

    public function __construct(string $name, callable $predicate, string $errorMessage, array $params = []) {
        $this->name = $name;
        $this->predicate = $predicate;
        $this->errorMessage = $errorMessage;
        $this->params = $params;
    }

    public function validate(mixed $value): bool {
        return ($this->predicate)($value, $this->params);
    }

    public function getName(): string { return $this->name; }
    public function getMessage(): string { return $this->errorMessage; }
}

class FieldValidator {
    private string $field;
    private array $rules = [];
    private bool $required = false;
    private mixed $defaultValue = null;

    public function __construct(string $field) {
        $this->field = $field;
    }

    public function required(): self {
        $this->required = true;
        $this->rules[] = new ValidationRule(
            'required',
            fn($v) => $v !== null && $v !== '',
            'Field is required'
        );
        return $this;
    }

    public function minLength(int $min): self {
        $this->rules[] = new ValidationRule(
            'minLength',
            fn($v, $p) => is_string($v) && strlen($v) >= $p['min'],
            "Minimum length is $min",
            ['min' => $min]
        );
        return $this;
    }

    public function maxLength(int $max): self {
        $this->rules[] = new ValidationRule(
            'maxLength',
            fn($v, $p) => is_string($v) && strlen($v) <= $p['max'],
            "Maximum length is $max",
            ['max' => $max]
        );
        return $this;
    }

    public function email(): self {
        $this->rules[] = new ValidationRule(
            'email',
            fn($v) => is_string($v) && preg_match('/^[\w.+-]+@[\w-]+\.[\w.-]+$/', $v),
            'Invalid email format'
        );
        return $this;
    }

    public function numeric(): self {
        $this->rules[] = new ValidationRule(
            'numeric',
            fn($v) => is_numeric($v),
            'Must be numeric'
        );
        return $this;
    }

    public function integer(): self {
        $this->rules[] = new ValidationRule(
            'integer',
            fn($v) => is_int($v),
            'Must be integer'
        );
        return $this;
    }

    public function in(array $values): self {
        $this->rules[] = new ValidationRule(
            'in',
            fn($v, $p) => in_array($v, $p['values'], true),
            'Value not in allowed list',
            ['values' => $values]
        );
        return $this;
    }

    public function between($min, $max): self {
        $this->rules[] = new ValidationRule(
            'between',
            fn($v, $p) => is_numeric($v) && $v >= $p['min'] && $v <= $p['max'],
            "Must be between $min and $max",
            ['min' => $min, 'max' => $max]
        );
        return $this;
    }

    public function custom(callable $fn, string $message): self {
        $this->rules[] = new ValidationRule(
            'custom',
            fn($v) => $fn($v),
            $message
        );
        return $this;
    }

    public function regex(string $pattern, string $message): self {
        $this->rules[] = new ValidationRule(
            'regex',
            fn($v, $p) => is_string($v) && preg_match($p['pattern'], $v),
            $message,
            ['pattern' => $pattern]
        );
        return $this;
    }

    public function validate(mixed $value): array {
        $errors = [];
        foreach ($this->rules as $rule) {
            if (!$rule->validate($value)) {
                $errors[] = new ValidationError($this->field, $rule->getName(), $rule->getMessage());
            }
        }
        return $errors;
    }

    public function getField(): string { return $this->field; }
    public function getRuleCount(): int { return count($this->rules); }
}

class FormValidator {
    private array $fieldValidators = [];

    public function addField(FieldValidator $validator): self {
        $this->fieldValidators[$validator->getField()] = $validator;
        return $this;
    }

    public function validate(array $data): array {
        $allErrors = [];
        foreach ($this->fieldValidators as $field => $validator) {
            $value = $data[$field] ?? null;
            $errors = $validator->validate($value);
            $allErrors = array_merge($allErrors, $errors);
        }
        return $allErrors;
    }

    public function isValid(array $data): bool {
        return empty($this->validate($data));
    }

    public function getFieldCount(): int {
        return count($this->fieldValidators);
    }
}

// === 测试 ===

echo "--- Field Validation ---\n";

$username = (new FieldValidator('username'))
    ->required()
    ->minLength(3)
    ->maxLength(20)
    ->regex('/^[a-zA-Z0-9_]+$/', 'Only alphanumeric and underscore');

$email = (new FieldValidator('email'))
    ->required()
    ->email()
    ->maxLength(100);

$age = (new FieldValidator('age'))
    ->required()
    ->integer()
    ->between(18, 120);

$role = (new FieldValidator('role'))
    ->required()
    ->in(['admin', 'editor', 'viewer']);

$password = (new FieldValidator('password'))
    ->required()
    ->minLength(8)
    ->custom(fn($v) => is_string($v) && preg_match('/[A-Z]/', $v) && preg_match('/[a-z]/', $v) && preg_match('/\d/', $v), 'Must contain uppercase, lowercase, and digit');

echo "Fields: " . count([$username, $email, $age, $role, $password]) . "\n";

echo "\n--- Valid Data ---\n";
$validData = [
    'username' => 'john_doe123',
    'email' => 'john@example.com',
    'age' => 25,
    'role' => 'editor',
    'password' => 'SecurePass123',
];

$errors = array_merge(
    $username->validate($validData['username']),
    $email->validate($validData['email']),
    $age->validate($validData['age']),
    $role->validate($validData['role']),
    $password->validate($validData['password'])
);

if (empty($errors)) {
    echo "All fields valid\n";
} else {
    foreach ($errors as $e) echo "  $e\n";
}

echo "\n--- Invalid Data ---\n";
$invalidData = [
    'username' => 'ab',
    'email' => 'not-an-email',
    'age' => 15,
    'role' => 'superadmin',
    'password' => 'weak',
];

$allErrors = array_merge(
    $username->validate($invalidData['username']),
    $email->validate($invalidData['email']),
    $age->validate($invalidData['age']),
    $role->validate($invalidData['role']),
    $password->validate($invalidData['password'])
);

foreach ($allErrors as $e) {
    echo "  $e\n";
}

echo "\n--- Form Validator ---\n";
$form = new FormValidator();
$form->addField($username);
$form->addField($email);
$form->addField($age);
$form->addField($role);
$form->addField($password);

echo "Field count: " . $form->getFieldCount() . "\n";

$validSet = [
    'username' => 'alice_wonder',
    'email' => 'alice@test.org',
    'age' => 30,
    'role' => 'admin',
    'password' => 'StrongPass1',
];

echo "Valid form: " . var_export($form->isValid($validSet), true) . "\n";

$invalidSet = [
    'username' => 'x',
    'email' => 'bad',
    'age' => 'not-a-number',
    'role' => 'guest',
    'password' => 'short',
];

$errors = $form->validate($invalidSet);
echo "Error count: " . count($errors) . "\n";
foreach ($errors as $e) {
    echo "  $e\n";
}

echo "\n--- Missing Fields ---\n";
$emptyData = [];
$errors = $form->validate($emptyData);
echo "Missing field errors: " . count($errors) . "\n";
foreach ($errors as $e) {
    echo "  $e\n";
}

echo "\n=== c039 Done ===\n";
