<?php
// 极度混搭: 异常处理全家桶 + 自定义异常 + 异常链 + 多catch + finally
echo "=== f046: Exception Handling + Custom + Chain + Multi-catch ===\n";

class AppException extends Exception {
    private array $context;

    public function __construct(string $message, array $context = [], int $code = 0, ?Throwable $previous = null) {
        $this->context = $context;
        parent::__construct($message, $code, $previous);
    }

    public function getContext(): array { return $this->context; }

    public function __toString(): string {
        return self::class . ": {$this->message} [code={$this->code}] context=" . json_encode($this->context);
    }
}

class ValidationException extends AppException {}
class NotFoundException extends AppException {}
class PermissionException extends AppException {}
class RateLimitException extends AppException {}

class ExceptionHandler {
    private array $log = [];

    public function handle(Throwable $e): string {
        $entry = [
            'type' => get_class($e),
            'message' => $e->getMessage(),
            'code' => $e->getCode(),
            'file' => basename($e->getFile()),
            'line' => $e->getLine(),
        ];

        if ($e instanceof AppException) {
            $entry['context'] = $e->getContext();
        }

        $chain = [];
        $current = $e;
        while (($prev = $current->getPrevious()) !== null) {
            $chain[] = get_class($prev) . ": " . $prev->getMessage();
            $current = $prev;
        }
        if (!empty($chain)) $entry['chain'] = $chain;

        $this->log[] = $entry;

        return match(true) {
            $e instanceof ValidationException => "VALIDATION_ERROR: {$e->getMessage()}",
            $e instanceof NotFoundException => "NOT_FOUND: {$e->getMessage()}",
            $e instanceof PermissionException => "PERMISSION_DENIED: {$e->getMessage()}",
            $e instanceof RateLimitException => "RATE_LIMITED: {$e->getMessage()}",
            default => "ERROR: {$e->getMessage()}",
        };
    }

    public function getLog(): array { return $this->log; }
    public function clearLog(): void { $this->log = []; }
}

class UserService {
    private array $users = ['alice' => ['name' => 'Alice', 'role' => 'admin']];

    public function getUser(string $username): array {
        if (!isset($this->users[$username])) {
            throw new NotFoundException("User '$username' not found", ['username' => $username]);
        }
        return $this->users[$username];
    }

    public function validateEmail(string $email): void {
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new ValidationException("Invalid email: $email", ['email' => $email]);
        }
    }

    public function checkPermission(string $username, string $action): void {
        $user = $this->getUser($username);
        $allowed = ['admin' => ['read', 'write', 'delete'], 'user' => ['read']];
        $role = $user['role'];
        if (!in_array($action, $allowed[$role] ?? [])) {
            throw new PermissionException("User '$username' cannot '$action'", ['user' => $username, 'action' => $action, 'role' => $role]);
        }
    }

    public function rateLimitedCall(int $count): void {
        if ($count > 3) {
            throw new RateLimitException("Too many calls ($count)", ['count' => $count, 'limit' => 3]);
        }
    }

    public function complexOperation(bool $failInner = false): void {
        try {
            if ($failInner) {
                throw new RuntimeException("Database connection failed");
            }
        } catch (RuntimeException $e) {
            throw new AppException("Complex operation failed", ['step' => 'db'], 500, $e);
        }
    }
}

// 测试
$handler = new ExceptionHandler();
$service = new UserService();

echo "--- NotFoundException ---\n";
try { $service->getUser('unknown'); }
catch (AppException $e) { echo $handler->handle($e) . "\n"; }

echo "\n--- ValidationException ---\n";
try { $service->validateEmail('not-an-email'); }
catch (AppException $e) { echo $handler->handle($e) . "\n"; }

echo "\n--- PermissionException ---\n";
try { $service->checkPermission('alice', 'delete-all'); }
catch (AppException $e) { echo $handler->handle($e) . "\n"; }

echo "\n--- RateLimitException ---\n";
try { $service->rateLimitedCall(10); }
catch (AppException $e) { echo $handler->handle($e) . "\n"; }

echo "\n--- Exception Chain ---\n";
try { $service->complexOperation(true); }
catch (AppException $e) { echo $handler->handle($e) . "\n"; }

echo "\n--- Multi-catch ---\n";
$operations = [
    fn() => $service->getUser('missing'),
    fn() => $service->validateEmail('bad'),
    fn() => $service->checkPermission('alice', 'hack'),
];
foreach ($operations as $i => $op) {
    try { $op(); }
    catch (ValidationException | NotFoundException | PermissionException $e) {
        echo "  Operation $i: " . $handler->handle($e) . "\n";
    }
}

echo "\n--- Finally ---\n";
function cleanupTest(bool $throw): string {
    try {
        if ($throw) throw new Exception("Oops");
        return "normal";
    } catch (Exception $e) {
        return "caught: " . $e->getMessage();
    } finally {
        echo "  [finally] cleanup executed\n";
    }
}
echo "Result: " . cleanupTest(false) . "\n";
echo "Result: " . cleanupTest(true) . "\n";

echo "\n--- Handler Log ---\n";
foreach ($handler->getLog() as $i => $entry) {
    echo "  [$i] {$entry['type']}: {$entry['message']}";
    if (isset($entry['chain'])) echo " chain=" . json_encode($entry['chain']);
    echo "\n";
}

echo "=== f046 Done ===\n";
