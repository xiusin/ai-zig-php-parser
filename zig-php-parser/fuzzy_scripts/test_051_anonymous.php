<?php
// Test 051: Anonymous classes, dynamic class creation
class AnonymousLab {
    public function process(): string {
        $out = "";

        $anon = new class {
            public string $value = 'anonymous_value';

            public function getValue(): string {
                return $this->value;
            }
        };

        $out .= "Anonymous class: " . get_class($anon) . "\n";
        $out .= "Anonymous value: " . $anon->value . "\n";
        $out .= "Anonymous method: " . $anon->getValue() . "\n";

        return $out;
    }

    public function withConstructor(): string {
        $out = "";

        $anon = new class('test', 42) {
            public function __construct(
                public string $name,
                public int $value
            ) {}

            public function describe(): string {
                return "\$name={$this->name}, \$value={$this->value}";
            }
        };

        $out .= "Anon with constructor: " . $anon->describe() . "\n";

        return $out;
    }

    public function extending(): string {
        $out = "";

        $parent = new class(100) {
            public function __construct(public int $baseValue) {}
        };

        $child = new class($parent) extends stdClass {
            public function __construct($parent) {
                $this->parentValue = $parent->baseValue;
            }
        };

        $out .= "Extended anon baseValue: " . $parent->baseValue . "\n";
        $out .= "Extended anon parentValue: " . $child->parentValue . "\n";

        return $out;
    }

    public function implementing(): string {
        $out = "";

        $impl = new class implements Countable {
            public function count(): int {
                return 42;
            }
        };

        $out .= "Anonymous Countable count: " . count($impl) . "\n";

        return $out;
    }
}

echo "=== Anonymous classes ===\n";
$lab = new AnonymousLab();
echo $lab->process();

echo "\n=== Anonymous with constructor ===\n";
echo $lab->withConstructor();

echo "\n=== Anonymous extending ===\n";
echo $lab->extending();

echo "\n=== Anonymous implementing ===\n";
echo $lab->implementing();

echo "\n=== Anonymous in function ===\n";
function createAnonymous(string $value): object {
    return new class($value) {
        public function __construct(public string $val) {}
        public function get(): string {
            return $this->val;
        }
    };
}

$obj = createAnonymous('wrapped');
echo "Wrapped anonymous: " . $obj->get() . "\n";

echo "\n=== Anonymous with traits ===\n";
trait AnonTrait {
    public function traitMethod(): string {
        return "from trait";
    }
}

$withTrait = new class {
    use AnonTrait;
};
echo "Trait method: " . $withTrait->traitMethod() . "\n";

echo "\n=== Anonymous instanceof ===\n";
$anon = new class {};
$std = new stdClass();
echo "anon instanceof stdClass: " . ($anon instanceof stdClass ? 'yes' : 'no') . "\n";
echo "std instanceof stdClass: " . ($std instanceof stdClass ? 'yes' : 'no') . "\n";