<?php
// 极度混搭: 表达式求值 + 逆波兰 + 运算符优先 + 变量绑定 + 求值栈
echo "=== c028: Expression Eval + RPN + OpPrecedence + VarBinding ===\n\n";

class ExpressionParser {
    private array $operators = [
        '+' => ['prec' => 1, 'assoc' => 'L'],
        '-' => ['prec' => 1, 'assoc' => 'L'],
        '*' => ['prec' => 2, 'assoc' => 'L'],
        '/' => ['prec' => 2, 'assoc' => 'L'],
        '%' => ['prec' => 2, 'assoc' => 'L'],
        '^' => ['prec' => 3, 'assoc' => 'R'],
    ];

    public function tokenize(string $expr): array {
        $tokens = [];
        $len = strlen($expr);
        $i = 0;

        while ($i < $len) {
            $c = $expr[$i];
            if (ctype_space($c)) { $i++; continue; }

            if ($c === '(' || $c === ')') {
                $tokens[] = ['type' => 'paren', 'value' => $c];
                $i++;
            } elseif ($c === '+' || $c === '-' || $c === '*' || $c === '/' || $c === '%' || $c === '^') {
                // Check if '-' is unary (negative number)
                if ($c === '-' && (empty($tokens) || $tokens[count($tokens)-1]['type'] === 'op' || $tokens[count($tokens)-1]['value'] === '(')) {
                    // Parse negative number
                    $num = '-';
                    $i++;
                    while ($i < $len && (ctype_digit($expr[$i]) || $expr[$i] === '.')) {
                        $num .= $expr[$i];
                        $i++;
                    }
                    $tokens[] = ['type' => 'number', 'value' => (float)$num];
                } else {
                    $tokens[] = ['type' => 'op', 'value' => $c];
                    $i++;
                }
            } elseif (ctype_digit($c) || $c === '.') {
                $num = '';
                while ($i < $len && (ctype_digit($expr[$i]) || $expr[$i] === '.')) {
                    $num .= $expr[$i];
                    $i++;
                }
                $tokens[] = ['type' => 'number', 'value' => (float)$num];
            } elseif (ctype_alpha($c)) {
                $var = '';
                while ($i < $len && (ctype_alnum($expr[$i]) || $expr[$i] === '_')) {
                    $var .= $expr[$i];
                    $i++;
                }
                $tokens[] = ['type' => 'var', 'value' => $var];
            } else {
                $i++;
            }
        }

        return $tokens;
    }

    public function toRPN(array $tokens): array {
        $output = [];
        $stack = [];

        foreach ($tokens as $token) {
            if ($token['type'] === 'number' || $token['type'] === 'var') {
                $output[] = $token;
            } elseif ($token['type'] === 'op') {
                while (!empty($stack)) {
                    $top = end($stack);
                    if ($top['type'] === 'op') {
                        $prec = $this->operators[$token['value']]['prec'];
                        $topPrec = $this->operators[$top['value']]['prec'];
                        $assoc = $this->operators[$token['value']]['assoc'];
                        if (($assoc === 'L' && $prec <= $topPrec) || ($assoc === 'R' && $prec < $topPrec)) {
                            $output[] = array_pop($stack);
                            continue;
                        }
                    }
                    break;
                }
                $stack[] = $token;
            } elseif ($token['value'] === '(') {
                $stack[] = $token;
            } elseif ($token['value'] === ')') {
                while (!empty($stack) && end($stack)['value'] !== '(') {
                    $output[] = array_pop($stack);
                }
                if (!empty($stack)) {
                    array_pop($stack); // Remove '('
                }
            }
        }

        while (!empty($stack)) {
            $output[] = array_pop($stack);
        }

        return $output;
    }

    public function evaluateRPN(array $rpn, array $variables = []): float {
        $stack = [];
        foreach ($rpn as $token) {
            if ($token['type'] === 'number') {
                $stack[] = $token['value'];
            } elseif ($token['type'] === 'var') {
                if (!isset($variables[$token['value']])) {
                    throw new RuntimeException("Undefined variable: {$token['value']}");
                }
                $stack[] = (float)$variables[$token['value']];
            } elseif ($token['type'] === 'op') {
                $b = array_pop($stack);
                $a = array_pop($stack);
                $stack[] = match($token['value']) {
                    '+' => $a + $b,
                    '-' => $a - $b,
                    '*' => $a * $b,
                    '/' => $a / $b,
                    '%' => fmod($a, $b),
                    '^' => pow($a, $b),
                    default => throw new RuntimeException("Unknown operator: {$token['value']}"),
                };
            }
        }
        return $stack[0] ?? 0;
    }

    public function evaluate(string $expr, array $variables = []): float {
        $tokens = $this->tokenize($expr);
        $rpn = $this->toRPN($tokens);
        return $this->evaluateRPN($rpn, $variables);
    }
}

// === 测试 ===

$parser = new ExpressionParser();

echo "--- Tokenization ---\n";
$expr = "3 + 5 * 2 - 8 / 4";
$tokens = $parser->tokenize($expr);
echo "Expression: $expr\n";
echo "Tokens: ";
foreach ($tokens as $t) {
    echo "{$t['type']}({$t['value']}) ";
}
echo "\n";

echo "\n--- RPN Conversion ---\n";
$rpn = $parser->toRPN($tokens);
echo "RPN: ";
foreach ($rpn as $t) {
    echo "{$t['value']} ";
}
echo "\n";

echo "\n--- Basic Evaluation ---\n";
$expressions = [
    "1 + 2" => 3,
    "3 * 4 + 2" => 14,
    "3 + 4 * 2" => 11,
    "(3 + 4) * 2" => 14,
    "2 ^ 3" => 8,
    "2 ^ 3 ^ 2" => 512,
    "10 - 3 - 2" => 5,
    "100 / 4 / 5" => 5,
    "-5 + 3" => -2,
    "10 % 3" => 1,
];

foreach ($expressions as $expr => $expected) {
    $result = $parser->evaluate($expr);
    $status = abs($result - $expected) < 0.001 ? "OK" : "FAIL";
    echo "  $expr = $result (expected $expected) [$status]\n";
}

echo "\n--- Variable Binding ---\n";
$varExpr = "x * y + z";
$vars = ['x' => 3, 'y' => 4, 'z' => 2];
$result = $parser->evaluate($varExpr, $vars);
echo "$varExpr with x=3,y=4,z=2 = $result\n";

$varExpr2 = "a ^ 2 + b ^ 2";
$vars2 = ['a' => 3, 'b' => 4];
$result2 = $parser->evaluate($varExpr2, $vars2);
echo "$varExpr2 with a=3,b=4 = $result2 (expected 25)\n";

echo "\n--- Complex Expressions ---\n";
$complex = [
    "2 * (3 + 4) * (5 - 2)" => 42,
    "100 - 20 * 3 + 10" => 50,
    "((2 + 3) * 4) / 5" => 4,
    "3 + 4 * 2 / (1 - 5) ^ 2" => 3.25,
    "-2 * -3" => 6,
];

foreach ($complex as $expr => $expected) {
    $result = $parser->evaluate($expr);
    $status = abs($result - $expected) < 0.01 ? "OK" : "FAIL";
    echo "  $expr = $result (expected $expected) [$status]\n";
}

echo "\n--- Error Handling ---\n";
try {
    $parser->evaluate("x + 5", []);
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "\n--- RPN Stack Trace ---\n";
$rpn = $parser->toRPN($parser->tokenize("(a + b) * (c - d)"));
echo "RPN for (a+b)*(c-d): ";
foreach ($rpn as $t) {
    echo "{$t['value']} ";
}
echo "\n";
$result = $parser->evaluateRPN($rpn, ['a' => 10, 'b' => 5, 'c' => 8, 'd' => 3]);
echo "Result with a=10,b=5,c=8,d=3: $result\n";

echo "\n=== c028 Done ===\n";
