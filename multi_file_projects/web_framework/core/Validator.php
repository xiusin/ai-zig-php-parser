<?php
// 验证器 + 验证异常
class ValidationException extends Exception {
    public array $errors;

    public function __construct(array $errors) {
        parent::__construct('Validation failed');
        $this->errors = $errors;
    }
}

class Validator {
    private array $data;
    private array $rules;
    private array $errors = [];
    private array $validated = [];

    public function __construct(array $data, array $rules) {
        $this->data = $data;
        $this->rules = $rules;
    }

    public function passes(): bool {
        $this->validate();
        return empty($this->errors);
    }

    public function fails(): bool {
        return !$this->passes();
    }

    public function errors(): array {
        return $this->errors;
    }

    public function validated(): array {
        return $this->validated;
    }

    private function validate(): void {
        $this->errors = [];
        $this->validated = [];

        foreach ($this->rules as $field => $ruleStr) {
            $value = $this->data[$field] ?? null;
            $rules = explode('|', $ruleStr);

            foreach ($rules as $rule) {
                $parts = explode(':', $rule);
                $ruleName = $parts[0];
                $ruleParam = $parts[1] ?? null;

                $error = $this->checkRule($field, $value, $ruleName, $ruleParam);
                if ($error !== null) {
                    $this->errors[$field][] = $error;
                }
            }

            if (!isset($this->errors[$field])) {
                $this->validated[$field] = $value;
            }
        }
    }

    private function checkRule(string $field, mixed $value, string $rule, ?string $param): ?string {
        switch ($rule) {
            case 'required':
                if ($value === null || $value === '' || $value === []) {
                    return "$field is required";
                }
                return null;

            case 'string':
                if ($value !== null && !is_string($value)) {
                    return "$field must be a string";
                }
                return null;

            case 'integer':
            case 'int':
                if ($value !== null && !is_int($value) && !ctype_digit((string)$value)) {
                    return "$field must be an integer";
                }
                return null;

            case 'numeric':
                if ($value !== null && !is_numeric($value)) {
                    return "$field must be numeric";
                }
                return null;

            case 'email':
                if ($value !== null && !filter_var($value, FILTER_VALIDATE_EMAIL)) {
                    return "$field must be a valid email";
                }
                return null;

            case 'min':
                $min = (float)$param;
                if (is_string($value) && strlen($value) < $min) {
                    return "$field must be at least $min characters";
                }
                if (is_numeric($value) && $value < $min) {
                    return "$field must be at least $min";
                }
                return null;

            case 'max':
                $max = (float)$param;
                if (is_string($value) && strlen($value) > $max) {
                    return "$field must not exceed $max characters";
                }
                if (is_numeric($value) && $value > $max) {
                    return "$field must not exceed $max";
                }
                return null;

            case 'in':
                $options = explode(',', $param ?? '');
                if ($value !== null && !in_array($value, $options)) {
                    return "$field must be one of: " . implode(', ', $options);
                }
                return null;

            case 'confirmed':
                $confirmField = $field . '_confirmation';
                if (($this->data[$confirmField] ?? null) !== $value) {
                    return "$field confirmation does not match";
                }
                return null;

            case 'regex':
                if ($value !== null && !preg_match('/' . $param . '/', (string)$value)) {
                    return "$field format is invalid";
                }
                return null;

            case 'array':
                if ($value !== null && !is_array($value)) {
                    return "$field must be an array";
                }
                return null;

            case 'nullable':
                return null;

            default:
                return null;
        }
    }
}
