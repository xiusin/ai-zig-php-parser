<?php
// 中间件管道
interface MiddlewareInterface {
    public function process(Request $request, callable $next): Response;
}

class MiddlewarePipeline {
    private array $middlewares = [];

    public function add(string|callable $middleware): self {
        $this->middlewares[] = $middleware;
        return $this;
    }

    public function handle(Request $request, callable $coreHandler): Response {
        $pipeline = array_reverse($this->middlewares);
        $handler = $coreHandler;
        foreach ($pipeline as $mw) {
            $handler = $this->wrapMiddleware($mw, $handler);
        }
        return $handler($request);
    }

    private function wrapMiddleware(string|callable $mw, callable $next): callable {
        return function(Request $request) use ($mw, $next) {
            if (is_string($mw)) {
                $instance = new $mw();
                return $instance->process($request, $next);
            }
            return $mw($request, $next);
        };
    }
}

// 日志中间件
class LogMiddleware implements MiddlewareInterface {
    private Logger $logger;

    public function __construct() {
        $this->logger = new Logger();
    }

    public function process(Request $request, callable $next): Response {
        $start = microtime(true);
        $this->logger->info("→ {$request->method} {$request->path} from {$request->ip}");
        $response = $next($request);
        $elapsed = round((microtime(true) - $start) * 1000, 2);
        $this->logger->info("← {$response->status} ({$elapsed}ms)");
        return $response;
    }
}

// 认证中间件
class AuthMiddleware implements MiddlewareInterface {
    public function process(Request $request, callable $next): Response {
        $token = $request->header('authorization');
        if (empty($token)) {
            return Response::json(['error' => 'Unauthorized'], 401);
        }
        $session = Session::getInstance();
        $userId = $session->validateToken($token);
        if (!$userId) {
            return Response::json(['error' => 'Invalid token'], 401);
        }
        $request->params['auth_user_id'] = $userId;
        return $next($request);
    }
}

// CORS 中间件
class CorsMiddleware implements MiddlewareInterface {
    public function process(Request $request, callable $next): Response {
        if ($request->method === 'OPTIONS') {
            return Response::make(204)->withHeaders([
                'Access-Control-Allow-Origin' => '*',
                'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
                'Access-Control-Allow-Headers' => 'Content-Type, Authorization',
            ]);
        }
        $response = $next($request);
        $response->withHeader('Access-Control-Allow-Origin', '*');
        return $response;
    }
}

// 限流中间件
class RateLimitMiddleware implements MiddlewareInterface {
    private static array $requests = [];
    private int $maxRequests = 100;
    private int $windowSeconds = 60;

    public function process(Request $request, callable $next): Response {
        $key = $request->ip;
        $now = time();
        if (!isset(self::$requests[$key])) {
            self::$requests[$key] = [];
        }
        self::$requests[$key] = array_filter(self::$requests[$key], fn($t) => $t > $now - $this->windowSeconds);
        if (count(self::$requests[$key]) >= $this->maxRequests) {
            return Response::json(['error' => 'Rate limit exceeded'], 429);
        }
        self::$requests[$key][] = $now;
        return $next($request);
    }
}
