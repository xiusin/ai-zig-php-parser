<?php
// 解释器模式：表达式求值、AST 遍历、上下文环境
echo "=== f168: Interpreter Pattern + AST Eval ===\n";

// AST 节点
abstract class Expr {
    abstract public function evaluate(array $context): mixed;
    abstract public function toString(): string;
}

class NumberExpr extends Expr {
    public function __construct(public float $value) {}
    public function evaluate(array $ctx): mixed { return $this->value; }
    public function toString(): string { return (string)$this->value; }
}

class StringExpr extends Expr {
    public function __construct(public string $value) {}
    public function evaluate(array $ctx): mixed { return $this->value; }
    public function toString(): string { return "'{$this->value}'"; }
}

class BoolExpr extends Expr {
    public function __construct(public bool $value) {}
    public function evaluate(array $ctx): mixed { return $this->value; }
    public function toString(): string { return $this->value ? 'true' : 'false'; }
}

class VariableExpr extends Expr {
    public function __construct(public string $name) {}
    public function evaluate(array $ctx): mixed { return $ctx[$this->name] ?? null; }
    public function toString(): string { return "\${$this->name}"; }
}

class BinaryExpr extends Expr {
    public function __construct(public string $op, public Expr $left, public Expr $right) {}
    public function evaluate(array $ctx): mixed {
        $l = $this->left->evaluate($ctx);
        $r = $this->right->evaluate($ctx);
        return match($this->op) {
            '+' => $l + $r,
            '-' => $l - $r,
            '*' => $l * $r,
            '/' => $r == 0 ? throw new DivisionByZeroError() : $l / $r,
            '%' => $l % $r,
            '**' => $l ** $r,
            '==' => $l == $r,
            '!=' => $l != $r,
            '<' => $l < $r,
            '>' => $l > $r,
            '<=' => $l <= $r,
            '>=' => $l >= $r,
            '&&' => $l && $r,
            '||' => $l || $r,
            '&' => $l & $r,
            '|' => $l | $r,
            '^' => $l ^ $r,
            default => throw new Exception("Unknown operator: {$this->op}"),
        };
    }
    public function toString(): string { return "({$this->left->toString()} {$this->op} {$this->right->toString()})"; }
}

class UnaryExpr extends Expr {
    public function __construct(public string $op, public Expr $operand) {}
    public function evaluate(array $ctx): mixed {
        $v = $this->operand->evaluate($ctx);
        return match($this->op) {
            '-' => -$v,
            '!' => !$v,
            '~' => ~$v,
            default => throw new Exception("Unknown unary op: {$this->op}"),
        };
    }
    public function toString(): string { return "{$this->op}{$this->operand->toString()}"; }
}

class TernaryExpr extends Expr {
    public function __construct(public Expr $cond, public Expr $true, public Expr $false) {}
    public function evaluate(array $ctx): mixed {
        return $this->cond->evaluate($ctx) ? $this->true->evaluate($ctx) : $this->false->evaluate($ctx);
    }
    public function toString(): string { return "{$this->cond->toString()} ? {$this->true->toString()} : {$this->false->toString()}"; }
}

class CallExpr extends Expr {
    public function __construct(public string $func, public array $args) {}
    public function evaluate(array $ctx): mixed {
        $evaluatedArgs = array_map(fn($a) => $a->evaluate($ctx), $this->args);
        $functions = [
            'max' => fn(...$a) => max($a),
            'min' => fn(...$a) => min($a),
            'abs' => fn($a) => abs($a),
            'sqrt' => fn($a) => sqrt($a),
            'pow' => fn($a, $b) => pow($a, $b),
            'floor' => fn($a) => floor($a),
            'ceil' => fn($a) => ceil($a),
            'round' => fn($a) => round($a),
            'strlen' => fn($a) => strlen($a),
            'count' => fn(...$a) => count($a),
        ];
        if (!isset($functions[$this->func])) throw new Exception("Unknown function: {$this->func}");
        return ($functions[$this->func])(...$evaluatedArgs);
    }
    public function toString(): string {
        $args = implode(', ', array_map(fn($a) => $a->toString(), $this->args));
        return "{$this->func}($args)";
    }
}

// 简易解析器
class ExprParser {
    private string $input;
    private int $pos = 0;

    public function __construct(string $input) {
        $this->input = trim($input);
    }

    public function parse(): Expr {
        return $this->parseTernary();
    }

    private function parseTernary(): Expr {
        $cond = $this->parseOr();
        if ($this->peek() === '?') {
            $this->consume('?');
            $true = $this->parseTernary();
            $this->consume(':');
            $false = $this->parseTernary();
            return new TernaryExpr($cond, $true, $false);
        }
        return $cond;
    }

    private function parseOr(): Expr {
        $left = $this->parseAnd();
        while ($this->match('||')) {
            $right = $this->parseAnd();
            $left = new BinaryExpr('||', $left, $right);
        }
        return $left;
    }

    private function parseAnd(): Expr {
        $left = $this->parseEquality();
        while ($this->match('&&')) {
            $right = $this->parseEquality();
            $left = new BinaryExpr('&&', $left, $right);
        }
        return $left;
    }

    private function parseEquality(): Expr {
        $left = $this->parseComparison();
        while (true) {
            if ($this->match('==')) { $left = new BinaryExpr('==', $left, $this->parseComparison()); }
            elseif ($this->match('!=')) { $left = new BinaryExpr('!=', $left, $this->parseComparison()); }
            else break;
        }
        return $left;
    }

    private function parseComparison(): Expr {
        $left = $this->parseAddSub();
        while (true) {
            if ($this->match('<=')) { $left = new BinaryExpr('<=', $left, $this->parseAddSub()); }
            elseif ($this->match('>=')) { $left = new BinaryExpr('>=', $left, $this->parseAddSub()); }
            elseif ($this->match('<')) { $left = new BinaryExpr('<', $left, $this->parseAddSub()); }
            elseif ($this->match('>')) { $left = new BinaryExpr('>', $left, $this->parseAddSub()); }
            else break;
        }
        return $left;
    }

    private function parseAddSub(): Expr {
        $left = $this->parseMulDiv();
        while (true) {
            if ($this->match('+')) { $left = new BinaryExpr('+', $left, $this->parseMulDiv()); }
            elseif ($this->match('-')) { $left = new BinaryExpr('-', $left, $this->parseMulDiv()); }
            else break;
        }
        return $left;
    }

    private function parseMulDiv(): Expr {
        $left = $this->parsePower();
        while (true) {
            if ($this->match('*')) { $left = new BinaryExpr('*', $left, $this->parsePower()); }
            elseif ($this->match('/')) { $left = new BinaryExpr('/', $left, $this->parsePower()); }
            elseif ($this->match('%')) { $left = new BinaryExpr('%', $left, $this->parsePower()); }
            else break;
        }
        return $left;
    }

    private function parsePower(): Expr {
        $left = $this->parseUnary();
        if ($this->match('**')) {
            return new BinaryExpr('**', $left, $this->parsePower());
        }
        return $left;
    }

    private function parseUnary(): Expr {
        if ($this->match('-')) return new UnaryExpr('-', $this->parseUnary());
        if ($this->match('!')) return new UnaryExpr('!', $this->parseUnary());
        return $this->parsePrimary();
    }

    private function parsePrimary(): Expr {
        $this->skipWhitespace();
        $ch = $this->peek();
        if ($ch === '(') {
            $this->consume('(');
            $expr = $this->parse();
            $this->consume(')');
            return $expr;
        }
        if ($ch === "'") {
            $this->consume("'");
            $end = strpos($this->input, "'", $this->pos);
            $str = substr($this->input, $this->pos, $end - $this->pos);
            $this->pos = $end + 1;
            return new StringExpr($str);
        }
        if (ctype_digit($ch) || $ch === '.') {
            $start = $this->pos;
            while ($this->pos < strlen($this->input) && (ctype_digit($this->input[$this->pos]) || $this->input[$this->pos] === '.')) {
                $this->pos++;
            }
            return new NumberExpr((float)substr($this->input, $start, $this->pos - $start));
        }
        if (ctype_alpha($ch)) {
            $start = $this->pos;
            while ($this->pos < strlen($this->input) && (ctype_alnum($this->input[$this->pos]) || $this->input[$this->pos] === '_')) {
                $this->pos++;
            }
            $name = substr($this->input, $start, $this->pos - $start);
            if ($name === 'true') return new BoolExpr(true);
            if ($name === 'false') return new BoolExpr(false);
            $this->skipWhitespace();
            if ($this->peek() === '(') {
                $this->consume('(');
                $args = [];
                $this->skipWhitespace();
                if ($this->peek() !== ')') {
                    $args[] = $this->parse();
                    while ($this->match(',')) { $args[] = $this->parse(); }
                }
                $this->consume(')');
                return new CallExpr($name, $args);
            }
            return new VariableExpr($name);
        }
        throw new Exception("Unexpected char: '$ch' at pos {$this->pos}");
    }

    private function peek(): ?string { return $this->input[$this->pos] ?? null; }
    private function consume(string $expected): void {
        $this->skipWhitespace();
        if (substr($this->input, $this->pos, strlen($expected)) !== $expected) {
            throw new Exception("Expected '$expected' at pos {$this->pos}");
        }
        $this->pos += strlen($expected);
    }
    private function match(string $token): bool {
        $this->skipWhitespace();
        if (substr($this->input, $this->pos, strlen($token)) === $token) {
            $this->pos += strlen($token);
            return true;
        }
        return false;
    }
    private function skipWhitespace(): void {
        while ($this->pos < strlen($this->input) && ctype_space($this->input[$this->pos])) $this->pos++;
    }
}

// 测试
echo "--- Expression Evaluation ---\n";
$context = ['x' => 10, 'y' => 20, 'z' => 5, 'name' => 'Alice'];

$expressions = [
    '1 + 2 * 3',
    '(1 + 2) * 3',
    '10 / 2 + 3',
    '2 ** 10',
    'x + y',
    'x * y - z',
    'x > 5 && y < 30',
    'x > 100 || y == 20',
    'x > 5 ? 100 : 200',
    'max(x, y, z)',
    'min(3, 1, 2)',
    'abs(-42)',
    'sqrt(144)',
    'pow(2, 8)',
    'strlen(name)',
    '-x + y',
    '!(x > 100)',
    'x + y * 2 - z / 5',
];

foreach ($expressions as $expr) {
    $parser = new ExprParser($expr);
    $ast = $parser->parse();
    $result = $ast->evaluate($context);
    echo "  $expr = $result  [AST: {$ast->toString()}]\n";
}

echo "\n--- Nested Expressions ---\n";
$complex = 'max(x * 2, y + z, abs(x - y)) + min(x, y)';
$parser = new ExprParser($complex);
$ast = $parser->parse();
echo "  $complex = " . $ast->evaluate($context) . "\n";
echo "  AST: " . $ast->toString() . "\n";

echo "\n--- Boolean Logic ---\n";
$boolExprs = [
    'true && false',
    'true || false',
    '!true',
    '(x > 5) && (y < 30)',
    '(x > 100) || (y == 20)',
    'x > 5 ? y > 10 ? "both" : "x only" : "neither"',
];
foreach ($boolExprs as $expr) {
    $parser = new ExprParser($expr);
    $ast = $parser->parse();
    $result = $ast->evaluate($context);
    echo "  $expr = " . var_export($result, true) . "\n";
}

echo "=== f168 Done ===\n";
