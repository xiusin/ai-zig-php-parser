<?php
// 访问者模式+组合模式：AST 遍历、双重分派
echo "=== f179: Visitor + Composite + AST Walk ===\n";

interface Visitor {
    public function visitNumber(NumberNode $node): mixed;
    public function visitString(StringNode $node): mixed;
    public function visitBinaryOp(BinaryOpNode $node): mixed;
    public function visitUnaryOp(UnaryOpNode $node): mixed;
    public function visitFunctionCall(FunctionCallNode $node): mixed;
    public function visitIfElse(IfElseNode $node): mixed;
    public function visitBlock(BlockNode $node): mixed;
    public function visitAssignment(AssignmentNode $node): mixed;
}

abstract class AstNode {
    abstract public function accept(Visitor $visitor): mixed;
    public array $children = [];
}

class NumberNode extends AstNode {
    public function __construct(public float $value) {}
    public function accept(Visitor $v): mixed { return $v->visitNumber($this); }
}

class StringNode extends AstNode {
    public function __construct(public string $value) {}
    public function accept(Visitor $v): mixed { return $v->visitString($this); }
}

class BinaryOpNode extends AstNode {
    public function __construct(public string $op, public AstNode $left, public AstNode $right) {
        $this->children = [$left, $right];
    }
    public function accept(Visitor $v): mixed { return $v->visitBinaryOp($this); }
}

class UnaryOpNode extends AstNode {
    public function __construct(public string $op, public AstNode $operand) {
        $this->children = [$operand];
    }
    public function accept(Visitor $v): mixed { return $v->visitUnaryOp($this); }
}

class FunctionCallNode extends AstNode {
    public function __construct(public string $name, public array $args) {
        $this->children = $args;
    }
    public function accept(Visitor $v): mixed { return $v->visitFunctionCall($this); }
}

class IfElseNode extends AstNode {
    public function __construct(public AstNode $cond, public AstNode $then, public ?AstNode $else = null) {
        $this->children = $else ? [$cond, $then, $else] : [$cond, $then];
    }
    public function accept(Visitor $v): mixed { return $v->visitIfElse($this); }
}

class BlockNode extends AstNode {
    public function __construct(public array $statements) {
        $this->children = $statements;
    }
    public function accept(Visitor $v): mixed { return $v->visitBlock($this); }
}

class AssignmentNode extends AstNode {
    public function __construct(public string $var, public AstNode $value) {
        $this->children = [$value];
    }
    public function accept(Visitor $v): mixed { return $v->visitAssignment($this); }
}

// 求值访问者
class EvalVisitor implements Visitor {
    private array $variables = [];

    public function visitNumber(NumberNode $n): mixed { return $n->value; }
    public function visitString(StringNode $n): mixed { return $n->value; }

    public function visitBinaryOp(BinaryOpNode $n): mixed {
        $l = $n->left->accept($this);
        $r = $n->right->accept($this);
        return match($n->op) {
            '+' => $l + $r, '-' => $l - $r, '*' => $l * $r,
            '/' => $r == 0 ? 0 : $l / $r, '%' => $l % $r,
            '==' => $l == $r, '!=' => $l != $r,
            '<' => $l < $r, '>' => $l > $r,
            default => 0,
        };
    }

    public function visitUnaryOp(UnaryOpNode $n): mixed {
        $v = $n->operand->accept($this);
        return match($n->op) { '-' => -$v, '!' => !$v, default => $v };
    }

    public function visitFunctionCall(FunctionCallNode $n): mixed {
        $args = array_map(fn($a) => $a->accept($this), $n->args);
        return match($n->name) {
            'max' => max($args), 'min' => min($args),
            'abs' => abs($args[0] ?? 0), 'sqrt' => sqrt($args[0] ?? 0),
            'pow' => pow($args[0] ?? 0, $args[1] ?? 1),
            default => 0,
        };
    }

    public function visitIfElse(IfElseNode $n): mixed {
        if ($n->cond->accept($this)) return $n->then->accept($this);
        return $n->else?->accept($this) ?? null;
    }

    public function visitBlock(BlockNode $n): mixed {
        $result = null;
        foreach ($n->statements as $stmt) $result = $stmt->accept($this);
        return $result;
    }

    public function visitAssignment(AssignmentNode $n): mixed {
        $val = $n->value->accept($this);
        $this->variables[$n->var] = $val;
        return $val;
    }

    public function getVariables(): array { return $this->variables; }
}

// 打印访问者
class PrintVisitor implements Visitor {
    private int $depth = 0;
    private string $output = '';

    private function indent(): string { return str_repeat('  ', $this->depth); }

    public function visitNumber(NumberNode $n): mixed {
        $this->output .= $this->indent() . "Number({$n->value})\n";
        return null;
    }

    public function visitString(StringNode $n): mixed {
        $this->output .= $this->indent() . "String('{$n->value}')\n";
        return null;
    }

    public function visitBinaryOp(BinaryOpNode $n): mixed {
        $this->output .= $this->indent() . "BinaryOp('{$n->op}')\n";
        $this->depth++;
        $n->left->accept($this);
        $n->right->accept($this);
        $this->depth--;
        return null;
    }

    public function visitUnaryOp(UnaryOpNode $n): mixed {
        $this->output .= $this->indent() . "UnaryOp('{$n->op}')\n";
        $this->depth++;
        $n->operand->accept($this);
        $this->depth--;
        return null;
    }

    public function visitFunctionCall(FunctionCallNode $n): mixed {
        $this->output .= $this->indent() . "Call('{$n->name}')\n";
        $this->depth++;
        foreach ($n->args as $arg) $arg->accept($this);
        $this->depth--;
        return null;
    }

    public function visitIfElse(IfElseNode $n): mixed {
        $this->output .= $this->indent() . "If\n";
        $this->depth++;
        $this->output .= $this->indent() . "Condition:\n";
        $this->depth++;
        $n->cond->accept($this);
        $this->depth--;
        $this->output .= $this->indent() . "Then:\n";
        $this->depth++;
        $n->then->accept($this);
        $this->depth--;
        if ($n->else) {
            $this->output .= $this->indent() . "Else:\n";
            $this->depth++;
            $n->else->accept($this);
            $this->depth--;
        }
        $this->depth--;
        return null;
    }

    public function visitBlock(BlockNode $n): mixed {
        $this->output .= $this->indent() . "Block\n";
        $this->depth++;
        foreach ($n->statements as $stmt) $stmt->accept($this);
        $this->depth--;
        return null;
    }

    public function visitAssignment(AssignmentNode $n): mixed {
        $this->output .= $this->indent() . "Assign('{$n->var}')\n";
        $this->depth++;
        $n->value->accept($this);
        $this->depth--;
        return null;
    }

    public function getOutput(): string { return $this->output; }
}

// 统计访问者
class CountVisitor implements Visitor {
    private array $counts = [];

    private function count(string $type): void {
        $this->counts[$type] = ($this->counts[$type] ?? 0) + 1;
    }

    public function visitNumber(NumberNode $n): mixed { $this->count('number'); return null; }
    public function visitString(StringNode $n): mixed { $this->count('string'); return null; }
    public function visitBinaryOp(BinaryOpNode $n): mixed {
        $this->count('binary');
        $n->left->accept($this); $n->right->accept($this);
        return null;
    }
    public function visitUnaryOp(UnaryOpNode $n): mixed {
        $this->count('unary'); $n->operand->accept($this); return null;
    }
    public function visitFunctionCall(FunctionCallNode $n): mixed {
        $this->count('call');
        foreach ($n->args as $a) $a->accept($this);
        return null;
    }
    public function visitIfElse(IfElseNode $n): mixed {
        $this->count('if');
        $n->cond->accept($this); $n->then->accept($this);
        $n->else?->accept($this);
        return null;
    }
    public function visitBlock(BlockNode $n): mixed {
        $this->count('block');
        foreach ($n->statements as $s) $s->accept($this);
        return null;
    }
    public function visitAssignment(AssignmentNode $n): mixed {
        $this->count('assign'); $n->value->accept($this); return null;
    }

    public function getCounts(): array { return $this->counts; }
}

// 测试
echo "--- AST Construction ---\n";
// x = 10 + 20 * 3
$ast = new BlockNode([
    new AssignmentNode('x', new BinaryOpNode('+',
        new NumberNode(10),
        new BinaryOpNode('*', new NumberNode(20), new NumberNode(3))
    )),
    new AssignmentNode('y', new FunctionCallNode('max', [
        new NumberNode(5), new NumberNode(10), new NumberNode(3),
    ])),
    new IfElseNode(
        new BinaryOpNode('>', new StringNode('x'), new NumberNode(50)),
        new NumberNode(100),
        new NumberNode(200)
    ),
]);

echo "\n--- Print Visitor (AST Structure) ---\n";
$printer = new PrintVisitor();
$ast->accept($printer);
echo $printer->getOutput();

echo "\n--- Eval Visitor ---\n";
$evaluator = new EvalVisitor();
$result = $ast->accept($evaluator);
echo "  Result: $result\n";
echo "  Variables: " . json_encode($evaluator->getVariables()) . "\n";

echo "\n--- Count Visitor ---\n";
$counter = new CountVisitor();
$ast->accept($counter);
echo "  Node counts:\n";
foreach ($counter->getCounts() as $type => $count) {
    echo "    $type: $count\n";
}

echo "\n--- Simple Expression ---\n";
$expr = new BinaryOpNode('*',
    new BinaryOpNode('+', new NumberNode(2), new NumberNode(3)),
    new NumberNode(4)
);
$eval = new EvalVisitor();
echo "  (2 + 3) * 4 = " . $expr->accept($eval) . "\n";

echo "\n--- Nested Function Calls ---\n";
$nested = new FunctionCallNode('max', [
    new FunctionCallNode('min', [new NumberNode(10), new NumberNode(20)]),
    new FunctionCallNode('abs', [new UnaryOpNode('-', new NumberNode(15))]),
    new BinaryOpNode('+', new NumberNode(5), new NumberNode(3)),
]);
$eval2 = new EvalVisitor();
echo "  max(min(10,20), abs(-15), 5+3) = " . $nested->accept($eval2) . "\n";

echo "=== f179 Done ===\n";
