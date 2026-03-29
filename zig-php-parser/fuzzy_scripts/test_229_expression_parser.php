<?php
function tokenize(string $expr): array {
    $tokens = [];
    $i = 0;
    $len = strlen($expr);

    while ($i < $len) {
        $char = $expr[$i];

        if (ctype_space($char)) {
            $i++;
            continue;
        }

        if (ctype_digit($char)) {
            $num = '';
            while ($i < $len && ctype_digit($expr[$i])) {
                $num .= $expr[$i++];
            }
            $tokens[] = ['type' => 'number', 'value' => (int)$num];
            continue;
        }

        if ($char === '+' || $char === '-' || $char === '*' || $char === '/' || $char === '^') {
            $tokens[] = ['type' => 'operator', 'value' => $char];
            $i++;
            continue;
        }

        if ($char === '(' || $char === ')') {
            $tokens[] = ['type' => 'paren', 'value' => $char];
            $i++;
            continue;
        }

        $i++;
    }

    return $tokens;
}

function evaluate(array $tokens): int {
    $values = [];
    $ops = [];

    foreach ($tokens as $token) {
        if ($token['type'] === 'number') {
            $values[] = $token['value'];
        } elseif ($token['type'] === 'operator') {
            while (!empty($ops) && $ops[count($ops) - 1] !== '(') {
                $values[] = $ops[count($ops) - 1];
                $ops = array_slice($ops, 0, -1);
            }
            $ops[] = $token['value'];
        } elseif ($token['type'] === 'paren') {
            if ($token['value'] === '(') {
                $ops[] = '(';
            } else {
                while (!empty($ops) && $ops[count($ops) - 1] !== '(') {
                    $values[] = $ops[count($ops) - 1];
                    $ops = array_slice($ops, 0, -1);
                }
                $ops = array_slice($ops, 0, -1);
            }
        }
    }

    while (!empty($ops)) {
        $values[] = $ops[count($ops) - 1];
        $ops = array_slice($ops, 0, -1);
    }

    $stack = [];
    foreach ($values as $v) {
        if (is_int($v)) {
            $stack[] = $v;
        } else {
            $b = array_pop($stack);
            $a = array_pop($stack);
            switch ($v) {
                case '+': $stack[] = $a + $b; break;
                case '-': $stack[] = $a - $b; break;
                case '*': $stack[] = $a * $b; break;
                case '/': $stack[] = $a / $b; break;
            }
        }
    }

    return $stack[0];
}

$tokens = tokenize("3 + 4 * 2 / (1 - 5) ^ 2");
echo count($tokens) . "\n";
echo evaluate(tokenize("3 + 4")) . "\n";
echo evaluate(tokenize("10 - 2 * 3")) . "\n";
echo "OK\n";
