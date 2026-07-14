<?php
// f065: 中间件管道 (Middleware Pipeline)
echo "=== Middleware Pipeline ===\n\n";

interface Middleware {
    public function process(Request $request, callable $next): Response;
}

class Request {
    public array $attributes = [];
    public string $path;
    public string $method;

    public function __construct(string $path, string $method = 'GET') {
        $this->path = $path;
        $this->method = $method;
    }

    public function withAttribute(string $key, mixed $value): self {
        $clone = clone $this;
        $clone->attributes[$key] = $value;
        return $clone;
    }
}

class Response {
    public int $status;
    public string $body;
    public array $headers = [];

    public function __construct(int $status = 200, string $body = '') {
        $this->status = $status;
        $this->body = $body;
    }

    public function withHeader(string $name, string $value): self {
        $clone = clone $this;
        $clone->headers[$name] = $value;
        return $clone;
    }
}

class LoggingMiddleware implements Middleware {
    private string $name;

    public function __construct(string $name) {
        $this->name = $name;
    }

    public function process(Request $request, callable $next): Response {
        echo "  [{$this->name}] Before: {$request->method} {$request->path}\n";
        $response = $next($request);
        echo "  [{$this->name}] After: status={$response->status}\n";
        return $response;
    }
}

class AuthMiddleware implements Middleware {
    public function process(Request $request, callable $next): Response {
        if (!isset($request->attributes['user'])) {
            return new Response(401, 'Unauthorized');
        }
        return $next($request);
    }
}

class RateLimitMiddleware implements Middleware {
    private int $limit;
    private int $count = 0;

    public function __construct(int $limit = 5) {
        $this->limit = $limit;
    }

    public function process(Request $request, callable $next): Response {
        $this->count++;
        if ($this->count > $this->limit) {
            return new Response(429, 'Too Many Requests');
        }
        return $next($request);
    }
}

class CorsMiddleware implements Middleware {
    public function process(Request $request, callable $next): Response {
        $response = $next($request);
        return $response->withHeader('Access-Control-Allow-Origin', '*');
    }
}

class Pipeline {
    private array $middlewares = [];

    public function add(Middleware $middleware): self {
        $this->middlewares[] = $middleware;
        return $this;
    }

    public function handle(Request $request, callable $finalHandler): Response {
        $stack = $this->middlewares;
        $runner = function (Request $req) use (&$runner, &$stack, $finalHandler) {
            if (empty($stack)) {
                return $finalHandler($req);
            }
            $middleware = array_shift($stack);
            return $middleware->process($req, $runner);
        };
        return $runner($request);
    }
}

// 测试
echo "--- Basic Pipeline ---\n";
$pipeline = new Pipeline();
$pipeline->add(new LoggingMiddleware('log1'));
$pipeline->add(new CorsMiddleware());

$request = new Request('/api/users');
$request = $request->withAttribute('user', 'admin');

$response = $pipeline->handle($request, function (Request $req) {
    echo "  [handler] Processing {$req->path}\n";
    return new Response(200, '{"users": []}');
});

echo "Response: {$response->status} {$response->body}\n";
foreach ($response->headers as $k => $v) {
    echo "  Header: $k: $v\n";
}

echo "\n--- Auth Failure ---\n";
$pipeline2 = new Pipeline();
$pipeline2->add(new LoggingMiddleware('log2'));
$pipeline2->add(new AuthMiddleware());

$response2 = $pipeline2->handle(new Request('/api/secret'), function (Request $req) {
    return new Response(200, 'secret data');
});

echo "Response: {$response2->status} {$response2->body}\n";

echo "\n--- Rate Limit ---\n";
$pipeline3 = new Pipeline();
$pipeline3->add(new RateLimitMiddleware(3));

for ($i = 1; $i <= 5; $i++) {
    $resp = $pipeline3->handle(new Request('/api/data'), function (Request $req) {
        return new Response(200, 'ok');
    });
    echo "  Request $i: {$resp->status} {$resp->body}\n";
}

echo "\n--- Full Stack ---\n";
$pipeline4 = new Pipeline();
$pipeline4->add(new LoggingMiddleware('full'));
$pipeline4->add(new CorsMiddleware());
$pipeline4->add(new AuthMiddleware());
$pipeline4->add(new RateLimitMiddleware(10));

$req4 = new Request('/api/items', 'POST');
$req4 = $req4->withAttribute('user', 'admin');

$resp4 = $pipeline4->handle($req4, function (Request $req) {
    echo "  [handler] Creating item at {$req->path}\n";
    return new Response(201, '{"id": 1}');
});

echo "Response: {$resp4->status} {$resp4->body}\n";
