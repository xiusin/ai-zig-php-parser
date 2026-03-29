<?php
class Validator {
    private array $rules = [];

    public function addRule(string $field, callable $rule, string $message): self {
        $this->rules[$field][] = ['rule' => $rule, 'message' => $message];
        return $this;
    }

    public function required(string $field, $value): bool {
        return !empty($value);
    }

    public function minLength($value, int $len): bool {
        return strlen((string)$value) >= $len;
    }

    public function maxLength($value, int $len): bool {
        return strlen((string)$value) <= $len;
    }

    public function email($value): bool {
        return filter_var($value, FILTER_VALIDATE_EMAIL) !== false;
    }

    public function numeric($value): bool {
        return is_numeric($value);
    }

    public function validate(array $data): array {
        $errors = [];

        foreach ($this->rules as $field => $rules) {
            $value = $data[$field] ?? null;
            foreach ($rules as $r) {
                if (!$r['rule']($value)) {
                    $errors[$field][] = $r['message'];
                }
            }
        }

        return $errors;
    }
}

$validator = (new Validator())
    ->addRule('name', fn($v) => strlen($v) >= 2, 'Name must be at least 2 characters')
    ->addRule('name', fn($v) => strlen($v) <= 50, 'Name must not exceed 50 characters')
    ->addRule('email', fn($v) => filter_var($v, FILTER_VALIDATE_EMAIL), 'Invalid email format')
    ->addRule('age', fn($v) => is_numeric($v) && $v >= 18, 'Must be 18 or older');

$errors = $validator->validate(['name' => 'A', 'email' => 'invalid', 'age' => 15]);
if (empty($errors)) {
    echo "Valid\n";
} else {
    foreach ($errors as $field => $msgs) {
        echo "$field: " . implode(', ', $msgs) . "\n";
    }
}
echo "OK\n";
