<?php
// 极度混搭: 责任链模式 + 中间件管道 + 请求过滤 + 短路 + 顺序控制
echo "=== f032: Chain of Responsibility + Middleware Pipeline ===\n";

interface Handler {
    public function setNext(Handler $next): Handler;
    public function handle(array $request): array;
}

abstract class AbstractHandler implements Handler {
    private ?Handler $next = null;

    public function setNext(Handler $next): Handler {
        $this->next = $next;
        return $next;
    }

    public function handle(array $request): array {
        if ($this->next !== null) {
            return $this->next->handle($request);
        }
        return $request;
    }
}

class AuthHandler extends AbstractHandler {
    public function handle(array $request): array {
        $token = $request['token'] ?? '';
        if (empty($token)) {
            $request['errors'][] = 'Authentication required';
            return $request;
        }
        $request['user'] = 'authenticated_user';
        return parent::handle($request);
    }
}

class RateLimitHandler extends AbstractHandler {
    private array $visits = [];
    private int $limit;

    public function __construct(int $limit = 5) { $this->limit = $limit; }

    public function handle(array $request): array {
        $ip = $request['ip'] ?? '0.0.0.0';
        $this->visits[$ip] = ($this->visits[$ip] ?? 0) + 1;
        if ($this->visits[$ip] > $this->limit) {
            $request['errors'][] = "Rate limit exceeded for $ip";
            return $request;
        }
        $request['rate_limit_remaining'] = $this->limit - $this->visits[$ip];
        return parent::handle($request);
    }
}

class ValidationHandler extends AbstractHandler {
    public function handle(array $request): array {
        $data = $request['data'] ?? [];
        if (empty($data)) {
            $request['errors'][] = 'Data required';
        } elseif (!isset($data['email'])) {
            $request['errors'][] = 'Email required';
        }
        return parent::handle($request);
    }
}

class LoggingHandler extends AbstractHandler {
    public function handle(array $request): array {
        $request['logged_at'] = '2025-01-01T12:00:00Z';
        return parent::handle($request);
    }
}

class CacheHandler extends AbstractHandler {
    private array $cache = [];

    public function handle(array $request): array {
        $key = md5($request['url'] ?? '');
        if (isset($this->cache[$key])) {
            $request['cached'] = true;
            $request['response'] = $this->cache[$key];
            return $request;
        }
        $request = parent::handle($request);
        if (!isset($request['errors'])) {
            $this->cache[$key] = $request['response'] ?? 'default_response';
        }
        return $request;
    }
}

// 构建管道
$auth = new AuthHandler();
$auth->setNext(new RateLimitHandler(3))
     ->setNext(new ValidationHandler())
     ->setNext(new LoggingHandler())
     ->setNext(new CacheHandler());

// 测试1: 正常请求
echo "--- Test 1: Normal request ---\n";
$req1 = ['token' => 'abc123', 'ip' => '192.168.1.1', 'url' => '/api/users', 'data' => ['email' => 'test@test.com']];
$result1 = $auth->handle($req1);
echo json_encode($result1) . "\n";

// 测试2: 无token
echo "\n--- Test 2: No token ---\n";
$req2 = ['ip' => '192.168.1.2', 'url' => '/api/users', 'data' => ['email' => 'a@b.com']];
$result2 = $auth->handle($req2);
echo json_encode($result2) . "\n";

// 测试3: 限流
echo "\n--- Test 3: Rate limit ---\n";
for ($i = 0; $i < 5; $i++) {
    $r = $auth->handle(['token' => 'tok', 'ip' => '10.0.0.1', 'url' => '/api/data', 'data' => ['email' => 'x@y.com']]);
    if (isset($r['errors'])) echo "  Request $i: " . implode('; ', $r['errors']) . "\n";
}

echo "=== f032 Done ===\n";
