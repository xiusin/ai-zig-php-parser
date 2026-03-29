<?php
// 测试67: 异常继承层次与自定义异常链
// 测试目的：验证复杂异常层次结构和异常链

// 基础异常
class AppException extends Exception {
    protected string $context = '';
    
    public function __construct(string $message, string $context = '', int $code = 0, ?Throwable $previous = null) {
        parent::__construct($message, $code, $previous);
        $this->context = $context;
    }
    
    public function getContext(): string {
        return $this->context;
    }
}

// 具体异常类型
class ValidationException extends AppException {}
class NotFoundException extends AppException {}
class DatabaseException extends AppException {}
class AuthenticationException extends AppException {}
class AuthorizationException extends AppException {}

// 业务逻辑异常
class BusinessRuleException extends AppException {
    private array $violations = [];
    
    public function __construct(string $message, array $violations = [], ?Throwable $previous = null) {
        parent::__construct($message, '', 0, $previous);
        $this->violations = $violations;
    }
    
    public function getViolations(): array {
        return $this->violations;
    }
}

// 异常处理类
class ExceptionHandler {
    private array $handlers = [];
    
    public function register(string $exceptionClass, callable $handler): void {
        $this->handlers[$exceptionClass] = $handler;
    }
    
    public function handle(Throwable $e): string {
        $class = get_class($e);
        
        // 精确匹配
        if (isset($this->handlers[$class])) {
            return ($this->handlers[$class])($e);
        }
        
        // 继承层次匹配
        foreach ($this->handlers as $exceptionClass => $handler) {
            if ($e instanceof $exceptionClass) {
                return $handler($e);
            }
        }
        
        return "Unhandled: " . $e->getMessage();
    }
}

// 测试异常处理
$handler = new ExceptionHandler();

$handler->register(AppException::class, fn($e) => "[APP] {$e->getMessage()}");
$handler->register(ValidationException::class, fn($e) => "[VALIDATION] {$e->getMessage()}");
$handler->register(NotFoundException::class, fn($e) => "[NOT FOUND] {$e->getMessage()}");

$exceptions = [
    new ValidationException("Email is required"),
    new NotFoundException("User not found", "user_id=123"),
    new DatabaseException("Connection failed"),
    new Exception("Generic error"),
];

echo "Exception handling:\n";
foreach ($exceptions as $e) {
    echo "  " . $handler->handle($e) . "\n";
}

// 异常链
function level3(): void {
    throw new DatabaseException("Query failed");
}

function level2(): void {
    try {
        level3();
    } catch (DatabaseException $e) {
        throw new AppException("Data access error", '', 0, $e);
    }
}

function level1(): void {
    try {
        level2();
    } catch (AppException $e) {
        throw new BusinessRuleException("Cannot complete operation", ['step' => 'data_load'], $e);
    }
}

echo "\nException chain:\n";
try {
    level1();
} catch (BusinessRuleException $e) {
    echo "Top level: " . $e->getMessage() . "\n";
    $current = $e;
    while ($current->getPrevious()) {
        $current = $current->getPrevious();
        echo "Caused by: " . get_class($current) . " - " . $current->getMessage() . "\n";
    }
}

// 多重catch
function riskyOperation(int $type): void {
    match($type) {
        1 => throw new ValidationException("Invalid input"),
        2 => throw new NotFoundException("Resource missing"),
        3 => throw new AuthenticationException("Login failed"),
        default => throw new Exception("Unknown error"),
    };
}

echo "\nMultiple catch blocks:\n";
for ($i = 1; $i <= 4; $i++) {
    try {
        riskyOperation($i);
    } catch (ValidationException $e) {
        echo "  Caught validation: {$e->getMessage()}\n";
    } catch (NotFoundException $e) {
        echo "  Caught not found: {$e->getMessage()}\n";
    } catch (AppException $e) {
        echo "  Caught app exception: {$e->getMessage()}\n";
    } catch (Exception $e) {
        echo "  Caught generic: {$e->getMessage()}\n";
    }
}

// 异常与finally
function withFinally(): string {
    try {
        throw new RuntimeException("Oops");
    } catch (RuntimeException $e) {
        return "caught";
    } finally {
        echo "Finally executed\n";
    }
}

echo "\nFinally test: " . withFinally() . "\n";

// Error转Exception
set_error_handler(function($severity, $message, $file, $line) {
    throw new ErrorException($message, 0, $severity, $file, $line);
});

echo "\nError to exception:\n";
try {
    // 触发警告
    @$undefined;
    // 这会被转换为异常
    trigger_error("Custom warning", E_USER_WARNING);
} catch (ErrorException $e) {
    echo "  Caught as exception: {$e->getMessage()}\n";
}

restore_error_handler();
?>
