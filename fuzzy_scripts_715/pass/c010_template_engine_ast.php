<?php
// 极度混搭: 模板引擎 + AST解析 + 词法分析 + 递归下降 + 字符串操作
echo "=== c010: Template Engine + AST + Lexer + Recursive Descent ===\n\n";

class Lexer {
    private int $pos = 0;
    private array $tokens = [];

    public const TYPE_TEXT = 'text';
    public const TYPE_VAR = 'var';
    public const TYPE_IF = 'if';
    public const TYPE_ELSE = 'else';
    public const TYPE_ENDIF = 'endif';
    public const TYPE_LOOP = 'loop';
    public const TYPE_ENDLOOP = 'endloop';
    public const TYPE_EOF = 'eof';

    public function tokenize(string $input): array {
        $this->pos = 0;
        $this->tokens = [];
        $len = strlen($input);
        $textBuffer = '';

        while ($this->pos < $len) {
            if (substr($input, $this->pos, 2) === '{{') {
                if ($textBuffer !== '') {
                    $this->tokens[] = [self::TYPE_TEXT, $textBuffer];
                    $textBuffer = '';
                }
                $this->pos += 2;
                $expr = '';
                while ($this->pos < $len && substr($input, $this->pos, 2) !== '}}') {
                    $expr .= $input[$this->pos];
                    $this->pos++;
                }
                $this->pos += 2;
                $expr = trim($expr);
                $this->tokens[] = [self::TYPE_VAR, $expr];
            } elseif (substr($input, $this->pos, 3) === '{% ') {
                if ($textBuffer !== '') {
                    $this->tokens[] = [self::TYPE_TEXT, $textBuffer];
                    $textBuffer = '';
                }
                $this->pos += 3;
                $directive = '';
                while ($this->pos < $len && substr($input, $this->pos, 3) !== ' %}') {
                    $directive .= $input[$this->pos];
                    $this->pos++;
                }
                $this->pos += 3;
                $directive = trim($directive);
                $parts = explode(' ', $directive, 2);
                $keyword = $parts[0];
                $rest = $parts[1] ?? '';
                $type = match($keyword) {
                    'if' => self::TYPE_IF,
                    'else' => self::TYPE_ELSE,
                    'endif' => self::TYPE_ENDIF,
                    'loop' => self::TYPE_LOOP,
                    'endloop' => self::TYPE_ENDLOOP,
                    default => 'unknown',
                };
                $this->tokens[] = [$type, $rest];
            } else {
                $textBuffer .= $input[$this->pos];
                $this->pos++;
            }
        }

        if ($textBuffer !== '') {
            $this->tokens[] = [self::TYPE_TEXT, $textBuffer];
        }

        $this->tokens[] = [self::TYPE_EOF, ''];
        return $this->tokens;
    }
}

class TemplateNode {
    public string $type;
    public mixed $value;
    public array $children = [];
    public ?TemplateNode $elseBranch = null;

    public function __construct(string $type, mixed $value = null) {
        $this->type = $type;
        $this->value = $value;
    }
}

class TemplateParser {
    private array $tokens;
    private int $pos = 0;

    public function __construct(array $tokens) {
        $this->tokens = $tokens;
    }

    public function parse(): TemplateNode {
        return $this->parseBlock();
    }

    private function parseBlock(string $endToken = 'eof'): TemplateNode {
        $block = new TemplateNode('block');

        while ($this->pos < count($this->tokens)) {
            $token = $this->tokens[$this->pos];

            switch ($token[0]) {
                case Lexer::TYPE_TEXT:
                    $block->children[] = new TemplateNode('text', $token[1]);
                    $this->pos++;
                    break;

                case Lexer::TYPE_VAR:
                    $block->children[] = new TemplateNode('var', $token[1]);
                    $this->pos++;
                    break;

                case Lexer::TYPE_IF:
                    $this->pos++;
                    $ifNode = new TemplateNode('if', $token[1]);
                    $ifNode->children = $this->parseBlockUntil(['else', 'endif'])->children;
                    if ($this->tokens[$this->pos][0] === Lexer::TYPE_ELSE) {
                        $this->pos++;
                        $ifNode->elseBranch = $this->parseBlockUntil(['endif']);
                    }
                    if ($this->tokens[$this->pos][0] === Lexer::TYPE_ENDIF) {
                        $this->pos++;
                    }
                    $block->children[] = $ifNode;
                    break;

                case Lexer::TYPE_LOOP:
                    $this->pos++;
                    $loopNode = new TemplateNode('loop', $token[1]);
                    $loopNode->children = $this->parseBlockUntil(['endloop'])->children;
                    if ($this->tokens[$this->pos][0] === Lexer::TYPE_ENDLOOP) {
                        $this->pos++;
                    }
                    $block->children[] = $loopNode;
                    break;

                case Lexer::TYPE_ELSE:
                case Lexer::TYPE_ENDIF:
                case Lexer::TYPE_ENDLOOP:
                case Lexer::TYPE_EOF:
                    return $block;

                default:
                    $this->pos++;
            }
        }

        return $block;
    }

    private function parseBlockUntil(array $endTokens): TemplateNode {
        return $this->parseBlock();
    }
}

class TemplateRenderer {
    private TemplateNode $ast;

    public function __construct(TemplateNode $ast) {
        $this->ast = $ast;
    }

    public function render(array $context): string {
        return $this->renderBlock($this->ast, $context);
    }

    private function renderBlock(TemplateNode $node, array $context): string {
        $output = '';
        foreach ($node->children as $child) {
            switch ($child->type) {
                case 'text':
                    $output .= $child->value;
                    break;

                case 'var':
                    $output .= $this->resolveVar($child->value, $context);
                    break;

                case 'if':
                    $cond = $this->resolveVar($child->value, $context);
                    if ($cond) {
                        $output .= $this->renderBlock($child, $context);
                    } elseif ($child->elseBranch !== null) {
                        $output .= $this->renderBlock($child->elseBranch, $context);
                    }
                    break;

                case 'loop':
                    $parts = preg_split('/\s+as\s+/', $child->value);
                    $arrName = trim($parts[0] ?? '');
                    $itemVar = trim($parts[1] ?? 'item');
                    $items = $context[$arrName] ?? [];
                    foreach ($items as $item) {
                        $localContext = $context;
                        $localContext[$itemVar] = $item;
                        $output .= $this->renderBlock($child, $localContext);
                    }
                    break;
            }
        }
        return $output;
    }

    private function resolveVar(string $expr, array $context): mixed {
        $expr = trim($expr);
        $parts = explode('.', $expr);
        $value = $context;
        foreach ($parts as $part) {
            if (is_array($value) && isset($value[$part])) {
                $value = $value[$part];
            } else {
                return '';
            }
        }
        return $value;
    }
}

// === 测试 ===

$lexer = new Lexer();

$template = <<<TPL
Hello {{ name }}!
{% if items %}
You have {{ items }} items:
{% loop items as item %}
  - {{ item }}
{% endloop %}
{% else %}
No items found.
{% endif %}
TPL;

echo "--- Tokens ---\n";
$tokens = $lexer->tokenize($template);
foreach ($tokens as $i => $t) {
    echo "  [$i] {$t[0]}: " . str_replace("\n", "\\n", substr($t[1], 0, 40)) . "\n";
}

echo "\n--- AST Render ---\n";
$parser = new TemplateParser($tokens);
$ast = $parser->parse();

$renderer = new TemplateRenderer($ast);

$context1 = [
    'name' => 'Alice',
    'items' => ['apple', 'banana', 'cherry'],
];
echo $renderer->render($context1) . "\n";

$context2 = [
    'name' => 'Bob',
    'items' => [],
];
echo $renderer->render($context2) . "\n";

// 2. 变量路径解析
echo "\n--- Nested Var Paths ---\n";
$template2 = "User: {{ user.name }} ({{ user.age }}) from {{ user.address.city }}\n";
$tokens2 = $lexer->tokenize($template2);
$ast2 = (new TemplateParser($tokens2))->parse();
$renderer2 = new TemplateRenderer($ast2);
echo $renderer2->render([
    'user' => [
        'name' => 'Charlie',
        'age' => 30,
        'address' => ['city' => 'Beijing'],
    ],
]);

// 3. 条件嵌套
echo "\n--- Nested Conditions ---\n";
$template3 = <<<TPL
{% if level == 1 %}
Level 1 access
{% if detail %}
  Detail: {{ detail }}
{% endif %}
{% else if level == 2 %}
Level 2 access
{% else %}
No access
{% endif %}
TPL;

// 简化版条件模板
$template3simple = "{% if show %}Visible: {{ msg }}{% else %}Hidden{% endif %}";
$tokens3 = $lexer->tokenize($template3simple);
$ast3 = (new TemplateParser($tokens3))->parse();
$renderer3 = new TemplateRenderer($ast3);
echo $renderer3->render(['show' => true, 'msg' => 'Hello World']) . "\n";
echo $renderer3->render(['show' => false, 'msg' => 'Hello World']) . "\n";

echo "\n=== c010 Done ===\n";
