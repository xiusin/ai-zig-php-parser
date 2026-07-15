<?php
// 极度混搭: 责任链 + 中间件管道 + HTTP模拟 + 响应构建 + 异常中断
echo "=== c018: Middleware Pipeline + HTTP Sim + Response Build ===\n\n";

class Request {
    private string $method;
    private string $path;
    private array $headers;
    private array $body;

    public function __construct(string $method, string $path, array $headers = [], array $body = []) {
        $this->method = $method;
        $this->path = $path;
        $this->headers = $headers;
        $this->body = $body;
    }

    public function getMethod(): string { return $this->method; }
    public function getPath(): string { return $this->path; }
    public function getHeader(string $key, ?string $default = null): ?string {
        $key = strtolower($key);
        foreach ($this->headers as $k => $v) {
            if (strtolower($k) === $key) return $v;
        }
        return $default;
    }
    public function getHeaders(): array { return $this->headers; }
    public function getBody(): array { return $this->body; }
    public function getParam(string $key, mixed $default = null): mixed {
        return $this->body[$key] ?? $default;
    }
}

class Response {
    private int $status;
    private string $body;
    private array $headers;

    public function __construct(int $status = 200, string $body = '', array $headers = []) {
        $this->status = $status;
        $this->body = $body;
        $this->headers = $headers;
    }

    public function getStatus(): int { return $this->status; }
    public function getBody(): string { return $this->body; }
    public function getHeaders(): array { return $this->headers; }

    public function __toString(): string {
        return "HTTP {$this->status}\n" . json_encode($this->headers) . "\n{$this->body}";
    }
}

class Middleware {
    private $handler;
    private ?Middleware $next = null;
    private string $name;

    public function __construct(string $name, callable $handler) {
        $this->name = $name;
        $this->handler = $handler;
    }

    public function setNext(Middleware $next): void {
        $this->next = $next;
    }

    public function handle(Request $request): Response {
        return ($this->handler)($request, $this->next, fn($req) => $this->next?->handle($req) ?? new Response(404, 'Not Found'));
    }

    public function getName(): string {
        return $this->name;
    }
}

class Pipeline {
    private array $middlewares = [];

    public function add(Middleware $mw): self {
        $this->middlewares[] = $mw;
        return $this;
    }

    public function handle(Request $request): Response {
        $count = count($this->middlewares);
        for ($i = $count - 2; $i >= 0; $i--) {
            $this->middlewares[$i]->setNext($this->middlewares[$i + 1]);
        }

        if ($count === 0) {
            return new Response(500, 'No middlewares');
        }

        return $this->middlewares[0]->handle($request);
    }

    public function getMiddlewareNames(): array {
        return array_map(fn($m) => $m->getName(), $this->middlewares);
    }
}

// === 中间件定义 ===

$loggingMiddleware = new Middleware('logging', function(Request $req, $next, callable $proceed) {
    echo "  [logging] {$req->getMethod()} {$req->getPath()}\n";
    $response = $proceed($req);
    echo "  [logging] Response: {$response->getStatus()}\n";
    return $response;
});

$authMiddleware = new Middleware('auth', function(Request $req, $next, callable $proceed) {
    $token = $req->getHeader('Authorization');
    if (!$token || $token !== 'Bearer valid-token') {
        echo "  [auth] Unauthorized\n";
        return new Response(401, json_encode(['error' => 'Unauthorized']), ['Content-Type' => 'application/json']);
    }
    echo "  [auth] Authorized\n";
    return $proceed($req);
});

$rateLimitMiddleware = new Middleware('rate-limit', function(Request $req, $next, callable $proceed) {
    static $requests = [];
    $ip = $req->getHeader('X-IP', '127.0.0.1');
    if (!isset($requests[$ip])) $requests[$ip] = 0;
    $requests[$ip]++;
    if ($requests[$ip] > 3) {
        echo "  [rate-limit] Too many requests from $ip\n";
        return new Response(429, json_encode(['error' => 'Rate limited']), ['Content-Type' => 'application/json']);
    }
    echo "  [rate-limit] Request #{$requests[$ip]} from $ip\n";
    return $proceed($req);
});

$validationMiddleware = new Middleware('validation', function(Request $req, $next, callable $proceed) {
    if ($req->getMethod() === 'POST') {
        $body = $req->getBody();
        if (empty($body)) {
            echo "  [validation] Empty POST body\n";
            return new Response(400, json_encode(['error' => 'Empty body']), ['Content-Type' => 'application/json']);
        }
        echo "  [validation] Body validated: " . count($body) . " fields\n";
    }
    return $proceed($req);
});

$finalMiddleware = new Middleware('handler', function(Request $req, $next, callable $proceed) {
    $path = $req->getPath();
    echo "  [handler] Processing $path\n";

    return match($path) {
        '/api/users' => new Response(200, json_encode(['users' => ['Alice', 'Bob', 'Charlie']]), ['Content-Type' => 'application/json']),
        '/api/products' => new Response(200, json_encode(['products' => ['Widget', 'Gadget']]), ['Content-Type' => 'application/json']),
        '/api/echo' => new Response(200, json_encode($req->getBody()), ['Content-Type' => 'application/json']),
        default => new Response(404, json_encode(['error' => 'Not found']), ['Content-Type' => 'application/json']),
    };
});

// === 测试 ===

echo "--- Full Pipeline ---\n";
$pipeline = new Pipeline();
$pipeline->add($loggingMiddleware);
$pipeline->add($authMiddleware);
$pipeline->add($rateLimitMiddleware);
$pipeline->add($validationMiddleware);
$pipeline->add($finalMiddleware);

echo "Pipeline: " . implode(" -> ", $pipeline->getMiddlewareNames()) . "\n";

echo "\n--- Valid Request ---\n";
$req = new Request('GET', '/api/users', ['Authorization' => 'Bearer valid-token', 'X-IP' => '192.168.1.1']);
echo $pipeline->handle($req) . "\n";

echo "\n--- Unauthorized ---\n";
$req = new Request('GET', '/api/users', ['X-IP' => '192.168.1.2']);
echo $pipeline->handle($req) . "\n";

echo "\n--- POST with body ---\n";
$req = new Request('POST', '/api/echo', ['Authorization' => 'Bearer valid-token', 'X-IP' => '192.168.1.3'], ['message' => 'hello', 'count' => 42]);
echo $pipeline->handle($req) . "\n";

echo "\n--- Rate Limited ---\n";
for ($i = 1; $i <= 5; $i++) {
    echo "Request $i:\n";
    $req = new Request('GET', '/api/products', ['Authorization' => 'Bearer valid-token', 'X-IP' => '10.0.0.1']);
    $resp = $pipeline->handle($req);
    echo "  Status: {$resp->getStatus()}\n";
}

echo "\n--- Not Found ---\n";
$req = new Request('GET', '/api/unknown', ['Authorization' => 'Bearer valid-token', 'X-IP' => '192.168.1.4']);
echo $pipeline->handle($req) . "\n";

echo "\n=== c018 Done ===\n";
