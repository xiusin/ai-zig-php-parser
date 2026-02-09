<?php
// 测试异常处理

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

class DatabaseException extends Exception {}

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

function saveUser(array $data): void {
    validateUser($data);
    
    // 模拟数据库错误
    if ($data["name"] === "error") {
        throw new DatabaseException("Database connection failed");
    }
    
    echo "User saved: " . $data["name"] . "\n";
}

// 测试 1: 正常情况
try {
    saveUser(["name" => "Alice", "age" => 25]);
    echo "Success!\n";
} catch (ValidationException $e) {
    echo "Validation error: " . $e->getMessage() . "\n";
    foreach ($e->getErrors() as $error) {
        echo "  - $error\n";
    }
} catch (DatabaseException $e) {
    echo "Database error: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Unknown error: " . $e->getMessage() . "\n";
}

// 测试 2: 验证失败
try {
    saveUser(["name" => "Bo", "age" => 15]);
} catch (ValidationException $e) {
    echo "Validation error: " . $e->getMessage() . "\n";
    foreach ($e->getErrors() as $error) {
        echo "  - $error\n";
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

// 测试 3: 数据库错误
try {
    saveUser(["name" => "error", "age" => 30]);
} catch (DatabaseException $e) {
    echo "Database error: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

// 测试 4: finally 块
$resource = null;
try {
    $resource = "opened";
    echo "Resource opened\n";
    throw new Exception("Something went wrong");
} catch (Exception $e) {
    echo "Caught: " . $e->getMessage() . "\n";
} finally {
    if ($resource !== null) {
        echo "Resource closed\n";
        $resource = null;
    }
}

// 测试 5: 嵌套 try-catch
try {
    try {
        throw new ValidationException(["Inner error"]);
    } catch (ValidationException $e) {
        echo "Inner catch: " . $e->getMessage() . "\n";
        throw new DatabaseException("Wrapped error");
    }
} catch (DatabaseException $e) {
    echo "Outer catch: " . $e->getMessage() . "\n";
}
