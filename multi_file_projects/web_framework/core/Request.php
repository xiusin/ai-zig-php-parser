<?php
// HTTP 请求对象
class Request {
    public string $method;
    public string $path;
    public array $headers = [];
    public array $query = [];
    public array $body = [];
    public array $params = [];
    public array $cookies = [];
    public ?string $ip = null;

    public function __construct(string $method, string $path, array $query = [], array $body = [], array $headers = [], array $cookies = []) {
        $this->method = strtoupper($method);
        $this->path = $path;
        $this->query = $query;
        $this->body = $body;
        $this->headers = $headers;
        $this->cookies = $cookies;
        $this->ip = '127.0.0.1';
    }

    public static function create(string $method, string $path, array $query = [], array $body = []): self {
        return new self($method, $path, $query, $body);
    }

    public function param(string $name, mixed $default = null): mixed {
        return $this->params[$name] ?? $default;
    }

    public function query(string $name, mixed $default = null): mixed {
        return $this->query[$name] ?? $default;
    }

    public function input(string $name, mixed $default = null): mixed {
        return $this->body[$name] ?? $default;
    }

    public function header(string $name, string $default = ''): string {
        return $this->headers[strtolower($name)] ?? $default;
    }

    public function isMethod(string $method): bool {
        return $this->method === strtoupper($method);
    }

    public function expectsJson(): bool {
        return strpos($this->header('accept'), 'application/json') !== false;
    }

    public function all(): array {
        return array_merge($this->query, $this->body);
    }

    public function only(array $keys): array {
        $result = [];
        $all = $this->all();
        foreach ($keys as $key) {
            if (isset($all[$key])) $result[$key] = $all[$key];
        }
        return $result;
    }
}
