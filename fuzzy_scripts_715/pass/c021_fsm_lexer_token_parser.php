<?php
// 极度混搭: 有限状态自动机 + 正则模拟 + 词法分析 + Token生成 + 语法检查
echo "=== c021: FSM + Lexer + Token + Syntax Check ===\n\n";

class State {
    public string $name;
    public array $transitions = [];
    public bool $isAccepting;

    public function __construct(string $name, bool $isAccepting = false) {
        $this->name = $name;
        $this->isAccepting = $isAccepting;
    }

    public function addTransition(string $input, string $targetState): void {
        $this->transitions[$input] = $targetState;
    }
}

class FiniteStateMachine {
    private array $states = [];
    private string $currentState;
    private string $startState;
    private array $history = [];

    public function __construct(string $startState) {
        $this->startState = $startState;
        $this->currentState = $startState;
        $this->states[$startState] = new State($startState);
    }

    public function addState(string $name, bool $isAccepting = false): self {
        $this->states[$name] = new State($name, $isAccepting);
        return $this;
    }

    public function addTransition(string $from, string $input, string $to): self {
        if (!isset($this->states[$from])) $this->addState($from);
        if (!isset($this->states[$to])) $this->addState($to);
        $this->states[$from]->addTransition($input, $to);
        return $this;
    }

    public function feed(string $input): bool {
        $state = $this->states[$this->currentState] ?? null;
        if ($state === null) return false;
        $nextState = $state->transitions[$input] ?? null;
        if ($nextState === null) {
            $this->history[] = ['input' => $input, 'from' => $this->currentState, 'to' => 'REJECT'];
            return false;
        }
        $this->history[] = ['input' => $input, 'from' => $this->currentState, 'to' => $nextState];
        $this->currentState = $nextState;
        return true;
    }

    public function feedString(string $input): bool {
        $len = strlen($input);
        for ($i = 0; $i < $len; $i++) {
            if (!$this->feed($input[$i])) return false;
        }
        return $this->isAccepting();
    }

    public function isAccepting(): bool {
        return $this->states[$this->currentState]->isAccepting ?? false;
    }

    public function getCurrentState(): string {
        return $this->currentState;
    }

    public function reset(): void {
        $this->currentState = $this->startState;
        $this->history = [];
    }

    public function getHistory(): array {
        return $this->history;
    }
}

class Token {
    public string $type;
    public string $value;
    public int $position;

    public function __construct(string $type, string $value, int $position) {
        $this->type = $type;
        $this->value = $value;
        $this->position = $position;
    }

    public function __toString(): string {
        return "$this->type('$this->value')@$this->position";
    }
}

class SimpleLexer {
    private array $rules = [];

    public function addRule(string $type, string $pattern): self {
        $this->rules[] = ['type' => $type, 'pattern' => '~^(' . $pattern . ')~'];
        return $this;
    }

    public function tokenize(string $input): array {
        $tokens = [];
        $pos = 0;
        $len = strlen($input);

        while ($pos < $len) {
            // Skip whitespace
            if (ctype_space($input[$pos])) {
                $pos++;
                continue;
            }

            $matched = false;
            foreach ($this->rules as $rule) {
                $subject = substr($input, $pos);
                if (preg_match($rule['pattern'], $subject, $m)) {
                    $tokens[] = new Token($rule['type'], $m[1], $pos);
                    $pos += strlen($m[1]);
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

    public function parseExpression(): ?array {
        if ($this->peek() === null) return null;

        $left = $this->parseTerm();
        if ($left === null) return null;

        while ($this->peek() !== null && $this->peek()->type === 'OP') {
            $op = $this->consume();
            $right = $this->parseTerm();
            if ($right === null) return null;
            $left = ['type' => 'binary', 'op' => $op->value, 'left' => $left, 'right' => $right];
        }

        return $left;
    }

    private function parseTerm(): ?array {
        $token = $this->peek();
        if ($token === null) return null;

        if ($token->type === 'NUMBER') {
            $this->consume();
            return ['type' => 'number', 'value' => (float)$token->value];
        }

        if ($token->type === 'LPAREN') {
            $this->consume();
            $expr = $this->parseExpression();
            if ($this->peek() !== null && $this->peek()->type === 'RPAREN') {
                $this->consume();
            }
            return $expr;
        }

        return null;
    }

    private function peek(): ?Token {
        return $this->tokens[$this->pos] ?? null;
    }

    private function consume(): Token {
        return $this->tokens[$this->pos++];
    }
}

// === 测试 ===

echo "--- FSM: Binary Number Acceptor ---\n";
$fsm = new FiniteStateMachine('start');
$fsm->addState('start');
$fsm->addState('zero', true);
$fsm->addState('ones', true);
$fsm->addTransition('start', '0', 'zero');
$fsm->addTransition('start', '1', 'ones');
$fsm->addTransition('zero', '0', 'zero');
$fsm->addTransition('zero', '1', 'ones');
$fsm->addTransition('ones', '0', 'zero');
$fsm->addTransition('ones', '1', 'ones');

$tests = ['0', '1', '10', '101', '110', '111', '1010', '10101'];
foreach ($tests as $bin) {
    $fsm->reset();
    $accepted = $fsm->feedString($bin);
    echo "  '$bin': " . ($accepted ? "ACCEPT" : "REJECT") . " (state: " . $fsm->getCurrentState() . ")\n";
}

echo "\n--- FSM: Even Parity Checker ---\n";
$parity = new FiniteStateMachine('even');
$parity->addState('even', true);
$parity->addState('odd');
$parity->addTransition('even', '1', 'odd');
$parity->addTransition('even', '0', 'even');
$parity->addTransition('odd', '1', 'even');
$parity->addTransition('odd', '0', 'odd');

$tests2 = ['0', '1', '00', '01', '10', '11', '000', '111', '1010'];
foreach ($tests2 as $s) {
    $parity->reset();
    $parity->feedString($s);
    echo "  '$s': " . ($parity->isAccepting() ? "EVEN" : "ODD") . "\n";
}

echo "\n--- Simple Lexer ---\n";
$lexer = new SimpleLexer();
$lexer->addRule('NUMBER', '\d+\.?\d*')
    ->addRule('OP', '[+\-*/]')
    ->addRule('LPAREN', '\(')
    ->addRule('RPAREN', '\)')
    ->addRule('IDENT', '[a-zA-Z_]\w*');

$expression = "3 + 5 * (10 - 2) / 4";
$tokens = $lexer->tokenize($expression);
echo "Expression: $expression\n";
echo "Tokens:\n";
foreach ($tokens as $t) {
    echo "  $t\n";
}

echo "\n--- Simple Parser (arithmetic) ---\n";
$parser = new SimpleParser($tokens);
$ast = $parser->parseExpression();
if ($ast !== null) {
    echo "AST: " . json_encode($ast) . "\n";
}

echo "\n--- FSM History ---\n";
$fsm->reset();
$fsm->feedString('10110');
$hist = $fsm->getHistory();
foreach ($hist as $h) {
    echo "  input={$h['input']} {$h['from']}->{$h['to']}\n";
}

echo "\n=== c021 Done ===\n";
