<?php
// 极度混搭: 编译原理简化 + 词法分析 + 语法分析 + AST + 求值
echo "=== f063: Lexer + Parser + AST + Evaluator ===\n";

enum TokenType: string {
    case Number = 'NUMBER';
    case Plus = '+';
    case Minus = '-';
    case Mul = '*';
    case Div = '/';
    case LParen = '(';
    case RParen = ')';
    case EOF = 'EOF';
}

class Token {
    public function __construct(public TokenType $type, public mixed $value = null) {}
}

class Lexer {
    private int $pos = 0;
    private int $len;

    public function __construct(private string $input) {
        $this->len = strlen($input);
    }

    public function tokenize(): array {
        $tokens = [];
        while ($this->pos < $this->len) {
            $char = $this->input[$this->pos];
            if (ctype_space($char)) { $this->pos++; continue; }
            if (ctype_digit($char)) { $tokens[] = $this->readNumber(); continue; }
            $token = match($char) {
                '+' => new Token(TokenType::Plus),
                '-' => new Token(TokenType::Minus),
                '*' => new Token(TokenType::Mul),
                '/' => new Token(TokenType::Div),
                '(' => new Token(TokenType::LParen),
                ')' => new Token(TokenType::RParen),
                default => throw new RuntimeException("Unknown char: $char"),
            };
            $tokens[] = $token;
            $this->pos++;
        }
        $tokens[] = new Token(TokenType::EOF);
        return $tokens;
    }

    private function readNumber(): Token {
        $start = $this->pos;
        $hasDot = false;
        while ($this->pos < $this->len && (ctype_digit($this->input[$this->pos]) || $this->input[$this->pos] === '.')) {
            if ($this->input[$this->pos] === '.') {
                if ($hasDot) break;
                $hasDot = true;
            }
            $this->pos++;
        }
        $num = substr($this->input, $start, $this->pos - $start);
        return new Token(TokenType::Number, (float)$num);
    }
}

abstract class ASTNode {}
class NumNode extends ASTNode { public function __construct(public float $value) {} }
class BinOpNode extends ASTNode { public function __construct(public string $op, public ASTNode $left, public ASTNode $right) {} }
class UnaryNode extends ASTNode { public function __construct(public string $op, public ASTNode $operand) {} }

class Parser {
    private array $tokens;
    private int $pos = 0;

    public function __construct(array $tokens) { $this->tokens = $tokens; }

    private function current(): Token { return $this->tokens[$this->pos]; }
    private function advance(): Token { return $this->tokens[$this->pos++]; }

    private function expect(TokenType $type): Token {
        if ($this->current()->type !== $type) {
            throw new RuntimeException("Expected {$type->value}, got {$this->current()->type->value}");
        }
        return $this->advance();
    }

    // expr → term (('+'|'-') term)*
    public function parseExpr(): ASTNode {
        $node = $this->parseTerm();
        while ($this->current()->type === TokenType::Plus || $this->current()->type === TokenType::Minus) {
            $op = $this->advance()->type->value;
            $right = $this->parseTerm();
            $node = new BinOpNode($op, $node, $right);
        }
        return $node;
    }

    // term → factor (('*'|'/') factor)*
    private function parseTerm(): ASTNode {
        $node = $this->parseFactor();
        while ($this->current()->type === TokenType::Mul || $this->current()->type === TokenType::Div) {
            $op = $this->advance()->type->value;
            $right = $this->parseFactor();
            $node = new BinOpNode($op, $node, $right);
        }
        return $node;
    }

    // factor → NUMBER | '(' expr ')' | '-' factor
    private function parseFactor(): ASTNode {
        if ($this->current()->type === TokenType::Minus) {
            $this->advance();
            return new UnaryNode('-', $this->parseFactor());
        }
        if ($this->current()->type === TokenType::Number) {
            return new NumNode($this->advance()->value);
        }
        if ($this->current()->type === TokenType::LParen) {
            $this->advance();
            $node = $this->parseExpr();
            $this->expect(TokenType::RParen);
            return $node;
        }
        throw new RuntimeException("Unexpected token: {$this->current()->type->value}");
    }
}

class Evaluator {
    public function eval(ASTNode $node): float {
        if ($node instanceof NumNode) return $node->value;
        if ($node instanceof BinOpNode) {
            $l = $this->eval($node->left);
            $r = $this->eval($node->right);
            return match($node->op) {
                '+' => $l + $r,
                '-' => $l - $r,
                '*' => $l * $r,
                '/' => $r == 0 ? throw new RuntimeException("Div by zero") : $l / $r,
            };
        }
        if ($node instanceof UnaryNode) {
            $v = $this->eval($node->operand);
            return $node->op === '-' ? -$v : $v;
        }
        throw new RuntimeException("Unknown AST node");
    }

    public function astToString(ASTNode $node, int $depth = 0): string {
        $indent = str_repeat('  ', $depth);
        if ($node instanceof NumNode) return "{$indent}Num({$node->value})\n";
        if ($node instanceof BinOpNode) {
            return "{$indent}BinOp({$node->op})\n" .
                $this->astToString($node->left, $depth + 1) .
                $this->astToString($node->right, $depth + 1);
        }
        if ($node instanceof UnaryNode) {
            return "{$indent}Unary({$node->op})\n" .
                $this->astToString($node->operand, $depth + 1);
        }
        return "";
    }
}

// 测试
$expressions = [
    "2 + 3",
    "2 + 3 * 4",
    "(2 + 3) * 4",
    "10 / 2 - 3",
    "-5 + 3",
    "2 * (3 + 4) - 10 / 2",
    "3.14 * 2 * 2",
    "((1 + 2) * (3 + 4)) / 2",
];

$evaluator = new Evaluator();
foreach ($expressions as $expr) {
    $lexer = new Lexer($expr);
    $tokens = $lexer->tokenize();
    $parser = new Parser($tokens);
    $ast = $parser->parseExpr();
    $result = $evaluator->eval($ast);
    echo "$expr = $result\n";
}

echo "\n--- AST Structure ---\n";
$lexer = new Lexer("2 + 3 * 4");
$tokens = $lexer->tokenize();
$parser = new Parser($tokens);
$ast = $parser->parseExpr();
echo $evaluator->astToString($ast);

echo "\n--- Error Handling ---\n";
try {
    $lexer = new Lexer("2 / 0");
    $tokens = $lexer->tokenize();
    $parser = new Parser($tokens);
    $ast = $parser->parseExpr();
    $evaluator->eval($ast);
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

try {
    $lexer = new Lexer("2 + ");
    $tokens = $lexer->tokenize();
    $parser = new Parser($tokens);
    $parser->parseExpr();
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "=== f063 Done ===\n";
