<?php
// 极度混搭: 有限状态机 + 词法分析器 + Token 流 + 语法校验
echo "=== f018: FSM + Lexer + Token Stream ===\n";

class State {
    public function __construct(
        public string $name,
        public bool $isAccept = false
    ) {}
}

class FiniteStateMachine {
    private array $states = [];
    private array $transitions = [];
    private string $current;
    private string $initial;

    public function addState(string $name, bool $accept = false): self {
        $this->states[$name] = new State($name, $accept);
        if (count($this->states) === 1) {
            $this->initial = $name;
            $this->current = $name;
        }
        return $this;
    }

    public function addTransition(string $from, string $input, string $to): self {
        $this->transitions[$from][$input] = $to;
        return $this;
    }

    public function reset(): void {
        $this->current = $this->initial;
    }

    public function process(string $input): bool {
        if (!isset($this->transitions[$this->current][$input])) {
            return false;
        }
        $this->current = $this->transitions[$this->current][$input];
        return true;
    }

    public function processString(string $str): bool {
        $this->reset();
        for ($i = 0; $i < strlen($str); $i++) {
            if (!$this->process($str[$i])) return false;
        }
        return $this->isAccepting();
    }

    public function isAccepting(): bool {
        return isset($this->states[$this->current]) && $this->states[$this->current]->isAccept;
    }

    public function getCurrentState(): string { return $this->current; }
}

class Token {
    public function __construct(
        public string $type,
        public string $value,
        public int $position = 0
    ) {}

    public function __toString(): string {
        return "$this->type('$this->value')";
    }
}

class Lexer {
    private array $rules;
    private array $keywords;

    public function __construct() {
        $this->keywords = ['if', 'else', 'while', 'for', 'function', 'return', 'true', 'false', 'null'];
        $this->rules = [
            'WHITESPACE' => '/^\s+/',
            'NUMBER' => '/^\d+\.?\d*/',
            'STRING' => '/^"[^"]*"/',
            'IDENT' => '/^[a-zA-Z_]\w*/',
            'OP' => '/^[+\-*\/%=<>!&|]+/',
            'LPAREN' => '/^\(/',
            'RPAREN' => '/^\)/',
            'LBRACE' => '/^\{/',
            'RBRACE' => '/^\}/',
            'SEMICOLON' => '/^;/',
            'COMMA' => '/^,/',
        ];
    }

    public function tokenize(string $input): array {
        $tokens = [];
        $pos = 0;
        $len = strlen($input);

        while ($pos < $len) {
            $matched = false;
            foreach ($this->rules as $type => $pattern) {
                $subject = substr($input, $pos);
                if (preg_match($pattern, $subject, $m)) {
                    $value = $m[0];
                    if ($type !== 'WHITESPACE') {
                        if ($type === 'IDENT' && in_array(strtolower($value), $this->keywords)) {
                            $type = 'KEYWORD';
                        }
                        $tokens[] = new Token($type, $value, $pos);
                    }
                    $pos += strlen($value);
                    $matched = true;
                    break;
                }
            }
            if (!$matched) {
                $tokens[] = new Token('UNKNOWN', $input[$pos], $pos);
                $pos++;
            }
        }
        return $tokens;
    }
}

class SimpleParser {
    private array $tokens;
    private int $pos = 0;

    public function __construct(array $tokens) {
        $this->tokens = $tokens;
    }

    private function peek(): ?Token {
        return $this->tokens[$this->pos] ?? null;
    }

    private function consume(): ?Token {
        return $this->tokens[$this->pos++] ?? null;
    }

    private function expect(string $type): Token {
        $token = $this->consume();
        if ($token === null || $token->type !== $type) {
            throw new RuntimeException(
                "Expected $type but got " . ($token?->type ?? 'EOF') .
                " at position " . ($token?->position ?? 'end')
            );
        }
        return $token;
    }

    public function parseExpression(): array {
        $left = $this->consume();
        if ($left === null) throw new RuntimeException("Unexpected EOF");

        if ($left->type === 'NUMBER') {
            $next = $this->peek();
            if ($next !== null && $next->type === 'OP') {
                $op = $this->consume();
                $right = $this->parseExpression();
                return ['type' => 'binary', 'op' => $op->value, 'left' => $left->value, 'right' => $right];
            }
            return ['type' => 'number', 'value' => $left->value];
        }
        if ($left->type === 'IDENT') {
            return ['type' => 'identifier', 'value' => $left->value];
        }
        if ($left->type === 'LPAREN') {
            $inner = $this->parseExpression();
            $this->expect('RPAREN');
            return ['type' => 'paren', 'value' => $inner];
        }
        throw new RuntimeException("Unexpected token: $left");
    }
}

// === 测试 ===
echo "--- FSM: Binary numbers ending in 0 ---\n";
$fsm = new FiniteStateMachine();
$fsm->addState('q0', false)  // 初始状态
    ->addState('q1', true);  // 接受状态（以0结尾）
$fsm->addTransition('q0', '0', 'q1');
$fsm->addTransition('q0', '1', 'q0');
$fsm->addTransition('q1', '0', 'q1');
$fsm->addTransition('q1', '1', 'q0');

$testStrings = ['0', '1', '10', '100', '101', '110', '1100', '1111'];
foreach ($testStrings as $s) {
    $result = $fsm->processString($s);
    echo "  '$s': " . var_export($result, true) . "\n";
}

echo "\n--- Lexer ---\n";
$lexer = new Lexer();
$code = 'if (x > 10) { return x + 5; } else { return 0; }';
$tokens = $lexer->tokenize($code);

echo "Input: $code\n";
echo "Tokens (" . count($tokens) . "):\n";
foreach ($tokens as $i => $t) {
    echo "  [" . sprintf('%02d', $i) . "] $t\n";
}

echo "\n--- Simple Parser: 3 + 5 * 2 ---\n";
$exprTokens = $lexer->tokenize('3 + 5');
$parser = new SimpleParser($exprTokens);
$ast = $parser->parseExpression();
echo "AST: " . json_encode($ast) . "\n";

$exprTokens2 = $lexer->tokenize('(42)');
$parser2 = new SimpleParser($exprTokens2);
$ast2 = $parser2->parseExpression();
echo "AST (paren): " . json_encode($ast2) . "\n";

// 统计 token 类型
$tokenTypes = [];
foreach ($tokens as $t) {
    $tokenTypes[$t->type] = ($tokenTypes[$t->type] ?? 0) + 1;
}
echo "\nToken type counts: " . json_encode($tokenTypes) . "\n";

echo "=== f018 Done ===\n";
