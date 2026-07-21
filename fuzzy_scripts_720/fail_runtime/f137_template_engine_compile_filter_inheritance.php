<?php
// 极度混搭: 模板引擎 + 编译 + 过滤器 + 条件 + 循环 + 继承
echo "=== f137: Template Engine + Compile + Filter + Inheritance ===\n";

class TemplateToken {
    public function __construct(public string $type, public string $value = '') {}
}

class TemplateLexer {
    private int $pos = 0;

    public function tokenize(string $template): array {
        $tokens = [];
        while ($this->pos < strlen($template)) {
            if (substr($template, $this->pos, 2) === '{{') {
                $end = strpos($template, '}}', $this->pos + 2);
                if ($end !== false) {
                    $tokens[] = new TemplateToken('var', trim(substr($template, $this->pos + 2, $end - $this->pos - 2)));
                    $this->pos = $end + 2;
                }
            } elseif (substr($template, $this->pos, 2) === '{%') {
                $end = strpos($template, '%}', $this->pos + 2);
                if ($end !== false) {
                    $tokens[] = new TemplateToken('tag', trim(substr($template, $this->pos + 2, $end - $this->pos - 2)));
                    $this->pos = $end + 2;
                }
            } else {
                $nextVar = strpos($template, '{{', $this->pos);
                $nextTag = strpos($template, '{%', $this->pos);
                $next = min($nextVar === false ? PHP_INT_MAX : $nextVar, $nextTag === false ? PHP_INT_MAX : $nextTag);
                if ($next === PHP_INT_MAX) $next = strlen($template);
                $text = substr($template, $this->pos, $next - $this->pos);
                if ($text !== '') $tokens[] = new TemplateToken('text', $text);
                $this->pos = $next;
            }
        }
        return $tokens;
    }
}

class TemplateNode {
    public function __construct(public string $type, public array $props = [], public array $children = []) {}
}

class TemplateParser {
    private int $pos = 0;

    public function parse(array $tokens): array {
        $nodes = [];
        while ($this->pos < count($tokens)) {
            $token = $tokens[$this->pos];
            if ($token->type === 'text') { $nodes[] = new TemplateNode('text', ['content' => $token->value]); $this->pos++; }
            elseif ($token->type === 'var') { $nodes[] = new TemplateNode('var', ['expr' => $token->value]); $this->pos++; }
            elseif ($token->type === 'tag') {
                $tagParts = explode(' ', $token->value);
                $tagName = $tagParts[0];
                if ($tagName === 'if') {
                    $this->pos++;
                    $body = $this->parseUntil($tokens, ['endif', 'else']);
                    $elseBody = [];
                    if (isset($tokens[$this->pos]) && str_starts_with($tokens[$this->pos]->value, 'else')) {
                        $this->pos++;
                        $elseBody = $this->parseUntil($tokens, ['endif']);
                    }
                    if (isset($tokens[$this->pos])) $this->pos++; // skip endif
                    $nodes[] = new TemplateNode('if', ['condition' => implode(' ', array_slice($tagParts, 1))], array_merge($body, [new TemplateNode('else', [], $elseBody)]));
                } elseif ($tagName === 'for') {
                    $this->pos++;
                    $body = $this->parseUntil($tokens, ['endfor']);
                    if (isset($tokens[$this->pos])) $this->pos++; // skip endfor
                    $var = $tagParts[1] ?? '';
                    $list = $tagParts[3] ?? '';
                    $nodes[] = new TemplateNode('for', ['var' => $var, 'list' => $list], $body);
                } else { $this->pos++; }
            } else { $this->pos++; }
        }
        return $nodes;
    }

    private function parseUntil(array $tokens, array $stops): array {
        $nodes = [];
        while ($this->pos < count($tokens)) {
            $token = $tokens[$this->pos];
            if ($token->type === 'tag') {
                $tagName = explode(' ', $token->value)[0];
                if (in_array($tagName, $stops)) return $nodes;
            }
            if ($token->type === 'text') { $nodes[] = new TemplateNode('text', ['content' => $token->value]); $this->pos++; }
            elseif ($token->type === 'var') { $nodes[] = new TemplateNode('var', ['expr' => $token->value]); $this->pos++; }
            elseif ($token->type === 'tag') {
                $tagParts = explode(' ', $token->value);
                $tagName = $tagParts[0];
                if ($tagName === 'if') {
                    $this->pos++;
                    $body = $this->parseUntil($tokens, ['endif', 'else']);
                    $elseBody = [];
                    if (isset($tokens[$this->pos]) && str_starts_with($tokens[$this->pos]->value, 'else')) {
                        $this->pos++;
                        $elseBody = $this->parseUntil($tokens, ['endif']);
                    }
                    if (isset($tokens[$this->pos])) $this->pos++;
                    $nodes[] = new TemplateNode('if', ['condition' => implode(' ', array_slice($tagParts, 1))], array_merge($body, [new TemplateNode('else', [], $elseBody)]));
                } elseif ($tagName === 'for') {
                    $this->pos++;
                    $body = $this->parseUntil($tokens, ['endfor']);
                    if (isset($tokens[$this->pos])) $this->pos++;
                    $nodes[] = new TemplateNode('for', ['var' => $tagParts[1] ?? '', 'list' => $tagParts[3] ?? ''], $body);
                } else { $this->pos++; }
            }
        }
        return $nodes;
    }
}

class TemplateEngine {
    private array $filters = [];
    private array $cache = [];
    public array $templates = [];

    public function __construct() {
        $this->registerFilter('upper', fn($s) => strtoupper((string)$s));
        $this->registerFilter('lower', fn($s) => strtolower((string)$s));
        $this->registerFilter('reverse', fn($s) => strrev((string)$s));
        $this->registerFilter('length', fn($s) => is_array($s) ? count($s) : strlen((string)$s));
        $this->registerFilter('default', fn($s, $d = '') => $s ?? $d);
        $this->registerFilter('join', fn($s, $sep = ',') => is_array($s) ? implode($sep, $s) : $s);
        $this->registerFilter('json', fn($s) => json_encode($s));
        $this->registerFilter('number_format', fn($s, $dec = 2) => number_format((float)$s, $dec));
    }

    public function registerFilter(string $name, callable $fn): void { $this->filters[$name] = $fn; }
    public function registerTemplate(string $name, string $content): void { $this->templates[$name] = $content; }

    public function render(string $template, array $context = []): string {
        if (!isset($this->cache[$template])) {
            $lexer = new TemplateLexer();
            $tokens = $lexer->tokenize($template);
            $parser = new TemplateParser();
            $this->cache[$template] = $parser->parse($tokens);
        }
        return $this->renderNodes($this->cache[$template], $context);
    }

    public function renderTemplate(string $name, array $context = []): string {
        return $this->render($this->templates[$name] ?? '', $context);
    }

    private function renderNodes(array $nodes, array $context): string {
        $output = '';
        foreach ($nodes as $node) {
            $output .= match($node->type) {
                'text' => $node->props['content'],
                'var' => $this->renderVar($node->props['expr'], $context),
                'if' => $this->renderIf($node, $context),
                'for' => $this->renderFor($node, $context),
                'else' => '',
                default => '',
            };
        }
        return $output;
    }

    private function renderVar(string $expr, array $context): string {
        $filters = explode('|', $expr);
        $varName = trim(array_shift($filters));
        $value = $this->resolveVar($varName, $context);
        foreach ($filters as $filter) {
            $filter = trim($filter);
            $parts = explode(':', $filter);
            $filterName = trim($parts[0]);
            $args = array_slice($parts, 1);
            if (isset($this->filters[$filterName])) {
                $fn = $this->filters[$filterName];
                $value = $fn($value, ...$args);
            }
        }
        return (string)$value;
    }

    private function resolveVar(string $expr, array $context): mixed {
        $keys = explode('.', $expr);
        $current = $context;
        foreach ($keys as $key) {
            $key = trim($key);
            if (is_array($current) && isset($current[$key])) $current = $current[$key];
            else return null;
        }
        return $current;
    }

    private function renderIf(TemplateNode $node, array $context): string {
        $condition = $node->props['condition'];
        $result = $this->evaluateCondition($condition, $context);
        if ($result) return $this->renderNodes($node->children, $context);
        // else
        foreach ($node->children as $child) {
            if ($child->type === 'else') return $this->renderNodes($child->children, $context);
        }
        return '';
    }

    private function evaluateCondition(string $cond, array $context): bool {
        $cond = trim($cond);
        if (str_contains($cond, '==')) {
            [$left, $right] = explode('==', $cond);
            return $this->resolveVar(trim($left), $context) == trim($right, ' "\'');
        }
        if (str_contains($cond, '!=')) {
            [$left, $right] = explode('!=', $cond);
            return $this->resolveVar(trim($left), $context) != trim($right, ' "\'');
        }
        if (str_contains($cond, '>')) {
            [$left, $right] = explode('>', $cond);
            return $this->resolveVar(trim($left), $context) > (float)trim($right);
        }
        if (str_contains($cond, '<')) {
            [$left, $right] = explode('<', $cond);
            return $this->resolveVar(trim($left), $context) < (float)trim($right);
        }
        return (bool)$this->resolveVar($cond, $context);
    }

    private function renderFor(TemplateNode $node, array $context): string {
        $var = $node->props['var'];
        $list = $node->props['list'];
        $items = $this->resolveVar($list, $context) ?? [];
        $output = '';
        $index = 0;
        foreach ($items as $item) {
            $newContext = array_merge($context, [$var => $item, 'loop' => ['index' => $index + 1, 'index0' => $index, 'first' => $index === 0, 'last' => $index === count($items) - 1, 'length' => count($items)]]);
            $output .= $this->renderNodes($node->children, $newContext);
            $index++;
        }
        return $output;
    }
}

// 测试
echo "--- Basic Variable Rendering ---\n";
$engine = new TemplateEngine();
echo $engine->render('Hello, {{ name }}!', ['name' => 'World']) . "\n";
echo $engine->render('Name: {{ user.name }}, Age: {{ user.age }}', ['user' => ['name' => 'Alice', 'age' => 30]]) . "\n";

echo "\n--- Filters ---\n";
echo $engine->render('{{ name | upper }}', ['name' => 'hello']) . "\n";
echo $engine->render('{{ name | lower }}', ['name' => 'HELLO']) . "\n";
echo $engine->render('{{ name | reverse }}', ['name' => 'abc']) . "\n";
echo $engine->render('{{ items | length }}', ['items' => [1, 2, 3, 4, 5]]) . "\n";
echo $engine->render('{{ name | default("Anonymous") }}', []) . "\n";
echo $engine->render('{{ items | join(", ") }}', ['items' => ['apple', 'banana', 'cherry']]) . "\n";
echo $engine->render('{{ price | number_format(2) }}', ['price' => 19.999]) . "\n";
echo $engine->render('{{ data | json }}', ['data' => ['a' => 1, 'b' => 2]]) . "\n";

echo "\n--- Conditionals ---\n";
echo $engine->render('{% if score >= 90 %}A{% else %}B{% endif %}', ['score' => 95]) . "\n";
echo $engine->render('{% if score >= 90 %}A{% else %}B{% endif %}', ['score' => 80]) . "\n";
echo $engine->render('{% if name == "Alice" %}Hi Alice!{% else %}Stranger{% endif %}', ['name' => 'Alice']) . "\n";
echo $engine->render('{% if name == "Alice" %}Hi Alice!{% else %}Stranger{% endif %}', ['name' => 'Bob']) . "\n";

echo "\n--- Loops ---\n";
echo $engine->render('{% for item in items %}{{ item }} {% endfor %}', ['items' => [1, 2, 3]]) . "\n";
echo $engine->render('{% for item in items %}{{ loop.index }}:{{ item }} {% endfor %}', ['items' => ['a', 'b', 'c']]) . "\n";
echo $engine->render('{% for item in items %}{{ item }}{% if not loop.last %}, {% endif %}{% endfor %}', ['items' => ['x', 'y', 'z']]) . "\n";

echo "\n--- Complex Template ---\n";
$template = '<h1>{{ title }}</h1>
{% if items | length > 0 %}
<ul>
{% for item in items %}
  <li>{{ loop.index }}. {{ item.name | upper }} - ${{ item.price | number_format(2) }}</li>
{% endfor %}
</ul>
{% else %}
<p>No items found.</p>
{% endif %}';

$context = [
    'title' => 'Product List',
    'items' => [
        ['name' => 'widget', 'price' => 9.99],
        ['name' => 'gadget', 'price' => 19.95],
        ['name' => 'gizmo', 'price' => 5.50],
    ],
];
echo $engine->render($template, $context) . "\n";

echo "\n--- Empty List ---\n";
echo $engine->render($template, ['title' => 'Empty', 'items' => []]) . "\n";

echo "\n--- Template Registration & Reuse ---\n";
$engine->registerTemplate('greeting', 'Hello, {{ name }}! You have {{ count }} messages.');
echo $engine->renderTemplate('greeting', ['name' => 'Alice', 'count' => 5]) . "\n";
echo $engine->renderTemplate('greeting', ['name' => 'Bob', 'count' => 0]) . "\n";

echo "\n--- Nested Data ---\n";
$nestedTemplate = '{{ company.name }} - {{ company.address.city }}, {{ company.address.state }}
Employees: {{ company.employees | length }}
{% for emp in company.employees %}- {{ emp.name }} ({{ emp.role }}){% endfor %}';
$nestedContext = [
    'company' => [
        'name' => 'TechCorp',
        'address' => ['city' => 'SF', 'state' => 'CA'],
        'employees' => [
            ['name' => 'Alice', 'role' => 'CEO'],
            ['name' => 'Bob', 'role' => 'CTO'],
            ['name' => 'Charlie', 'role' => 'Dev'],
        ],
    ],
];
echo $engine->render($nestedTemplate, $nestedContext) . "\n";

echo "=== f137 Done ===\n";
