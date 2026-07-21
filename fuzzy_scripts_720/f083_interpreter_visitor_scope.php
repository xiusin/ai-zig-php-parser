<?php
// 极度混搭: 解释器模式 + AST访问者 + 求值 + 变量作用域
echo "=== f083: Interpreter + Visitor + Scope ===\n";

abstract class Expr {}
class NumExpr extends Expr { public function __construct(public float $val) {} }
class VarExpr extends Expr { public function __construct(public string $name) {} }
class BinaryExpr extends Expr { public function __construct(public string $op, public Expr $left, public Expr $right) {} }
class UnaryExpr extends Expr { public function __construct(public string $op, public Expr $expr) {} }
class AssignExpr extends Expr { public function __construct(public string $name, public Expr $value) {} }
class CallExpr extends Expr { public function __construct(public string $func, public array $args) {} }
class IfExpr extends Expr { public function __construct(public Expr $cond, public Expr $then, public Expr $else) {} }
class BlockExpr extends Expr { public function __construct(public array $exprs) {} }

class Scope {
    private array $vars = [];
    private array $funcs = [];

    public function __construct(private ?Scope $parent = null) {}

    public function get(string $name): mixed {
        if (array_key_exists($name, $this->vars)) return $this->vars[$name];
        return $this->parent?->get($name);
    }

    public function set(string $name, mixed $value): void {
        $this->vars[$name] = $value;
    }

    public function setExisting(string $name, mixed $value): bool {
        if (array_key_exists($name, $this->vars)) { $this->vars[$name] = $value; return true; }
        return $this->parent?->setExisting($name, $value) ?? false;
    }

    public function defineFunc(string $name, array $params, Expr $body): void {
        $this->funcs[$name] = ['params' => $params, 'body' => $body];
    }

    public function getFunc(string $name): ?array {
        if (isset($this->funcs[$name])) return $this->funcs[$name];
        return $this->parent?->getFunc($name);
    }

    public function createChild(): Scope { return new Scope($this); }
}

class Interpreter {
    private Scope $global;

    public function __construct() {
        $this->global = new Scope();
        $this->registerBuiltins();
    }

    private function registerBuiltins(): void {
        $this->global->set('pi', M_PI);
        $this->global->set('e', M_E);
    }

    public function eval(Expr $expr, Scope $scope): mixed {
        if ($expr instanceof NumExpr) return $expr->val;
        if ($expr instanceof VarExpr) return $scope->get($expr->name) ?? throw new RuntimeException("Undefined: {$expr->name}");
        if ($expr instanceof BinaryExpr) {
            $l = $this->eval($expr->left, $scope);
            $r = $this->eval($expr->right, $scope);
            return match($expr->op) {
                '+' => $l + $r, '-' => $l - $r, '*' => $l * $r,
                '/' => $r == 0 ? throw new RuntimeException("Div by zero") : $l / $r,
                '%' => $l % $r,
                '==' => $l == $r, '!=' => $l != $r,
                '<' => $l < $r, '>' => $l > $r, '<=' => $l <= $r, '>=' => $l >= $r,
                '&&' => $l && $r, '||' => $l || $r,
            };
        }
        if ($expr instanceof UnaryExpr) {
            $v = $this->eval($expr->expr, $scope);
            return match($expr->op) { '-' => -$v, '!' => !$v, default => $v };
        }
        if ($expr instanceof AssignExpr) {
            $v = $this->eval($expr->value, $scope);
            $scope->set($expr->name, $v);
            return $v;
        }
        if ($expr instanceof CallExpr) {
            $func = $scope->getFunc($expr->func);
            if ($func !== null) {
                $funcScope = $scope->createChild();
                foreach ($func['params'] as $i => $param) {
                    $funcScope->set($param, $this->eval($expr->args[$i], $scope));
                }
                return $this->eval($func['body'], $funcScope);
            }
            // 内置函数
            $args = array_map(fn($a) => $this->eval($a, $scope), $expr->args);
            return match($expr->func) {
                'abs' => abs($args[0]),
                'max' => max($args),
                'min' => min($args),
                'sqrt' => sqrt($args[0]),
                'floor' => floor($args[0]),
                'ceil' => ceil($args[0]),
                'print' => print($args[0] . "\n"),
                default => throw new RuntimeException("Unknown function: {$expr->func}"),
            };
        }
        if ($expr instanceof IfExpr) {
            $cond = $this->eval($expr->cond, $scope);
            return $cond ? $this->eval($expr->then, $scope) : $this->eval($expr->else, $scope);
        }
        if ($expr instanceof BlockExpr) {
            $result = null;
            foreach ($expr->exprs as $e) $result = $this->eval($e, $scope);
            return $result;
        }
        throw new RuntimeException("Unknown expression type");
    }

    public function getGlobalScope(): Scope { return $this->global; }

    public function defineFunction(string $name, array $params, Expr $body): void {
        $this->global->defineFunc($name, $params, $body);
    }
}

class ASTPrinter {
    public function print(Expr $expr, int $depth = 0): string {
        $indent = str_repeat('  ', $depth);
        if ($expr instanceof NumExpr) return "{$indent}Num({$expr->val})\n";
        if ($expr instanceof VarExpr) return "{$indent}Var({$expr->name})\n";
        if ($expr instanceof BinaryExpr) {
            return "{$indent}Binary({$expr->op})\n" .
                $this->print($expr->left, $depth + 1) . $this->print($expr->right, $depth + 1);
        }
        if ($expr instanceof UnaryExpr) {
            return "{$indent}Unary({$expr->op})\n" . $this->print($expr->expr, $depth + 1);
        }
        if ($expr instanceof AssignExpr) {
            return "{$indent}Assign({$expr->name})\n" . $this->print($expr->value, $depth + 1);
        }
        if ($expr instanceof CallExpr) {
            $s = "{$indent}Call({$expr->func})\n";
            foreach ($expr->args as $arg) $s .= $this->print($arg, $depth + 1);
            return $s;
        }
        if ($expr instanceof IfExpr) {
            return "{$indent}If\n" . $this->print($expr->cond, $depth + 1) .
                "{$indent}Then:\n" . $this->print($expr->then, $depth + 2) .
                "{$indent}Else:\n" . $this->print($expr->else, $depth + 2);
        }
        if ($expr instanceof BlockExpr) {
            $s = "{$indent}Block:\n";
            foreach ($expr->exprs as $e) $s .= $this->print($e, $depth + 1);
            return $s;
        }
        return "{$indent}Unknown\n";
    }
}

// 测试
$interp = new Interpreter();
$scope = $interp->getGlobalScope();

echo "--- Basic Arithmetic ---\n";
// 2 + 3 * 4
$expr1 = new BinaryExpr('+', new NumExpr(2), new BinaryExpr('*', new NumExpr(3), new NumExpr(4)));
echo "2 + 3 * 4 = " . $interp->eval($expr1, $scope) . "\n";

echo "\n--- Variables ---\n";
// x = 10; y = 20; x + y
$expr2 = new BlockExpr([
    new AssignExpr('x', new NumExpr(10)),
    new AssignExpr('y', new NumExpr(20)),
    new BinaryExpr('+', new VarExpr('x'), new VarExpr('y')),
]);
echo "x=10; y=20; x+y = " . $interp->eval($expr2, $scope) . "\n";
echo "Global x = " . $scope->get('x') . "\n";

echo "\n--- Functions ---\n";
// fib(n) = if n < 2 then n else fib(n-1) + fib(n-2)
$interp->defineFunction('fib', ['n'], new IfExpr(
    new BinaryExpr('<', new VarExpr('n'), new NumExpr(2)),
    new VarExpr('n'),
    new BinaryExpr('+',
        new CallExpr('fib', [new BinaryExpr('-', new VarExpr('n'), new NumExpr(1))]),
        new CallExpr('fib', [new BinaryExpr('-', new VarExpr('n'), new NumExpr(2))])
    )
));
for ($i = 0; $i <= 10; $i++) {
    $result = $interp->eval(new CallExpr('fib', [new NumExpr($i)]), $scope);
    echo "fib($i) = $result\n";
}

echo "\n--- Built-in Functions ---\n";
$builtinExprs = [
    'abs(-5)' => new CallExpr('abs', [new UnaryExpr('-', new NumExpr(5))]),
    'max(3,7,2)' => new CallExpr('max', [new NumExpr(3), new NumExpr(7), new NumExpr(2)]),
    'min(3,7,2)' => new CallExpr('min', [new NumExpr(3), new NumExpr(7), new NumExpr(2)]),
    'sqrt(16)' => new CallExpr('sqrt', [new NumExpr(16)]),
    'floor(3.7)' => new CallExpr('floor', [new NumExpr(3.7)]),
    'ceil(3.2)' => new CallExpr('ceil', [new NumExpr(3.2)]),
];
foreach ($builtinExprs as $desc => $expr) {
    echo "$desc = " . $interp->eval($expr, $scope) . "\n";
}

echo "\n--- Conditional ---\n";
// if x > 5 then x * 2 else x / 2
$condExpr = new AssignExpr('x', new NumExpr(7));
$interp->eval($condExpr, $scope);
$ifExpr = new IfExpr(
    new BinaryExpr('>', new VarExpr('x'), new NumExpr(5)),
    new BinaryExpr('*', new VarExpr('x'), new NumExpr(2)),
    new BinaryExpr('/', new VarExpr('x'), new NumExpr(2))
);
echo "x=7; if x>5 then x*2 else x/2 = " . $interp->eval($ifExpr, $scope) . "\n";

$scope->set('x', 3);
echo "x=3; if x>5 then x*2 else x/2 = " . $interp->eval($ifExpr, $scope) . "\n";

echo "\n--- AST Structure ---\n";
$printer = new ASTPrinter();
echo $printer->print($expr1);
echo "---\n";
echo $printer->print($ifExpr);

echo "=== f083 Done ===\n";
