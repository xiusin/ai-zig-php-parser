<?php
// 极度混搭: 代码生成器 + AST + 模板 + DSL + 序列化
echo "=== f143: Code Generator + AST + Template + DSL ===\n";

class ASTNode {
    public function __construct(public string $type, public array $props = [], public array $children = []) {}
    public function __toString(): string { return "$this->type(" . json_encode($this->props) . ")"; }
}

class ASTBuilder {
    public static function assignment(string $var, ASTNode|string $value): ASTNode {
        return new ASTNode('assign', ['var' => $var, 'value' => $value]);
    }

    public static function binaryOp(string $op, ASTNode|string $left, ASTNode|string $right): ASTNode {
        return new ASTNode('binop', ['op' => $op, 'left' => $left, 'right' => $right]);
    }

    public static function funcCall(string $name, array $args): ASTNode {
        return new ASTNode('call', ['name' => $name, 'args' => $args]);
    }

    public static function ifStmt(ASTNode|string $cond, array $then, array $else = []): ASTNode {
        return new ASTNode('if', ['cond' => $cond], array_merge(
            [new ASTNode('then', [], $then)],
            $else ? [new ASTNode('else', [], $else)] : []
        ));
    }

    public static function forStmt(string $var, ASTNode|string $iterable, array $body): ASTNode {
        return new ASTNode('for', ['var' => $var, 'iterable' => $iterable], $body);
    }

    public static function funcDecl(string $name, array $params, array $body): ASTNode {
        return new ASTNode('func', ['name' => $name, 'params' => $params], $body);
    }

    public static function returnStmt(ASTNode|string $value): ASTNode {
        return new ASTNode('return', ['value' => $value]);
    }

    public static function literal(mixed $value): ASTNode {
        return new ASTNode('literal', ['value' => $value]);
    }

    public static function variable(string $name): ASTNode {
        return new ASTNode('var', ['name' => $name]);
    }
}

class PHPCodeGenerator {
    private int $indent = 0;

    public function generate(ASTNode $node): string {
        return $this->genNode($node);
    }

    private function genNode(ASTNode|string $node): string {
        if (is_string($node)) return $node;
        return match($node->type) {
            'assign' => "\${$node->props['var']} = " . $this->genValue($node->props['value']) . ';',
            'binop' => $this->genValue($node->props['left']) . " {$node->props['op']} " . $this->genValue($node->props['right']),
            'call' => "{$node->props['name']}(" . implode(', ', array_map(fn($a) => $this->genValue($a), $node->props['args'])) . ")",
            'if' => $this->genIf($node),
            'for' => $this->genFor($node),
            'func' => $this->genFunc($node),
            'return' => 'return ' . $this->genValue($node->props['value']) . ';',
            'literal' => $this->genLiteral($node->props['value']),
            'var' => "\${$node->props['name']}",
            default => "/* unknown: {$node->type} */",
        };
    }

    private function genValue(ASTNode|string $value): string {
        if (is_string($value)) return $value;
        return $this->genNode($value);
    }

    private function genLiteral(mixed $value): string {
        if (is_string($value)) return "'$value'";
        if (is_bool($value)) return $value ? 'true' : 'false';
        if (is_null($value)) return 'null';
        if (is_array($value)) return '[' . implode(', ', array_map(fn($v) => $this->genLiteral($v), $value)) . ']';
        return (string)$value;
    }

    private function genIf(ASTNode $node): string {
        $indent = str_repeat('    ', $this->indent);
        $code = $indent . "if (" . $this->genValue($node->props['cond']) . ") {\n";
        $this->indent++;
        foreach ($node->children as $child) {
            if ($child->type === 'then') {
                foreach ($child->children as $stmt) $code .= str_repeat('    ', $this->indent) . $this->genNode($stmt) . "\n";
            }
        }
        $this->indent--;
        $code .= $indent . "}";
        foreach ($node->children as $child) {
            if ($child->type === 'else') {
                $code .= " else {\n";
                $this->indent++;
                foreach ($child->children as $stmt) $code .= str_repeat('    ', $this->indent) . $this->genNode($stmt) . "\n";
                $this->indent--;
                $code .= $indent . "}";
            }
        }
        return $code;
    }

    private function genFor(ASTNode $node): string {
        $indent = str_repeat('    ', $this->indent);
        $code = $indent . "foreach (\${$node->props['iterable']} as \${$node->props['var']}) {\n";
        $this->indent++;
        foreach ($node->children as $stmt) $code .= str_repeat('    ', $this->indent) . $this->genNode($stmt) . "\n";
        $this->indent--;
        $code .= $indent . "}";
        return $code;
    }

    private function genFunc(ASTNode $node): string {
        $params = implode(', ', array_map(fn($p) => "\$$p", $node->props['params']));
        $code = "function {$node->props['name']}($params) {\n";
        $this->indent++;
        foreach ($node->children as $stmt) $code .= str_repeat('    ', $this->indent) . $this->genNode($stmt) . "\n";
        $this->indent--;
        $code .= "}\n";
        return $code;
    }
}

class DSLParser {
    private int $pos = 0;

    public function parse(string $dsl): array {
        $lines = explode("\n", trim($dsl));
        $ast = [];
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) continue;
            $ast[] = $this->parseLine($line);
        }
        return $ast;
    }

    private function parseLine(string $line): ASTNode {
        if (preg_match('/^let\s+(\w+)\s*=\s*(.+)$/', $line, $m)) {
            return ASTBuilder::assignment($m[1], $this->parseExpr($m[2]));
        }
        if (preg_match('/^if\s+(.+)$/', $line, $m)) {
            return ASTBuilder::ifStmt($this->parseExpr($m[1]), [
                ASTBuilder::funcCall('doSomething', [ASTBuilder::literal('if-branch')])
            ]);
        }
        if (preg_match('/^return\s+(.+)$/', $line, $m)) {
            return ASTBuilder::returnStmt($this->parseExpr($m[1]));
        }
        if (preg_match('/^call\s+(\w+)\((.*)\)$/', $line, $m)) {
            $args = $m[2] ? array_map(fn($a) => $this->parseExpr(trim($a)), explode(',', $m[2])) : [];
            return ASTBuilder::funcCall($m[1], $args);
        }
        return new ASTNode('comment', ['text' => $line]);
    }

    private function parseExpr(string $expr): ASTNode|string {
        $expr = trim($expr);
        if (preg_match('/^(\d+)$/', $expr)) return ASTBuilder::literal((int)$expr);
        if (preg_match('/^"(.*)"$/', $expr, $m)) return ASTBuilder::literal($m[1]);
        if (preg_match('/^(\w+)$/', $expr)) return ASTBuilder::variable($expr);
        if (preg_match('/^(.+?)\s*([+\-*/])\s*(.+)$/', $expr, $m)) {
            return ASTBuilder::binaryOp($m[2], $this->parseExpr($m[1]), $this->parseExpr($m[3]));
        }
        return $expr;
    }
}

class CodeSerializer {
    public static function toJSON(ASTNode $node): string { return json_encode(self::nodeToArray($node), JSON_PRETTY_PRINT); }

    private static function nodeToArray(ASTNode $node): array {
        $arr = ['type' => $node->type, 'props' => $node->props];
        if (!empty($node->children)) {
            $arr['children'] = array_map(fn($c) => $c instanceof ASTNode ? self::nodeToArray($c) : $c, $node->children);
        }
        return $arr;
    }

    public static function fromJSON(string $json): ASTNode {
        $data = json_decode($json, true);
        return self::arrayToNode($data);
    }

    private static function arrayToNode(array $data): ASTNode {
        $children = [];
        foreach ($data['children'] ?? [] as $c) {
            $children[] = is_array($c) ? self::arrayToNode($c) : $c;
        }
        return new ASTNode($data['type'], $data['props'] ?? [], $children);
    }
}

// 测试
echo "--- AST Building & Code Generation ---\n";
$ast = ASTBuilder::funcDecl('calculateTotal', ['items', 'taxRate'], [
    ASTBuilder::assignment('total', ASTBuilder::literal(0)),
    ASTBuilder::forStmt('item', 'items', [
        ASTBuilder::assignment('total', ASTBuilder::binaryOp('+', ASTBuilder::variable('total'), ASTBuilder::variable('item')))
    ]),
    ASTBuilder::assignment('tax', ASTBuilder::binaryOp('*', ASTBuilder::variable('total'), ASTBuilder::variable('taxRate'))),
    ASTBuilder::returnStmt(ASTBuilder::binaryOp('+', ASTBuilder::variable('total'), ASTBuilder::variable('tax')))
]);

$gen = new PHPCodeGenerator();
echo "Generated PHP code:\n";
echo $gen->generate($ast) . "\n";

echo "\n--- If Statement Generation ---\n";
$ifAst = ASTBuilder::ifStmt(
    ASTBuilder::binaryOp('>', ASTBuilder::variable('score'), ASTBuilder::literal(90)),
    [ASTBuilder::assignment('grade', ASTBuilder::literal('A'))],
    [ASTBuilder::assignment('grade', ASTBuilder::literal('B'))]
);
echo $gen->generate($ifAst) . "\n";

echo "\n--- DSL Parsing ---\n";
$dsl = <<<DSL
# This is a comment
let x = 10
let y = x + 20
let name = "hello"
if x > 5
return x * y
call print(name)
DSL;

echo "DSL Input:\n$dsl\n\n";
$parser = new DSLParser();
$parsed = $parser->parse($dsl);
echo "Parsed AST nodes: " . count($parsed) . "\n";
foreach ($parsed as $node) {
    echo "  $node\n";
}

echo "\n--- Generate PHP from DSL ---\n";
foreach ($parsed as $node) {
    $code = $gen->generate($node);
    if ($code) echo $code . "\n";
}

echo "\n--- AST Serialization ---\n";
$serializeAst = ASTBuilder::funcDecl('greet', ['name'], [
    ASTBuilder::funcCall('echo', [ASTBuilder::binaryOp('.', ASTBuilder::literal('Hello, '), ASTBuilder::variable('name'))])
]);
$json = CodeSerializer::toJSON($serializeAst);
echo "Serialized AST:\n$json\n\n";

$deserialized = CodeSerializer::fromJSON($json);
echo "Deserialized & regenerated code:\n";
echo $gen->generate($deserialized) . "\n";

echo "\n--- Complex Code Generation ---\n";
$complexAst = ASTBuilder::funcDecl('fibonacci', ['n'], [
    ASTBuilder::ifStmt(
        ASTBuilder::binaryOp('<', ASTBuilder::variable('n'), ASTBuilder::literal(2)),
        [ASTBuilder::returnStmt(ASTBuilder::variable('n'))]
    ),
    ASTBuilder::returnStmt(ASTBuilder::binaryOp('+',
        ASTBuilder::funcCall('fibonacci', [ASTBuilder::binaryOp('-', ASTBuilder::variable('n'), ASTBuilder::literal(1))]),
        ASTBuilder::funcCall('fibonacci', [ASTBuilder::binaryOp('-', ASTBuilder::variable('n'), ASTBuilder::literal(2))])
    ))
]);
echo "Fibonacci function:\n";
echo $gen->generate($complexAst) . "\n";

echo "\n--- Template-Based Generation ---\n";
class Template {
    public static function generateClass(string $name, array $properties, array $methods): string {
        $code = "class $name {\n";
        foreach ($properties as $prop) $code .= "    public \$$prop;\n";
        $code .= "\n";
        foreach ($methods as $method) {
            $code .= "    public function $method() {\n";
            $code .= "        // TODO: implement\n";
            $code .= "    }\n\n";
        }
        $code .= "}\n";
        return $code;
    }

    public static function generateInterface(string $name, array $methods): string {
        $code = "interface $name {\n";
        foreach ($methods as $method => $params) {
            $paramStr = implode(', ', array_map(fn($p) => "\$$p", $params));
            $code .= "    public function $method($paramStr);\n";
        }
        $code .= "}\n";
        return $code;
    }
}

echo "Generated class:\n";
echo Template::generateClass('User', ['id', 'name', 'email'], ['save', 'delete', 'toArray']) . "\n";
echo "Generated interface:\n";
echo Template::generateInterface('Repository', ['find' => ['id'], 'findAll' => [], 'save' => ['entity'], 'delete' => ['id']]) . "\n";

echo "=== f143 Done ===\n";
