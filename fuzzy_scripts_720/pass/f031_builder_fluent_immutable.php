<?php
// 极度混搭: 建造者模式 + 链式调用 + 不可变对象 + 验证 + 冻结
echo "=== f031: Builder + Fluent + Immutable + Freeze ===\n";

class HttpRequestBuilder {
    private string $method = 'GET';
    private string $url = '';
    private array $headers = [];
    private array $query = [];
    private ?string $body = null;
    private int $timeout = 30;
    private bool $verifySSL = true;

    public function method(string $m): self { $this->method = strtoupper($m); return $this; }
    public function url(string $u): self { $this->url = $u; return $this; }
    public function header(string $key, string $value): self { $this->headers[$key] = $value; return $this; }
    public function query(string $key, mixed $value): self { $this->query[$key] = $value; return $this; }
    public function body(string $b): self { $this->body = $b; return $this; }
    public function timeout(int $t): self { $this->timeout = $t; return $this; }
    public function verifySSL(bool $v): self { $this->verifySSL = $v; return $this; }

    public function build(): HttpRequest {
        if (empty($this->url)) throw new InvalidArgumentException("URL required");
        $queryString = '';
        if (!empty($this->query)) {
            $queryString = '?' . http_build_query($this->query);
        }
        return new HttpRequest(
            $this->method,
            $this->url . $queryString,
            $this->headers,
            $this->body,
            $this->timeout,
            $this->verifySSL
        );
    }
}

class HttpRequest {
    private bool $frozen = false;

    public function __construct(
        public readonly string $method,
        public readonly string $url,
        public readonly array $headers,
        public readonly ?string $body,
        public readonly int $timeout,
        public readonly bool $verifySSL
    ) {}

    public function toArray(): array {
        return [
            'method' => $this->method,
            'url' => $this->url,
            'headers' => $this->headers,
            'body' => $this->body,
            'timeout' => $this->timeout,
            'verifySSL' => $this->verifySSL,
        ];
    }

    public function __toString(): string {
        return "{$this->method} {$this->url} [timeout={$this->timeout}s ssl=" . var_export($this->verifySSL, true) . "]";
    }
}

// 测试
$req = (new HttpRequestBuilder())
    ->method('POST')
    ->url('https://api.example.com/v1/users')
    ->header('Content-Type', 'application/json')
    ->header('Authorization', 'Bearer token123')
    ->query('page', 1)
    ->query('limit', 20)
    ->body(json_encode(['name' => 'Alice', 'age' => 30]))
    ->timeout(15)
    ->verifySSL(false)
    ->build();

echo $req . "\n";
echo "Headers: " . json_encode($req->headers) . "\n";
echo "Body: " . $req->body . "\n";

// 验证异常
try {
    (new HttpRequestBuilder())->method('GET')->build();
} catch (InvalidArgumentException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

// 默认值
$req2 = (new HttpRequestBuilder())->url('https://example.com')->build();
echo "Default: $req2\n";

echo "=== f031 Done ===\n";
