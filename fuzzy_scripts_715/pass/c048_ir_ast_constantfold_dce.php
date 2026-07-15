<?php
// 极度混搭: 编译器中间表示 + AST遍历 + 常量折叠 + 死代码消除 + 优化pass
echo "=== c048: IR + AST Traversal + ConstantFold + DeadCode + OptPass ===\n\n";

class ASTNode {
    public string $type;
    public mixed $value;
    public ?ASTNode $left = null;
    public ?ASTNode $right = null;
    public array $children = [];

    public function __construct(string $type, mixed $value = null) {
        $this->type = $type;
        $this->value = $value;
    }

    public function isLeaf(): bool {
        return $this->left === null && $this->right === null && empty($this->children);
    }

    public function __toString(): string {
        return $this->toStringIndented(0);
    }

    private function toStringIndented(int $depth): string {
        $indent = str_repeat("  ", $depth);
        $result = "$indent{$this->type}";
        if ($this->value !== null) {
            $result .= "(" . var_export($this->value, true) . ")";
        }
        $result .= "\n";
        if ($this->left !== null) $result .= $this->left->toStringIndented($depth + 1);
        if ($this->right !== null) $result .= $this->right->toStringIndented($depth + 1);
        foreach ($this->children as $child) {
            $result .= $child->toStringIndented($depth + 1);
        }
        return $result;
    }
}

class IRInstruction {
    public string $op;
    public mixed $arg1;
    public mixed $arg2;
    public ?string $result = null;
    public bool $dead = false;

    public function __construct(string $op, mixed $arg1 = null, mixed $arg2 = null, ?string $result = null) {
        $this->op = $op;
        $this->arg1 = $arg1;
        $this->arg2 = $arg2;
        $this->result = $result;
    }

    public function __toString(): string {
        $parts = [$this->op];
        if ($this->arg1 !== null) $parts[] = var_export($this->arg1, true);
        if ($this->arg2 !== null) $parts[] = var_export($this->arg2, true);
        if ($this->result !== null) $parts[] = "-> " . $this->result;
        return implode(" ", $parts);
    }
}

class ConstantFolder {
    public function optimize(ASTNode $node): ASTNode {
        if ($node->type === 'binary') {
            $node->left = $this->optimize($node->left);
            $node->right = $this->optimize($node->right);

            if ($node->left->type === 'number' && $node->right->type === 'number') {
                $result = match($node->value) {
                    '+' => $node->left->value + $node->right->value,
                    '-' => $node->left->value - $node->right->value,
                    '*' => $node->left->value * $node->right->value,
                    '/' => $node->right->value != 0 ? $node->left->value / $node->right->value : null,
                    '%' => $node->right->value != 0 ? $node->left->value % $node->right->value : null,
                    default => null,
                };
                if ($result !== null) {
                    return new ASTNode('number', $result);
                }
            }
        }
        return $node;
    }
}

class DeadCodeEliminator {
    private array $definedVars = [];
    private array $usedVars = [];

    public function analyze(ASTNode $node): void {
        $this->traverse($node);
    }

    private function traverse(ASTNode $node): void {
        if ($node->type === 'assign') {
            $this->definedVars[$node->left->value] = true;
            $this->traverse($node->right);
        } elseif ($node->type === 'var') {
            $this->usedVars[$node->value] = true;
        } elseif ($node->type === 'binary') {
            $this->traverse($node->left);
            $this->traverse($node->right);
        } elseif ($node->type === 'return') {
            $this->traverse($node->left);
        }
        foreach ($node->children as $child) {
            $this->traverse($child);
        }
    }

    public function getDeadVars(): array {
        $dead = [];
        foreach ($this->definedVars as $var => $true) {
            if (!isset($this->usedVars[$var])) {
                $dead[] = $var;
            }
        }
        return $dead;
    }
}

class IROptimizer {
    private array $instructions;
    private array $constPool = [];
    private array $definedRegs = [];

    public function __construct(array $instructions) {
        $this->instructions = $instructions;
    }

    public function optimize(): array {
        $this->constantPropagation();
        $this->deadCodeElimination();
        $this->constantFolding();
        return array_values(array_filter($this->instructions, fn($i) => !$i->dead));
    }

    private function constantPropagation(): void {
        foreach ($this->instructions as $instr) {
            if ($instr->op === 'LOAD_CONST' && $instr->result !== null) {
                $this->constPool[$instr->result] = $instr->arg1;
            }
            if ($instr->op === 'MOVE' && isset($this->constPool[$instr->arg1])) {
                $this->constPool[$instr->result] = $this->constPool[$instr->arg1];
            }
        }

        foreach ($this->instructions as $instr) {
            if ($instr->op !== 'LOAD_CONST' && $instr->op !== 'MOVE') {
                if ($instr->arg1 !== null && isset($this->constPool[$instr->arg1])) {
                    $instr->arg1 = $this->constPool[$instr->arg1];
                    $instr->op = 'LOAD_CONST_OPT';
                }
            }
        }
    }

    private function constantFolding(): void {
        foreach ($this->instructions as $instr) {
            if ($instr->op === 'ADD' && is_numeric($instr->arg1) && is_numeric($instr->arg2)) {
                $instr->op = 'LOAD_CONST_OPT';
                $instr->arg1 = $instr->arg1 + $instr->arg2;
                $instr->arg2 = null;
            }
            if ($instr->op === 'MUL' && is_numeric($instr->arg1) && is_numeric($instr->arg2)) {
                $instr->op = 'LOAD_CONST_OPT';
                $instr->arg1 = $instr->arg1 * $instr->arg2;
                $instr->arg2 = null;
            }
        }
    }

    private function deadCodeElimination(): void {
        foreach ($this->instructions as $instr) {
            if ($instr->result !== null) {
                $this->definedRegs[$instr->result] = false;
            }
        }

        foreach ($this->instructions as $instr) {
            if ($instr->arg1 !== null && is_string($instr->arg1) && isset($this->definedRegs[$instr->arg1])) {
                $this->definedRegs[$instr->arg1] = true;
            }
            if ($instr->arg2 !== null && is_string($instr->arg2) && isset($this->definedRegs[$instr->arg2])) {
                $this->definedRegs[$instr->arg2] = true;
            }
        }

        foreach ($this->instructions as $instr) {
            if ($instr->result !== null && !$this->definedRegs[$instr->result] && $instr->op !== 'STORE' && $instr->op !== 'RETURN') {
                $instr->dead = true;
            }
        }
    }
}

// === 测试 ===

echo "--- AST Construction ---\n";
// (2 + 3) * (4 - 1)
$ast = new ASTNode('binary', '*');
$ast->left = new ASTNode('binary', '+');
$ast->left->left = new ASTNode('number', 2);
$ast->left->right = new ASTNode('number', 3);
$ast->right = new ASTNode('binary', '-');
$ast->right->left = new ASTNode('number', 4);
$ast->right->right = new ASTNode('number', 1);

echo "AST:\n$ast\n";

echo "\n--- Constant Folding ---\n";
$folder = new ConstantFolder();
$optimized = $folder->optimize($ast);
echo "After constant folding:\n$optimized\n";

echo "\n--- More Complex AST ---\n";
// (1 + 2) * x + (3 * 4)
$ast2 = new ASTNode('binary', '+');
$ast2->left = new ASTNode('binary', '*');
$ast2->left->left = new ASTNode('binary', '+');
$ast2->left->left->left = new ASTNode('number', 1);
$ast2->left->left->right = new ASTNode('number', 2);
$ast2->left->right = new ASTNode('var', 'x');
$ast2->right = new ASTNode('binary', '*');
$ast2->right->left = new ASTNode('number', 3);
$ast2->right->right = new ASTNode('number', 4);

$optimized2 = $folder->optimize($ast2);
echo "After constant folding:\n$optimized2\n";

echo "\n--- Dead Code Analysis ---\n";
// x = 10; y = 20; z = x + y; return z; (y is used, so not dead)
$program = new ASTNode('block');
$program->children[] = new ASTNode('assign');
$program->children[0]->left = new ASTNode('var', 'x');
$program->children[0]->right = new ASTNode('number', 10);
$program->children[] = new ASTNode('assign');
$program->children[1]->left = new ASTNode('var', 'unused');
$program->children[1]->right = new ASTNode('number', 99);
$program->children[] = new ASTNode('assign');
$program->children[2]->left = new ASTNode('var', 'z');
$program->children[2]->right = new ASTNode('binary', '+');
$program->children[2]->right->left = new ASTNode('var', 'x');
$program->children[2]->right->right = new ASTNode('number', 5);
$program->children[] = new ASTNode('return');
$program->children[3]->left = new ASTNode('var', 'z');

$dce = new DeadCodeEliminator();
$dce->analyze($program);
echo "Dead variables: " . implode(", ", $dce->getDeadVars()) . "\n";

echo "\n--- IR Optimization ---\n";
$ir = [
    new IRInstruction('LOAD_CONST', 5, null, 't0'),
    new IRInstruction('LOAD_CONST', 3, null, 't1'),
    new IRInstruction('ADD', 't0', 't1', 't2'),
    new IRInstruction('LOAD_CONST', 10, null, 't3'),
    new IRInstruction('MUL', 't2', 't3', 't4'),  // t4 is used in return
    new IRInstruction('MOVE', 't4', null, 't5'),  // t5 is dead (not used)
    new IRInstruction('STORE', 't4', null, 'result'),
    new IRInstruction('RETURN', 'result'),
];

echo "Before optimization:\n";
foreach ($ir as $i) echo "  $i\n";

$opt = new IROptimizer($ir);
$optimized = $opt->optimize();

echo "\nAfter optimization:\n";
foreach ($optimized as $i) echo "  $i\n";
echo "Instructions: " . count($ir) . " -> " . count($optimized) . "\n";

echo "\n=== c048 Done ===\n";
