<?php
// 极度混搭: 代码生成器 + AST + 模板 + 序列化
echo "=== f108: Code Gen + AST + Template + Serialize ===\n";

class CodeNode {
    public function __construct(public string $type, public array $props = [], public array $children = []) {}
}

class CodeGenerator {
    public function generatePHP(CodeNode $node, int $indent = 0): string {
        $pad = str_repeat('    ', $indent);
        return match($node->type) {
            'class' => $this->genClass($node, $indent),
            'method' => $this->genMethod($node, $indent),
            'property' => $this->genProperty($node, $indent),
            'if' => $this->genIf($node, $indent),
            'for' => $this->genFor($node, $indent),
            'return' => $pad . "return " . $node->props['value'] . ";\n",
            'echo' => $pad . "echo " . $node->props['value'] . ";\n",
            'assign' => $pad . "\${$node->props['var']} = {$node->props['value']};\n",
            'call' => $pad . $node->props['expr'] . ";\n",
            'comment' => $pad . "// " . $node->props['text'] . "\n",
            'block' => $this->genBlock($node, $indent),
            default => $pad . "// Unknown: {$node->type}\n",
        };
    }

    private function genClass(CodeNode $node, int $indent): string {
        $pad = str_repeat('    ', $indent);
        $name = $node->props['name'];
        $extends = isset($node->props['extends']) ? " extends {$node->props['extends']}" : '';
        $implements = isset($node->props['implements']) ? " implements {$node->props['implements']}" : '';
        $output = "{$pad}class $name$extends$implements {\n";
        foreach ($node->children as $child) $output .= $this->generatePHP($child, $indent + 1);
        $output .= "{$pad}}\n";
        return $output;
    }

    private function genMethod(CodeNode $node, int $indent): string {
        $pad = str_repeat('    ', $indent);
        $visibility = $node->props['visibility'] ?? 'public';
        $static = isset($node->props['static']) && $node->props['static'] ? 'static ' : '';
        $name = $node->props['name'];
        $params = $node->props['params'] ?? '';
        $retType = isset($node->props['returnType']) ? ": {$node->props['returnType']}" : '';
        $output = "{$pad}$visibility $static function $name($params)$retType {\n";
        foreach ($node->children as $child) $output .= $this->generatePHP($child, $indent + 1);
        $output .= "{$pad}}\n\n";
        return $output;
    }

    private function genProperty(CodeNode $node, int $indent): string {
        $pad = str_repeat('    ', $indent);
        $vis = $node->props['visibility'] ?? 'public';
        $name = $node->props['name'];
        $default = isset($node->props['default']) ? " = {$node->props['default']}" : '';
        $type = isset($node->props['type']) ? " {$node->props['type']}" : '';
        return "{$pad}$vis$type \$$name$default;\n";
    }

    private function genIf(CodeNode $node, int $indent): string {
        $pad = str_repeat('    ', $indent);
        $cond = $node->props['condition'];
        $output = "{$pad}if ($cond) {\n";
        foreach ($node->children as $child) $output .= $this->generatePHP($child, $indent + 1);
        $output .= "{$pad}}\n";
        return $output;
    }

    private function genFor(CodeNode $node, int $indent): string {
        $pad = str_repeat('    ', $indent);
        $init = $node->props['init'];
        $cond = $node->props['cond'];
        $incr = $node->props['incr'];
        $output = "{$pad}for ($init; $cond; $incr) {\n";
        foreach ($node->children as $child) $output .= $this->generatePHP($child, $indent + 1);
        $output .= "{$pad}}\n";
        return $output;
    }

    private function genBlock(CodeNode $node, int $indent): string {
        $output = '';
        foreach ($node->children as $child) $output .= $this->generatePHP($child, $indent);
        return $output;
    }

    public function generateJSON(CodeNode $node): string {
        return json_encode($this->nodeToArray($node), JSON_PRETTY_PRINT);
    }

    private function nodeToArray(CodeNode $node): array {
        $arr = ['type' => $node->type, 'props' => $node->props];
        if (!empty($node->children)) {
            $arr['children'] = array_map(fn($c) => $this->nodeToArray($c), $node->children);
        }
        return $arr;
    }

    public function fromJSON(string $json): CodeNode {
        return $this->arrayToNode(json_decode($json, true));
    }

    private function arrayToNode(array $arr): CodeNode {
        $children = array_map(fn($c) => $this->arrayToNode($c), $arr['children'] ?? []);
        return new CodeNode($arr['type'], $arr['props'] ?? [], $children);
    }
}

// 测试
$gen = new CodeGenerator();

echo "--- Generate PHP Class ---\n";
$class = new CodeNode('class', [
    'name' => 'UserService',
    'implements' => 'UserServiceInterface',
], [
    new CodeNode('property', ['visibility' => 'private', 'type' => 'array', 'name' => 'users', 'default' => '[]']),
    new CodeNode('property', ['visibility' => 'private', 'type' => 'int', 'name' => 'count', 'default' => '0']),
    new CodeNode('method', [
        'visibility' => 'public', 'name' => 'addUser', 'params' => 'string $name, int $age',
        'returnType' => 'void'
    ], [
        new CodeNode('assign', ['var' => 'this->users[]', 'value' => "['name' => \$name, 'age' => \$age]"]),
        new CodeNode('assign', ['var' => 'this->count', 'value' => 'this->count + 1']),
    ]),
    new CodeNode('method', [
        'visibility' => 'public', 'name' => 'findUser', 'params' => 'string $name',
        'returnType' => '?array'
    ], [
        new CodeNode('for', ['init' => '$i = 0', 'cond' => '$i < count($this->users)', 'incr' => '$i++'], [
            new CodeNode('if', ['condition' => '$this->users[$i]["name"] === $name'], [
                new CodeNode('return', ['value' => '$this->users[$i]']),
            ]),
        ]),
        new CodeNode('return', ['value' => 'null']),
    ]),
    new CodeNode('method', [
        'visibility' => 'public', 'static' => true, 'name' => 'create', 'params' => '',
        'returnType' => 'self'
    ], [
        new CodeNode('return', ['value' => 'new self()']),
    ]),
]);

$php = $gen->generatePHP($class);
echo $php;

echo "\n--- Serialize to JSON ---\n";
$json = $gen->generateJSON($class);
echo $json . "\n";

echo "\n--- Deserialize from JSON ---\n";
$restored = $gen->fromJSON($json);
$php2 = $gen->generatePHP($restored);
echo "Round-trip match: " . var_export($php === $php2, true) . "\n";

echo "\n--- Generate Complex Method ---\n";
$method = new CodeNode('method', [
    'visibility' => 'public', 'name' => 'processItems', 'params' => 'array $items',
    'returnType' => 'array'
], [
    new CodeNode('assign', ['var' => 'result', 'value' => '[]']),
    new CodeNode('for', ['init' => '$i = 0', 'cond' => '$i < count($items)', 'incr' => '$i++'], [
        new CodeNode('if', ['condition' => '$items[$i] > 0'], [
            new CodeNode('assign', ['var' => 'result[]', 'value' => '$items[$i] * 2']),
        ]),
    ]),
    new CodeNode('return', ['value' => '$result']),
]);
echo $gen->generatePHP($method);

echo "\n--- Generate Interface ---\n";
$interface = new CodeNode('class', ['name' => 'Repository', 'implements' => ''], [
    new CodeNode('comment', ['text' => 'Find by ID']),
    new CodeNode('method', ['visibility' => 'public', 'name' => 'find', 'params' => 'int $id', 'returnType' => '?array'], [
        new CodeNode('return', ['value' => 'null']),
    ]),
    new CodeNode('comment', ['text' => 'Save entity']),
    new CodeNode('method', ['visibility' => 'public', 'name' => 'save', 'params' => 'array $data', 'returnType' => 'bool'], [
        new CodeNode('return', ['value' => 'true']),
    ]),
    new CodeNode('comment', ['text' => 'Delete by ID']),
    new CodeNode('method', ['visibility' => 'public', 'name' => 'delete', 'params' => 'int $id', 'returnType' => 'bool'], [
        new CodeNode('return', ['value' => 'false']),
    ]),
]);
echo $gen->generatePHP($interface);

echo "=== f108 Done ===\n";
