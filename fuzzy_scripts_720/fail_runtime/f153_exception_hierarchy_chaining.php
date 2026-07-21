<?php
// 异常处理深入：自定义异常层级、异常链、多重 catch、finally 语义
echo "=== f153: Exception Hierarchy + Chaining + Multi-catch ===\n";

// 自定义异常层级
class AppException extends Exception {
    protected array $context = [];
    public function __construct(string $message, array $context = [], int $code = 0, ?Throwable $previous = null) {
        $this->context = $context;
        parent::__construct($message, $code, $previous);
    }
    public function getContext(): array { return $this->context; }
    public function getFullTrace(): string {
        return $this->getMessage() . " [code={$this->getCode()}]";
    }
}

class DatabaseException extends AppException {}
class ConnectionException extends DatabaseException {}
class QueryException extends DatabaseException {
    private string $sql;
    public function __construct(string $sql, string $message, int $code = 0, ?Throwable $previous = null) {
        $this->sql = $sql;
        parent::__construct($message, ['sql' => $sql], $code, $previous);
    }
    public function getSql(): string { return $this->sql; }
}

class ValidationException extends AppException {
    private array $errors;
    public function __construct(array $errors, string $message = 'Validation failed') {
        $this->errors = $errors;
        parent::__construct($message, ['errors' => $errors]);
    }
    public function getErrors(): array { return $this->errors; }
}

class AuthException extends AppException {}
class TokenExpiredException extends AuthException {}
class InvalidCredentialsException extends AuthException {}

// 异常处理中间层
class ExceptionHandler {
    public static function handle(Throwable $e): string {
        if ($e instanceof ConnectionException) {
            return "DB Connection Error: " . $e->getMessage();
        }
        if ($e instanceof QueryException) {
            return "Query Error: " . $e->getMessage() . " | SQL: " . $e->getSql();
        }
        if ($e instanceof ValidationException) {
            return "Validation: " . implode(', ', array_map(
                fn($field, $errors) => "$field: " . implode('|', $errors),
                array_keys($e->getErrors()),
                $e->getErrors()
            ));
        }
        if ($e instanceof TokenExpiredException) {
            return "Token expired, please re-authenticate";
        }
        if ($e instanceof InvalidCredentialsException) {
            return "Invalid email or password";
        }
        return "Unknown error: " . $e->getMessage();
    }
}

// 模拟操作
function connectDatabase(string $host): void {
    if ($host === 'invalid') {
        throw new ConnectionException("Cannot connect to $host", ['host' => $host]);
    }
}

function executeQuery(string $sql): void {
    if (strpos($sql, 'DROP') !== false) {
        throw new QueryException($sql, "DDL not allowed in production");
    }
}

function validateInput(array $data): void {
    $errors = [];
    if (empty($data['email'])) $errors['email'] = ['required'];
    if (!filter_var($data['email'] ?? '', FILTER_VALIDATE_EMAIL)) $errors['email'][] = 'invalid';
    if (strlen($data['password'] ?? '') < 8) $errors['password'] = ['min_length'];
    if (!empty($errors)) throw new ValidationException($errors);
}

function authenticate(string $token): void {
    if (empty($token)) throw new InvalidCredentialsException("Empty token");
    if ($token === 'expired') throw new TokenExpiredException("Token has expired");
}

// 测试
echo "--- Exception Chaining ---\n";
try {
    try {
        connectDatabase('invalid');
    } catch (ConnectionException $e) {
        throw new DatabaseException("Failed to initialize", ['original' => $e->getMessage()], 0, $e);
    }
} catch (DatabaseException $e) {
    echo "  Caught: " . $e->getMessage() . "\n";
    echo "  Previous: " . ($e->getPrevious()?->getMessage() ?? 'none') . "\n";
    echo "  Handler: " . ExceptionHandler::handle($e->getPrevious()) . "\n";
}

echo "\n--- Multi-Catch ---\n";
$exceptions = [
    fn() => connectDatabase('invalid'),
    fn() => executeQuery('DROP TABLE users'),
    fn() => validateInput(['email' => 'bad', 'password' => '123']),
    fn() => authenticate(''),
    fn() => authenticate('expired'),
];

foreach ($exceptions as $i => $fn) {
    try {
        $fn();
    } catch (ConnectionException | QueryException $e) {
        echo "  [$i] DB: " . ExceptionHandler::handle($e) . "\n";
    } catch (ValidationException $e) {
        echo "  [$i] " . ExceptionHandler::handle($e) . "\n";
    } catch (InvalidCredentialsException | TokenExpiredException $e) {
        echo "  [$i] Auth: " . ExceptionHandler::handle($e) . "\n";
    }
}

echo "\n--- Finally Semantics ---\n";
function processWithCleanup(int $mode): string {
    $resource = 'opened';
    try {
        if ($mode === 0) return "normal: $resource";
        if ($mode === 1) throw new Exception("error mode");
        return "other: $resource";
    } catch (Exception $e) {
        return "caught: " . $e->getMessage();
    } finally {
        $resource = 'closed';
    }
}
echo "  Mode 0: " . processWithCleanup(0) . "\n";
echo "  Mode 1: " . processWithCleanup(1) . "\n";
echo "  Mode 2: " . processWithCleanup(2) . "\n";

echo "\n--- Exception Context ---\n";
try {
    throw new AppException('Something went wrong', [
        'user_id' => 42,
        'action' => 'create_order',
        'timestamp' => '2026-07-20T12:00:00Z',
    ]);
} catch (AppException $e) {
    echo "  Message: " . $e->getMessage() . "\n";
    $ctx = $e->getContext();
    echo "  Context: user_id={$ctx['user_id']}, action={$ctx['action']}\n";
}

echo "\n--- Nested Exception Recovery ---\n";
function riskyOperation(int $attempt): string {
    if ($attempt < 3) {
        throw new Exception("Attempt $attempt failed");
    }
    return "Success on attempt $attempt";
}

function withRetry(int $maxAttempts, callable $fn): string {
    $lastError = null;
    for ($i = 1; $i <= $maxAttempts; $i++) {
        try {
            return $fn($i);
        } catch (Exception $e) {
            $lastError = $e;
            echo "  Attempt $i failed: " . $e->getMessage() . "\n";
        }
    }
    throw new Exception("All $maxAttempts attempts failed", 0, $lastError);
}

try {
    $result = withRetry(5, fn($n) => riskyOperation($n));
    echo "  Result: $result\n";
} catch (Exception $e) {
    echo "  Final: " . $e->getMessage() . "\n";
}

echo "=== f153 Done ===\n";
