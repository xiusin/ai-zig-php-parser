<?php

class ValidationException extends Exception {
    private array $errors;
    
    public function __construct(array $errors, string $message = "Validation failed") {
        parent::__construct($message);
        $this->errors = $errors;
    }
    
    public function getErrors(): array {
        return $this->errors;
    }
}

function validateUser(array $data): void {
    $errors = [];
    
    if (!isset($data["name"]) || strlen($data["name"]) < 3) {
        $errors[] = "Name must be at least 3 characters";
    }
    
    if (!isset($data["age"]) || $data["age"] < 18) {
        $errors[] = "Age must be at least 18";
    }
    
    if (!empty($errors)) {
        throw new ValidationException($errors);
    }
}

// 测试 1: 正常情况
try {
    validateUser(["name" => "Alice", "age" => 25]);
    echo "Test 1: Success!\n";
} catch (ValidationException $e) {
    echo "Test 1: Validation error\n";
}

// 测试 2: 验证失败
try {
    validateUser(["name" => "Bo", "age" => 15]);
    echo "Test 2: Should not reach here\n";
} catch (ValidationException $e) {
    echo "Test 2: Caught validation error\n";
    foreach ($e->getErrors() as $error) {
        echo "  - $error\n";
    }
}
