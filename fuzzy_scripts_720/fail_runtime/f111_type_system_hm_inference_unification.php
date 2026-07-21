<?php
// 极度混搭: 类型系统 + Hindley-Milner类型推断 + 泛型 + 统一化
echo "=== f111: Type System + HM Inference + Unification ===\n";

abstract class Type {}
class TVar extends Type { public function __construct(public string $name) {} }
class TCon extends Type { public function __construct(public string $name) {} }
class TArrow extends Type { public function __construct(public Type $from, public Type $to) {} }
class TProduct extends Type { public function __construct(public array $types) {} }
class TList extends Type { public function __construct(public Type $elem) {} }

class TypeEnv {
    private array $env = [];
    private array $schemes = [];

    public function bind(string $name, Type $type): void { $this->env[$name] = $type; }
    public function lookup(string $name): ?Type { return $this->env[$name] ?? null; }
    public function remove(string $name): void { unset($this->env[$name]); }
    public function copy(): self { $c = new self(); $c->env = $this->env; return $c; }
    public function all(): array { return $this->env; }
}

class Substitution {
    private array $subs = [];

    public function bind(string $var, Type $type): void { $this->subs[$var] = $type; }
    public function lookup(string $var): ?Type { return $this->subs[$var] ?? null; }
    public function has(string $var): bool { return isset($this->subs[$var]); }
    public function all(): array { return $this->subs; }

    public function apply(Type $type): Type {
        return match(true) {
            $type instanceof TVar => $this->has($type->name) ? $this->apply($this->lookup($type->name)) : $type,
            $type instanceof TCon => $type,
            $type instanceof TArrow => new TArrow($this->apply($type->from), $this->apply($type->to)),
            $type instanceof TProduct => new TProduct(array_map(fn($t) => $this->apply($t), $type->types)),
            $type instanceof TList => new TList($this->apply($type->elem)),
        };
    }

    public function compose(Substitution $other): Substitution {
        $result = new Substitution();
        foreach ($this->subs as $var => $type) $result->bind($var, $other->apply($type));
        foreach ($other->subs as $var => $type) {
            if (!$result->has($var)) $result->bind($var, $type);
        }
        return $result;
    }
}

class Unifier {
    public static function unify(Type $t1, Type $t2): ?Substitution {
        if ($t1 instanceof TVar) return self::unifyVar($t1->name, $t2);
        if ($t2 instanceof TVar) return self::unifyVar($t2->name, $t1);
        if ($t1 instanceof TCon && $t2 instanceof TCon) {
            return $t1->name === $t2->name ? new Substitution() : null;
        }
        if ($t1 instanceof TArrow && $t2 instanceof TArrow) {
            $s1 = self::unify($t1->from, $t2->from);
            if ($s1 === null) return null;
            $s2 = self::unify($s1->apply($t1->to), $s1->apply($t2->to));
            if ($s2 === null) return null;
            return $s2->compose($s1);
        }
        if ($t1 instanceof TList && $t2 instanceof TList) {
            return self::unify($t1->elem, $t2->elem);
        }
        if ($t1 instanceof TProduct && $t2 instanceof TProduct) {
            if (count($t1->types) !== count($t2->types)) return null;
            $s = new Substitution();
            for ($i = 0; $i < count($t1->types); $i++) {
                $si = self::unify($s->apply($t1->types[$i]), $s->apply($t2->types[$i]));
                if ($si === null) return null;
                $s = $si->compose($s);
            }
            return $s;
        }
        return null;
    }

    private static function unifyVar(string $name, Type $t): ?Substitution {
        if ($t instanceof TVar && $t->name === $name) return new Substitution();
        if (self::occursIn($name, $t)) return null; // occurs check
        $s = new Substitution();
        $s->bind($name, $t);
        return $s;
    }

    private static function occursIn(string $name, Type $t): bool {
        return match(true) {
            $t instanceof TVar => $t->name === $name,
            $t instanceof TCon => false,
            $t instanceof TArrow => self::occursIn($name, $t->from) || self::occursIn($name, $t->to),
            $t instanceof TProduct => (bool)array_reduce($t->types, fn($c, $t) => $c || self::occursIn($name, $t), false),
            $t instanceof TList => self::occursIn($name, $t->elem),
        };
    }
}

class TypeInferencer {
    private int $freshCount = 0;

    private function fresh(): TVar { return new TVar("t" . $this->freshCount++); }

    public function infer(ASTNode $node, TypeEnv $env): array {
        return match($node->type) {
            'int' => [new TCon('Int'), new Substitution()],
            'bool' => [new TCon('Bool'), new Substitution()],
            'string' => [new TCon('String'), new Substitution()],
            'var' => $this->inferVar($node, $env),
            'lambda' => $this->inferLambda($node, $env),
            'app' => $this->inferApp($node, $env),
            'let' => $this->inferLet($node, $env),
            'if' => $this->inferIf($node, $env),
            'binop' => $this->inferBinOp($node, $env),
        };
    }

    private function inferVar(ASTNode $node, TypeEnv $env): array {
        $t = $env->lookup($node->value);
        if ($t === null) throw new Exception("Unbound variable: {$node->value}");
        return [$t, new Substitution()];
    }

    private function inferLambda(ASTNode $node, TypeEnv $env): array {
        $argType = $this->fresh();
        $newEnv = $env->copy();
        $newEnv->bind($node->param, $argType);
        [$bodyType, $s] = $this->infer($node->body, $newEnv);
        return [new TArrow($s->apply($argType), $bodyType), $s];
    }

    private function inferApp(ASTNode $node, TypeEnv $env): array {
        [$funType, $s1] = $this->infer($node->func, $env);
        [$argType, $s2] = $this->infer($node->arg, $env->copy());
        $s2 = $s2->compose($s1);
        $resultType = $this->fresh();
        $s3 = Unifier::unify($s2->apply($funType), new TArrow($argType, $resultType));
        if ($s3 === null) throw new Exception("Type mismatch in application");
        return [$s3->apply($resultType), $s3->compose($s2)];
    }

    private function inferLet(ASTNode $node, TypeEnv $env): array {
        [$valType, $s1] = $this->infer($node->value, $env);
        $newEnv = $env->copy();
        $newEnv->bind($node->name, $s1->apply($valType));
        [$bodyType, $s2] = $this->infer($node->body, $newEnv);
        return [$bodyType, $s2->compose($s1)];
    }

    private function inferIf(ASTNode $node, TypeEnv $env): array {
        [$condType, $s1] = $this->infer($node->cond, $env);
        $s = Unifier::unify($condType, new TCon('Bool'));
        if ($s === null) throw new Exception("If condition must be Bool");
        $s1 = $s->compose($s1);
        [$thenType, $s2] = $this->infer($node->then, $env->copy());
        [$elseType, $s3] = $this->infer($node->else, $env->copy());
        $s3 = $s3->compose($s2)->compose($s1);
        $s4 = Unifier::unify($s3->apply($thenType), $s3->apply($elseType));
        if ($s4 === null) throw new Exception("If branches must have same type");
        return [$s4->apply($thenType), $s4->compose($s3)];
    }

    private function inferBinOp(ASTNode $node, TypeEnv $env): array {
        [$leftType, $s1] = $this->infer($node->left, $env);
        [$rightType, $s2] = $this->infer($node->right, $env->copy());
        $s2 = $s2->compose($s1);
        $s3 = Unifier::unify($s2->apply($leftType), $s2->apply($rightType));
        if ($s3 === null) throw new Exception("Binary op type mismatch");
        $finalS = $s3->compose($s2);
        $resultType = in_array($node->op, ['==', '<', '>', '<=', '>=']) ? new TCon('Bool') : $finalS->apply($leftType);
        return [$resultType, $finalS];
    }
}

class ASTNode {
    public function __construct(public string $type, public array $props = []) {}
    public function __get($name) { return $this->props[$name] ?? null; }
}

function typeToString(Type $t): string {
    return match(true) {
        $t instanceof TVar => $t->name,
        $t instanceof TCon => $t->name,
        $t instanceof TArrow => "(" . typeToString($t->from) . " → " . typeToString($t->to) . ")",
        $t instanceof TProduct => "(" . implode(' * ', array_map('typeToString', $t->types)) . ")",
        $t instanceof TList => "[" . typeToString($t->elem) . "]",
    };
}

// 测试
echo "--- Unification ---\n";
$tests = [
    [new TVar('a'), new TCon('Int')],
    [new TCon('Int'), new TCon('Int')],
    [new TArrow(new TVar('a'), new TCon('Int')), new TArrow(new TCon('String'), new TVar('b'))],
    [new TList(new TVar('a')), new TList(new TCon('Int'))],
];
foreach ($tests as [$t1, $t2]) {
    $s = Unifier::unify($t1, $t2);
    echo "unify(" . typeToString($t1) . ", " . typeToString($t2) . "): ";
    echo $s ? "OK {" . implode(', ', array_map(fn($k, $v) => "$k=" . typeToString($v), array_keys($s->all()), $s->all())) . "}" : "FAIL";
    echo "\n";
}

echo "\n--- Type Inference ---\n";
$inferencer = new TypeInferencer();
$env = new TypeEnv();
$env->bind('+', new TArrow(new TCon('Int'), new TArrow(new TCon('Int'), new TCon('Int'))));
$env->bind('true', new TCon('Bool'));
$env->bind('42', new TCon('Int'));

// 42 : Int
$ast1 = new ASTNode('int', ['value' => 42]);
[$t1, $s1] = $inferencer->infer($ast1, $env);
echo "42 : " . typeToString($t1) . "\n";

// λx.x : a → a
$ast2 = new ASTNode('lambda', ['param' => 'x', 'body' => new ASTNode('var', ['value' => 'x'])]);
[$t2, $s2] = $inferencer->infer($ast2, $env);
echo "λx.x : " . typeToString($t2) . "\n";

// λx.λy.x : a → b → a
$ast3 = new ASTNode('lambda', ['param' => 'x', 'body' => new ASTNode('lambda', ['param' => 'y', 'body' => new ASTNode('var', ['value' => 'x'])])]);
[$t3, $s3] = $inferencer->infer($ast3, $env);
echo "λx.λy.x : " . typeToString($t3) . "\n";

// let id = λx.x in id : a → a
$ast4 = new ASTNode('let', [
    'name' => 'id',
    'value' => new ASTNode('lambda', ['param' => 'x', 'body' => new ASTNode('var', ['value' => 'x'])]),
    'body' => new ASTNode('var', ['value' => 'id']),
]);
[$t4, $s4] = $inferencer->infer($ast4, $env);
echo "let id = λx.x in id : " . typeToString($t4) . "\n";

// if true then 42 else 0 : Int
$ast5 = new ASTNode('if', [
    'cond' => new ASTNode('bool', ['value' => true]),
    'then' => new ASTNode('int', ['value' => 42]),
    'else' => new ASTNode('int', ['value' => 0]),
]);
[$t5, $s5] = $inferencer->infer($ast5, $env);
echo "if true then 42 else 0 : " . typeToString($t5) . "\n";

echo "\n--- Type Environment ---\n";
foreach ($env->all() as $name => $type) {
    echo "  $name : " . typeToString($type) . "\n";
}

echo "=== f111 Done ===\n";
