<?php
// 中间件管道：洋葱模型、请求处理链、中断机制
echo "=== f180: Middleware Pipeline + Onion Model ===\n";

class HttpRequest {
    public function __construct(
        public string $method,
        public string $path,
        public array $headers = [],
        public ?string $body = null,
        public array $params = [],
    ) {}

    public function header(string $name): ?string {
        return $this->headers[$name] ?? null;
    }
}

class HttpResponse {
    public function __construct(
        public int $status = 200,
        public string $body = '',
        public array $headers = [],
    ) {}

    public function withHeader(string $name, string $value): self {
        $this->headers[$name] = $value;
        return $this;
    }

    public function json(array $data, int $status = 200): self {
        $this->status = $status;
        $this->body = json_encode($data);
        $this->headers['Content-Type'] = 'application/json';
        return $this;
    }

    public function text(string $body, int $status = 200): self {
        $this->status = $status;
        $this->body = $body;
        return $this;
    }
}

interface Middleware {
    public function process(HttpRequest $request, callable $next): HttpResponse;
}

class Pipeline {
    private array $middleware = [];

    public function add(Middleware ...$middleware): self {
        foreach ($middleware as $m) $this->middleware[] = $m;
        return $this;
    }

    public function handle(HttpRequest $request, callable $handler): HttpResponse {
        $stack = $this->middleware;
        $runner = function(HttpRequest $req) use (&$runner, &$stack, $handler) {
            if (empty($stack)) return $handler($req);
            $next = array_shift($stack);
            return $next->process($req, $runner);
        };
        return $runner($request);
    }
}

// 具体中间件
class LoggingMiddleware implements Middleware {
    public function process(HttpRequest $req, callable $next): HttpResponse {
        $start = microtime(true);
        echo "  [LOG] → {$req->method} {$req->path}\n";
        $response = $next($req);
        $elapsed = round((microtime(true) - $start) * 1000, 2);
        echo "  [LOG] ← {$response->status} ({$elapsed}ms)\n";
        return $response;
    }
}

class CorsMiddleware implements Middleware {
    public function process(HttpRequest $req, callable $next): HttpResponse {
        if ($req->method === 'OPTIONS') {
            return (new HttpResponse(204))
                ->withHeader('Access-Control-Allow-Origin', '*')
                ->withHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE')
                ->withHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        }
        $response = $next($req);
        $response->withHeader('Access-Control-Allow-Origin', '*');
        return $response;
    }
}

class AuthMiddleware implements Middleware {
    private array $validTokens = ['token_alice', 'token_bob'];

    public function process(HttpRequest $req, callable $next): HttpResponse {
        $auth = $req->header('Authorization');
        if (!$auth || !in_array($auth, $this->validTokens)) {
            echo "  [AUTH] ✗ Unauthorized\n";
            return (new HttpResponse())->json(['error' => 'Unauthorized'], 401);
        }
        echo "  [AUTH] ✓ Authorized\n";
        return $next($req);
    }
}

class RateLimitMiddleware implements Middleware {
    private array $requests = [];
    private int $maxRequests;
    private int $window;

    public function __construct(int $max = 100, int $window = 60) {
        $this->maxRequests = $max;
        $this->window = $window;
    }

    public function process(HttpRequest $req, callable $next): HttpResponse {
        $ip = $req->header('X-Forwarded-For') ?? '127.0.0.1';
        $now = time();
        if (!isset($this->requests[$ip])) $this->requests[$ip] = [];
        $this->requests[$ip] = array_filter($this->requests[$ip], fn($t) => $t > $now - $this->window);
        if (count($this->requests[$ip]) >= $this->maxRequests) {
            echo "  [RATE] ✗ Rate limited\n";
            return (new HttpResponse())->json(['error' => 'Rate limited'], 429);
        }
        $this->requests[$ip][] = $now;
        echo "  [RATE] ✓ OK (" . count($this->requests[$ip]) . "/{$this->maxRequests})\n";
        return $next($req);
    }
}

class ValidationMiddleware implements Middleware {
    public function process(HttpRequest $req, callable $next): HttpResponse {
        if ($req->method === 'POST' || $req->method === 'PUT') {
            if (!$req->header('Content-Type') || strpos($req->header('Content-Type'), 'application/json') === false) {
                echo "  [VALID] ✗ Invalid content type\n";
                return (new HttpResponse())->json(['error' => 'Content-Type must be application/json'], 400);
            }
        }
        echo "  [VALID] ✓ Valid\n";
        return $next($req);
    }
}

class CacheMiddleware implements Middleware {
    private array $cache = [];

    public function process(HttpRequest $req, callable $next): HttpResponse {
        if ($req->method !== 'GET') return $next($req);
        $key = $req->path;
        if (isset($this->cache[$key])) {
            echo "  [CACHE] ✓ Hit\n";
            return $this->cache[$key];
        }
        echo "  [CACHE] ✗ Miss, computing...\n";
        $response = $next($req);
        $this->cache[$key] = $response;
        return $response;
    }
}

// 测试
echo "--- Basic Pipeline ---\n";
$pipeline = new Pipeline();
$pipeline->add(new LoggingMiddleware(), new CorsMiddleware());

$handler = fn(HttpRequest $req) => (new HttpResponse())->json(['message' => 'Hello', 'path' => $req->path]);
$resp = $pipeline->handle(new HttpRequest('GET', '/api/hello'), $handler);
echo "  Response: {$resp->body}\n\n";

echo "--- Auth + RateLimit Pipeline ---\n";
$pipeline2 = new Pipeline();
$pipeline2->add(new LoggingMiddleware(), new RateLimitMiddleware(5), new AuthMiddleware());

$handler2 = fn(HttpRequest $req) => (new HttpResponse())->json(['data' => 'protected']);

echo "  Without token:\n";
$resp = $pipeline2->handle(new HttpRequest('GET', '/api/secret'), $handler2);
echo "  Status: {$resp->status}\n\n";

echo "  With valid token:\n";
$resp = $pipeline2->handle(
    new HttpRequest('GET', '/api/secret', ['Authorization' => 'token_alice']),
    $handler2
);
echo "  Status: {$resp->status}\n\n";

echo "--- Validation Pipeline ---\n";
$pipeline3 = new Pipeline();
$pipeline3->add(new LoggingMiddleware(), new ValidationMiddleware());

$handler3 = fn(HttpRequest $req) => (new HttpResponse())->json(['created' => true]);

echo "  POST without Content-Type:\n";
$resp = $pipeline3->handle(new HttpRequest('POST', '/api/items', [], '{}'), $handler3);
echo "  Status: {$resp->status}\n\n";

echo "  POST with Content-Type:\n";
$resp = $pipeline3->handle(
    new HttpRequest('POST', '/api/items', ['Content-Type' => 'application/json'], '{"name":"test"}'),
    $handler3
);
echo "  Status: {$resp->status}\n\n";

echo "--- Cache Pipeline ---\n";
$pipeline4 = new Pipeline();
$pipeline4->add(new LoggingMiddleware(), new CacheMiddleware());

$callCount = 0;
$handler4 = function(HttpRequest $req) use (&$callCount) {
    $callCount++;
    return (new HttpResponse())->json(['computed' => true, 'call' => $callCount]);
};

echo "  First request (miss):\n";
$resp = $pipeline4->handle(new HttpRequest('GET', '/api/data'), $handler4);
echo "  Response: {$resp->body}\n\n";

echo "  Second request (hit):\n";
$resp = $pipeline4->handle(new HttpRequest('GET', '/api/data'), $handler4);
echo "  Response: {$resp->body}\n\n";

echo "  Third request (different path, miss):\n";
$resp = $pipeline4->handle(new HttpRequest('GET', '/api/other'), $handler4);
echo "  Response: {$resp->body}\n\n";

echo "--- Full Stack Pipeline ---\n";
$pipeline5 = new Pipeline();
$pipeline5->add(
    new LoggingMiddleware(),
    new CorsMiddleware(),
    new RateLimitMiddleware(100),
    new AuthMiddleware(),
    new ValidationMiddleware(),
    new CacheMiddleware(),
);

$handler5 = fn(HttpRequest $req) => (new HttpResponse())->json([
    'message' => 'Full stack response',
    'user' => 'authenticated',
    'path' => $req->path,
]);

echo "  Full stack request:\n";
$resp = $pipeline5->handle(
    new HttpRequest('GET', '/api/full', ['Authorization' => 'token_bob']),
    $handler5
);
echo "  Status: {$resp->status}\n";
echo "  Body: {$resp->body}\n";
echo "  Headers: " . json_encode($resp->headers) . "\n";

echo "=== f180 Done ===\n";
