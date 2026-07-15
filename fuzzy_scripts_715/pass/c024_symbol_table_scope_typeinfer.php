<?php
// 极度混搭: 编译器符号表 + 作用域链 + 类型推导 + 语义分析 + 错误收集
echo "=== c024: SymbolTable + ScopeChain + TypeInference + Semantic ===\n\n";

class SymbolType {
    public const INT = 'int';
    public const FLOAT = 'float';
    public const STRING = 'string';
    public const BOOL = 'bool';
    public const ARRAY = 'array';
    public const FUNCTION = 'function';
    public const CLASS_ = 'class';
    public const NULL = 'null';
    public const VOID = 'void';
    public const MIXED = 'mixed';
}

class Symbol {
    public string $name;
    public string $type;
    public mixed $value;
    public int $scopeLevel;
    public bool $isConst;
    public bool $isRef;

    public function __construct(string $name, string $type, mixed $value = null, int $scopeLevel = 0, bool $isConst = false, bool $isRef = false) {
        $this->name = $name;
        $this->type = $type;
        $this->value = $value;
        $this->scopeLevel = $scopeLevel;
        $this->isConst = $isConst;
        $this->isRef = $isRef;
    }
}

class FunctionSymbol extends Symbol {
    public array $params = [];
    public string $returnType;

    public function __construct(string $name, array $params, string $returnType, int $scopeLevel = 0) {
        parent::__construct($name, SymbolType::FUNCTION, null, $scopeLevel);
        $this->params = $params;
        $this->returnType = $returnType;
    }
}

class ClassSymbol extends Symbol {
    public array $properties = [];
    public array $methods = [];
    public ?string $parent = null;
    public array $interfaces = [];

    public function __construct(string $name, int $scopeLevel = 0) {
        parent::__construct($name, SymbolType::CLASS_, null, $scopeLevel);
    }
}

class Scope {
    private int $level;
    private array $symbols = [];
    public ?Scope $parent;

    public function __construct(int $level, ?Scope $parent = null) {
        $this->level = $level;
        $this->parent = $parent;
    }

    public function define(Symbol $symbol): bool {
        if (isset($this->symbols[$symbol->name])) {
            return false; // Redefinition
        }
        $symbol->scopeLevel = $this->level;
        $this->symbols[$symbol->name] = $symbol;
        return true;
    }

    public function lookup(string $name): ?Symbol {
        if (isset($this->symbols[$name])) {
            return $this->symbols[$name];
        }
        return $this->parent?->lookup($name);
    }

    public function hasLocal(string $name): bool {
        return isset($this->symbols[$name]);
    }

    public function getSymbols(): array {
        return $this->symbols;
    }

    public function getLevel(): int {
        return $this->level;
    }
}

class SymbolTable {
    private Scope $globalScope;
    private Scope $currentScope;
    private int $scopeCounter = 0;
    private array $errors = [];
    private array $warnings = [];

    public function __construct() {
        $this->globalScope = new Scope(0);
        $this->currentScope = $this->globalScope;
    }

    public function pushScope(): void {
        $this->scopeCounter++;
        $this->currentScope = new Scope($this->scopeCounter, $this->currentScope);
    }

    public function popScope(): void {
        if ($this->currentScope->getLevel() > 0) {
            $this->currentScope = $this->currentScope->parent ?? $this->globalScope;
        }
    }

    public function defineVariable(string $name, string $type, mixed $value = null, bool $isConst = false): bool {
        $symbol = new Symbol($name, $type, $value, $this->currentScope->getLevel(), $isConst);
        if (!$this->currentScope->define($symbol)) {
            $this->errors[] = "Redefinition of '$name' in scope " . $this->currentScope->getLevel();
            return false;
        }
        return true;
    }

    public function defineFunction(string $name, array $params, string $returnType): bool {
        $symbol = new FunctionSymbol($name, $params, $returnType, $this->currentScope->getLevel());
        if (!$this->currentScope->define($symbol)) {
            $this->errors[] = "Redefinition of function '$name'";
            return false;
        }
        return true;
    }

    public function defineClass(string $name, ?string $parent = null, array $interfaces = []): bool {
        $symbol = new ClassSymbol($name, $this->currentScope->getLevel());
        $symbol->parent = $parent;
        $symbol->interfaces = $interfaces;
        if (!$this->currentScope->define($symbol)) {
            $this->errors[] = "Redefinition of class '$name'";
            return false;
        }
        return true;
    }

    public function lookup(string $name): ?Symbol {
        return $this->currentScope->lookup($name);
    }

    public function checkType(string $name, string $expectedType): bool {
        $symbol = $this->lookup($name);
        if ($symbol === null) {
            $this->errors[] = "Undefined variable '$name'";
            return false;
        }
        if ($symbol->type !== $expectedType && $symbol->type !== SymbolType::MIXED) {
            $this->errors[] = "Type mismatch: '$name' is {$symbol->type}, expected $expectedType";
            return false;
        }
        return true;
    }

    public function inferType(mixed $value): string {
        return match(true) {
            is_int($value) => SymbolType::INT,
            is_float($value) => SymbolType::FLOAT,
            is_string($value) => SymbolType::STRING,
            is_bool($value) => SymbolType::BOOL,
            is_array($value) => SymbolType::ARRAY,
            is_null($value) => SymbolType::NULL,
            default => SymbolType::MIXED,
        };
    }

    public function checkAssignment(string $name, mixed $value): bool {
        $symbol = $this->lookup($name);
        if ($symbol === null) {
            $this->errors[] = "Undefined variable '$name'";
            return false;
        }
        if ($symbol->isConst) {
            $this->errors[] = "Cannot assign to constant '$name'";
            return false;
        }
        $inferredType = $this->inferType($value);
        if ($symbol->type !== SymbolType::MIXED && $symbol->type !== $inferredType) {
            $this->warnings[] = "Type coercion: '$name' declared as {$symbol->type}, assigned $inferredType";
        }
        $symbol->value = $value;
        $symbol->type = $inferredType;
        return true;
    }

    public function getErrors(): array { return $this->errors; }
    public function getWarnings(): array { return $this->warnings; }

    public function dumpScope(): array {
        $result = [];
        $scope = $this->currentScope;
        while ($scope !== null) {
            $symbols = $scope->getSymbols();
            $level = $scope->getLevel();
            foreach ($symbols as $name => $symbol) {
                $result[] = [
                    'name' => $name,
                    'type' => $symbol->type,
                    'scope' => $level,
                    'value' => $symbol->value,
                ];
            }
            $scope = $scope->parent ?? null;
        }
        return $result;
    }
}

// === 测试 ===

echo "--- Symbol Table Setup ---\n";
$st = new SymbolTable();

// Global variables
$st->defineVariable('PI', SymbolType::FLOAT, 3.14159, true);
$st->defineVariable('count', SymbolType::INT, 0);
$st->defineVariable('message', SymbolType::STRING, 'hello');
$st->defineVariable('debug', SymbolType::BOOL, false);

// Functions
$st->defineFunction('calculate', [
    ['name' => 'x', 'type' => SymbolType::INT],
    ['name' => 'y', 'type' => SymbolType::INT],
], SymbolType::INT);

$st->defineFunction('greet', [
    ['name' => 'name', 'type' => SymbolType::STRING],
], SymbolType::STRING);

// Class
$st->defineClass('Vector', null, []);

echo "Symbols defined: " . count($st->dumpScope()) . "\n";

echo "\n--- Scope Nesting ---\n";
$st->pushScope();
$st->defineVariable('local_var', SymbolType::INT, 42);
$st->defineVariable('temp', SymbolType::STRING, 'inner');

$st->pushScope();
$st->defineVariable('deep_var', SymbolType::FLOAT, 3.14);
echo "Lookup deep_var: " . var_export($st->lookup('deep_var') !== null, true) . "\n";
echo "Lookup local_var (parent scope): " . var_export($st->lookup('local_var') !== null, true) . "\n";
echo "Lookup PI (global): " . var_export($st->lookup('PI') !== null, true) . "\n";

echo "\nScope dump:\n";
foreach ($st->dumpScope() as $sym) {
    echo "  {$sym['name']} ({$sym['type']}) scope={$sym['scope']} value=" . var_export($sym['value'], true) . "\n";
}

$st->popScope();
$st->popScope();

echo "\n--- Type Checking ---\n";
$st->defineVariable('x', SymbolType::INT, 10);
echo "checkType(x, int): " . var_export($st->checkType('x', SymbolType::INT), true) . "\n";
echo "checkType(x, string): " . var_export($st->checkType('x', SymbolType::STRING), true) . "\n";

echo "\n--- Type Inference ---\n";
$values = [42, 3.14, "hello", true, [1, 2, 3], null];
foreach ($values as $val) {
    echo "  " . var_export($val, true) . " -> " . $st->inferType($val) . "\n";
}

echo "\n--- Assignment Check ---\n";
$st->defineVariable('counter', SymbolType::INT, 0);
$st->checkAssignment('counter', 5);
$st->checkAssignment('counter', "not a number");
$st->checkAssignment('PI', 2.71);

echo "\n--- Redefinition ---\n";
$st->defineVariable('x', SymbolType::INT, 1);

echo "\n--- Errors & Warnings ---\n";
foreach ($st->getErrors() as $err) {
    echo "  ERROR: $err\n";
}
foreach ($st->getWarnings() as $warn) {
    echo "  WARN: $warn\n";
}

echo "\n=== c024 Done ===\n";
