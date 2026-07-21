<?php
// 路由系统：静态路由 + 动态参数路由 + 路由分组 + RESTful
class Route {
    public string $method;
    public string $pattern;
    public mixed $handler;
    public array $middleware = [];
    public string $name = '';

    public function __construct(string $method, string $pattern, mixed $handler) {
        $this->method = strtoupper($method);
        $this->pattern = $pattern;
        $this->handler = $handler;
    }

    public function middleware(string|array $mw): self {
        $mws = is_array($mw) ? $mw : [$mw];
        foreach ($mws as $m) $this->middleware[] = $m;
        return $this;
    }

    public function name(string $name): self {
        $this->name = $name;
        return $this;
    }
}

class Router {
    public array $routes = [];
    public array $namedRoutes = [];
    public array $groupStack = [];

    public function get(string $pattern, mixed $handler): Route {
        return $this->addRoute('GET', $pattern, $handler);
    }

    public function post(string $pattern, mixed $handler): Route {
        return $this->addRoute('POST', $pattern, $handler);
    }

    public function put(string $pattern, mixed $handler): Route {
        return $this->addRoute('PUT', $pattern, $handler);
    }

    public function delete(string $pattern, mixed $handler): Route {
        return $this->addRoute('DELETE', $pattern, $handler);
    }

    public function patch(string $pattern, mixed $handler): Route {
        return $this->addRoute('PATCH', $pattern, $handler);
    }

    public function any(string $pattern, mixed $handler): Route {
        $route = $this->addRoute('ANY', $pattern, $handler);
        return $route;
    }

    public function addRoute(string $method, string $pattern, mixed $handler): Route {
        $prefix = '';
        $groupMw = [];
        foreach ($this->groupStack as $group) {
            $prefix .= $group['prefix'] ?? '';
            $mw = $group['middleware'] ?? [];
            $groupMw = array_merge($groupMw, is_array($mw) ? $mw : [$mw]);
        }
        $fullPattern = $prefix . $pattern;
        $route = new Route($method, $fullPattern, $handler);
        if (!empty($groupMw)) $route->middleware($groupMw);
        $this->routes[] = $route;
        return $route;
    }

    public function group(array $attrs, callable $callback): void {
        $this->groupStack[] = $attrs;
        $callback($this);
        array_pop($this->groupStack);
    }

    public function resource(string $name, string $controller): void {
        $this->get("/$name", [$controller, 'index']);
        $this->get("/$name/create", [$controller, 'create']);
        $this->post("/$name", [$controller, 'store']);
        $this->get("/$name/{id}", [$controller, 'show']);
        $this->get("/$name/{id}/edit", [$controller, 'edit']);
        $this->put("/$name/{id}", [$controller, 'update']);
        $this->delete("/$name/{id}", [$controller, 'destroy']);
    }

    public function match(Request $request): ?array {
        $method = $request->method;
        $path = $request->path;

        foreach ($this->routes as $route) {
            if ($route->method !== 'ANY' && $route->method !== $method) continue;
            $params = $this->matchPattern($route->pattern, $path);
            if ($params !== null) {
                return ['route' => $route, 'params' => $params];
            }
        }
        return null;
    }

    private function matchPattern(string $pattern, string $path): ?array {
        // 将路由模式编译为正则
        $regex = preg_replace('/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/', '(?P<$1>[^/]+)', $pattern);
        $regex = '#^' . $regex . '$#';
        if (preg_match($regex, $path, $matches)) {
            $params = [];
            foreach ($matches as $key => $value) {
                if (is_string($key)) $params[$key] = $value;
            }
            return $params;
        }
        return null;
    }

    public function url(string $name, array $params = []): string {
        $pattern = $this->namedRoutes[$name] ?? '';
        if (empty($pattern)) return '/';
        foreach ($params as $key => $value) {
            $pattern = str_replace('{' . $key . '}', (string)$value, $pattern);
        }
        return $pattern;
    }
}
