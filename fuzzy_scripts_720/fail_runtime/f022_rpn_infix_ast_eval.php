<?php
// 极度混搭: RPN表达式求值 + 中缀转后缀 + AST构建 + 变量绑定 + 函数调用
echo "=== f022: RPN + InfixToPostfix + AST + Eval ===\n";

class RPN {
    private array $stack = [];
    private array $operators = [
        '+' => ['prec' => 1, 'assoc' => 'L', 'fn' => 'add'],
        '-' => ['prec' => 1, 'assoc' => 'L', 'fn' => 'sub'],
        '*' => ['prec' => 2, 'assoc' => 'L', 'fn' => 'mul'],
        '/' => ['prec' => 2, 'assoc' => 'L', 'fn' => 'div'],
        '%' => ['prec' => 2, 'assoc' => 'L', 'fn' => 'mod'],
        '^' => ['prec' => 3, 'assoc' => 'R', 'fn' => 'pow'],
    ];

    public static function evaluate(array $tokens, array $vars = []): float {
        $stack = [];
        foreach ($tokens as $token) {
            if (is_numeric($token)) {
                $stack[] = (float)$token;
            } elseif (array_key_exists($token, $vars)) {
                $stack[] = (float)$vars[$token];
            } elseif (in_array($token, ['+', '-', '*', '/', '%', '^'])) {
                $b = array_pop($stack);
                $a = array_pop($stack);
                $stack[] = match($token) {
                    '+' => $a + $b,
                    '-' => $a - $b,
                    '*' => $a * $b,
                    '/' => $b == 0 ? 0 : $a / $b,
                    '%' => $b == 0 ? 0 : fmod($a, $b),
                    '^' => pow($a, $b),
                };
            }
        }
        return $stack[0] ?? 0;
    }

    public static function infixToPostfix(string $expr): array {
        $output = [];
        $stack = [];
        $precedence = ['+' => 1, '-' => 1, '*' => 2, '/' => 2, '%' => 2, '^' => 3];
        $rightAssoc = ['^'];

        $tokens = self::tokenize($expr);
        foreach ($tokens as $token) {
            if (is_numeric($token) || preg_match('/^[a-zA-Z_]\w*$/', $token)) {
                $output[] = $token;
            } elseif ($token === '(') {
                $stack[] = $token;
            } elseif ($token === ')') {
                while (!empty($stack) && end($stack) !== '(') {
                    $output[] = array_pop($stack);
                }
                array_pop($stack); // 弹出 '('
            } elseif (isset($precedence[$token])) {
                while (!empty($stack) && end($stack) !== '(') {
                    $top = end($stack);
                    if (!isset($precedence[$top])) break;
                    if (in_array($token, $rightAssoc)) {
                        if ($precedence[$top] > $precedence[$token]) {
                            $output[] = array_pop($stack);
                        } else {
                            break;
                        }
                    } else {
                        if ($precedence[$top] >= $precedence[$token]) {
                            $output[] = array_pop($stack);
                        } else {
                            break;
                        }
                    }
                }
                $stack[] = $token;
            }
        }
        while (!empty($stack)) {
            $output[] = array_pop($stack);
        }
        return $output;
    }

    private static function tokenize(string $expr): array {
        $tokens = [];
        $i = 0;
        $len = strlen($expr);
        while ($i < $len) {
            $char = $expr[$i];
            if (ctype_space($char)) { $i++; continue; }
            if (is_numeric($char) || ($char === '.' && $i + 1 < $len && is_numeric($expr[$i+1]))) {
                $num = '';
                while ($i < $len && (is_numeric($expr[$i]) || $expr[$i] === '.')) {
                    $num .= $expr[$i++];
                }
                $tokens[] = $num;
                continue;
            }
            if (ctype_alpha($char) || $char === '_') {
                $ident = '';
                while ($i < $len && (ctype_alnum($expr[$i]) || $expr[$i] === '_')) {
                    $ident .= $expr[$i++];
                }
                $tokens[] = $ident;
                continue;
            }
            if (in_array($char, ['+', '-', '*', '/', '%', '^', '(', ')'])) {
                $tokens[] = $char;
                $i++;
                continue;
            }
            $i++;
        }
        return $tokens;
    }
}

class ASTNode {
    public function __construct(
        public string $type,
        public mixed $value = null,
        public ?ASTNode $left = null,
        public ?ASTNode $right = null
    ) {}

    public function eval(array $vars = []): float {
        return match($this->type) {
            'number' => (float)$this->value,
            'variable' => (float)($vars[$this->value] ?? 0),
            'binary' => match($this->value) {
                '+' => $this->left->eval($vars) + $this->right->eval($vars),
                '-' => $this->left->eval($vars) - $this->right->eval($vars),
                '*' => $this->left->eval($vars) * $this->right->eval($vars),
                '/' => $this->right->eval($vars) == 0 ? 0 : $this->left->eval($vars) / $this->right->eval($vars),
                '^' => pow($this->left->eval($vars), $this->right->eval($vars)),
                default => 0,
            },
            default => 0,
        };
    }

    public function toString(): string {
        return match($this->type) {
            'number' => (string)$this->value,
            'variable' => $this->value,
            'binary' => "({$this->left->toString()} {$this->value} {$this->right->toString()})",
            default => '?',
        };
    }
}

class ExpressionParser {
    private array $tokens;
    private int $pos = 0;

    public function __construct(string $expr) {
        $this->tokens = RPN::infixToPostfix($expr);
    }

    public static function parse(string $expr): ASTNode {
        $tokens = RPN::infixToPostfix($expr);
        $stack = [];
        foreach ($tokens as $token) {
            if (is_numeric($token)) {
                $stack[] = new ASTNode('number', $token);
            } elseif (preg_match('/^[a-zA-Z_]\w*$/', $token)) {
                $stack[] = new ASTNode('variable', $token);
            } else {
                $right = array_pop($stack);
                $left = array_pop($stack);
                $stack[] = new ASTNode('binary', $token, $left, $right);
            }
        }
        return $stack[0] ?? new ASTNode('number', 0);
    }
}

// === 测试 ===
echo "--- RPN Evaluation ---\n";
$rpn1 = [3, 4, '+']; // 3 + 4 = 7
$rpn2 = [3, 4, 2, '*', '+']; // 3 + 4*2 = 11
$rpn3 = [10, 2, '/']; // 10/2 = 5
$rpn4 = [2, 3, '^']; // 2^3 = 8
$rpn5 = [5, 1, 2, '+', 4, '*', '+', 3, '-']; // 5 + (1+2)*4 - 3 = 14

echo "3 4 + = " . RPN::evaluate($rpn1) . "\n";
echo "3 4 2 * + = " . RPN::evaluate($rpn2) . "\n";
echo "10 2 / = " . RPN::evaluate($rpn3) . "\n";
echo "2 3 ^ = " . RPN::evaluate($rpn4) . "\n";
echo "5 1 2 + 4 * + 3 - = " . RPN::evaluate($rpn5) . "\n";

echo "\n--- Infix to Postfix ---\n";
$exprs = ['3 + 4', '3 + 4 * 2', '(3 + 4) * 2', '2 ^ 3 ^ 2', '10 - 2 - 3'];
foreach ($exprs as $expr) {
    $postfix = RPN::infixToPostfix($expr);
    echo "  $expr → " . implode(' ', $postfix) . " = " . RPN::evaluate($postfix) . "\n";
}

echo "\n--- Variable Binding ---\n";
$expr = 'x + y * 2';
$postfix = RPN::infixToPostfix($expr);
echo "Expression: $expr\n";
echo "Postfix: " . implode(' ', $postfix) . "\n";
$vars1 = ['x' => 5, 'y' => 3];
echo "x=5, y=3: " . RPN::evaluate($postfix, $vars1) . "\n";
$vars2 = ['x' => 10, 'y' => 4];
echo "x=10, y=4: " . RPN::evaluate($postfix, $vars2) . "\n";

echo "\n--- AST ---\n";
$ast = ExpressionParser::parse('3 + 4 * 2');
echo "AST: " . $ast->toString() . "\n";
echo "Eval: " . $ast->eval() . "\n";

$ast2 = ExpressionParser::parse('x ^ 2 + y ^ 2');
echo "AST2: " . $ast2->toString() . "\n";
echo "Eval x=3,y=4: " . $ast2->eval(['x' => 3, 'y' => 4]) . "\n";

echo "\n--- Complex Expressions ---\n";
$complex = '(a + b) * (c - d) / e';
$postfix = RPN::infixToPostfix($complex);
$vars = ['a' => 10, 'b' => 5, 'c' => 8, 'd' => 3, 'e' => 5];
echo "($complex) with a=10,b=5,c=8,d=3,e=5: " . RPN::evaluate($postfix, $vars) . "\n";

$complex2 = '2 ^ 10 % 100';
$postfix2 = RPN::infixToPostfix($complex2);
echo "2^10 % 100 = " . RPN::evaluate($postfix2) . "\n";

echo "=== f022 Done ===\n";
