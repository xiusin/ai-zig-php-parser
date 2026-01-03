<?php
// Error handling and exceptions example

// Custom exception class
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

// Function that throws exceptions
function validateUser(array $data): void {
    $errors = [];
    
    if (empty($data['name'])) {
        $errors[] = "Name is required";
    }
    
    if (empty($data['email'])) {
        $errors[] = "Email is required";
    } elseif (!filter_var($data['email'], FILTER_VALIDATE_EMAIL)) {
        $errors[] = "Invalid email format";
    }
    
    if (!empty($data['age']) && $data['age'] < 0) {
        $errors[] = "Age must be positive";
    }
    
    if (!empty($errors)) {
        throw new ValidationException($errors);
    }
}

// Try-catch example
try {
    $userData = [
        'name' => '',
        'email' => 'invalid-email',
        'age' => -5
    ];
    
    validateUser($userData);
    echo "User validation passed!\n";
    
} catch (ValidationException $e) {
    echo "Validation failed: " . $e->getMessage() . "\n";
    echo "Errors:\n";
    foreach ($e->getErrors() as $error) {
        echo "  - {$error}\n";
    }
} catch (Exception $e) {
    echo "Unexpected error: " . $e->getMessage() . "\n";
}

// Try-catch-finally example
function processFile(string $filename): void {
    $file = null;
    
    try {
        echo "Opening file: {$filename}\n";
        $file = fopen($filename, 'r');
        
        if (!$file) {
            throw new RuntimeException("Could not open file: {$filename}");
        }
        
        echo "Processing file...\n";
        // Simulate file processing
        $content = fread($file, 1024);
        echo "Read " . strlen($content) . " bytes\n";
        
    } catch (RuntimeException $e) {
        echo "File error: " . $e->getMessage() . "\n";
    } finally {
        if ($file) {
            echo "Closing file\n";
            fclose($file);
        }
    }
}

// Test with non-existent file
processFile("nonexistent.txt");

// Multiple catch blocks
function divide(float $a, float $b): float {
    if ($b === 0.0) {
        throw new DivisionByZeroError("Cannot divide by zero");
    }
    
    if (!is_numeric($a) || !is_numeric($b)) {
        throw new InvalidArgumentException("Arguments must be numeric");
    }
    
    return $a / $b;
}

try {
    echo "10 / 2 = " . divide(10, 2) . "\n";
    echo "10 / 0 = " . divide(10, 0) . "\n";
} catch (DivisionByZeroError $e) {
    echo "Division error: " . $e->getMessage() . "\n";
} catch (InvalidArgumentException $e) {
    echo "Argument error: " . $e->getMessage() . "\n";
} catch (Throwable $e) {
    echo "Unexpected error: " . $e->getMessage() . "\n";
}

// Error handling with set_error_handler
function customErrorHandler(int $errno, string $errstr, string $errfile, int $errline): bool {
    echo "Custom error handler: [{$errno}] {$errstr} in {$errfile} on line {$errline}\n";
    return true; // Don't execute PHP's internal error handler
}

set_error_handler('customErrorHandler');

// Trigger a warning
echo "Triggering a warning...\n";
$result = 10 / 0; // This should trigger a warning

restore_error_handler();
?>