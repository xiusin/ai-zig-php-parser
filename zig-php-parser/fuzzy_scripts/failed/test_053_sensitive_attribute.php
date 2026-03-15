<?php
// 测试53: 敏感参数属性 (PHP 8.2)
function login(string $username, #[\SensitiveParameter] string $password): void {
    echo "Logging in: $username\n";
    // password在堆栈跟踪中会被隐藏
}

login("admin", "secret123");

// 模拟堆栈跟踪中敏感参数
class SecureHandler {
    public function process(
        string $data,
        #[\SensitiveParameter] string $apiKey,
        string $endpoint
    ): void {
        throw new RuntimeException("Processing failed");
    }
}

try {
    $handler = new SecureHandler();
    $handler->process("data", "sk-abc123", "/api/v1");
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 多个敏感参数
function transfer(
    string $from,
    #[\SensitiveParameter] string $privateKey,
    #[\SensitiveParameter] string $seed,
    float $amount
): void {
    echo "Transfer from: $from, amount: $amount\n";
}

transfer("account1", "private_key_xyz", "seed_123", 100.50);
?>
