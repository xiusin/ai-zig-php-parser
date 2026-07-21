<?php
// 会话管理
class Session {
    private static ?Session $instance = null;
    private array $data = [];
    private array $tokens = []; // token => userId
    private string $sessionId;

    public static function getInstance(): self {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public function __construct() {
        $this->sessionId = bin2hex(random_bytes(16));
    }

    public function set(string $key, mixed $value): void {
        $this->data[$key] = $value;
    }

    public function get(string $key, mixed $default = null): mixed {
        return $this->data[$key] ?? $default;
    }

    public function has(string $key): bool {
        return isset($this->data[$key]);
    }

    public function remove(string $key): void {
        unset($this->data[$key]);
    }

    public function flush(): void {
        $this->data = [];
    }

    public function createToken(int $userId): string {
        $token = 'tk_' . bin2hex(random_bytes(16));
        $this->tokens[$token] = $userId;
        return $token;
    }

    public function validateToken(string $token): ?int {
        return $this->tokens[$token] ?? null;
    }

    public function revokeToken(string $token): void {
        unset($this->tokens[$token]);
    }

    public function getId(): string {
        return $this->sessionId;
    }

    public function flash(string $key, mixed $value): void {
        $this->set('_flash_' . $key, $value);
    }

    public function getFlash(string $key, mixed $default = null): mixed {
        $value = $this->get('_flash_' . $key, $default);
        $this->remove('_flash_' . $key);
        return $value;
    }
}
