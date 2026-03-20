<?php
class Router {
    private array $routes = [];

    public function add(string $method, string $path, callable $handler): self {
        $this->routes[] = [
            'method' => strtoupper($method),
            'path' => $path,
            'handler' => $handler
        ];
        return $this;
    }

    public function match(string $method, string $path): ?callable {
        foreach ($this->routes as $route) {
            if ($route['method'] !== strtoupper($method)) continue;

            $pattern = preg_replace('/\{(\w+)\}/', '([^/]+)', $route['path']);
            $pattern = '#^' . $pattern . '$#';

            if (preg_match($pattern, $path, $matches)) {
                array_shift($matches);
                return fn() => $route['handler'](...$matches);
            }
        }
        return null;
    }

    public function dispatch(string $method, string $path): mixed {
        $handler = $this->match($method, $path);
        if ($handler === null) {
            return "404 Not Found";
        }
        return $handler();
    }
}

$router = new Router();
$router
    ->add('GET', '/users', fn() => 'All users')
    ->add('GET', '/users/{id}', fn($id) => "User $id")
    ->add('POST', '/users', fn() => 'Create user')
    ->add('PUT', '/users/{id}', fn($id) => "Update user $id")
    ->add('DELETE', '/users/{id}', fn($id) => "Delete user $id");

echo $router->dispatch('GET', '/users') . "\n";
echo $router->dispatch('GET', '/users/123') . "\n";
echo $router->dispatch('POST', '/users') . "\n";
echo $router->dispatch('PUT', '/users/456') . "\n";
echo $router->dispatch('DELETE', '/users/789') . "\n";
echo "OK\n";
