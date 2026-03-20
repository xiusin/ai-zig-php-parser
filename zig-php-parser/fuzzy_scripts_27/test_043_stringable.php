<?php
// Test 043: Stringable interface, __toString, Stringify
class StringableObject implements Stringable {
    public function __construct(private string $value) {}

    public function __toString(): string {
        return $this->value;
    }
}

class AutoStringable {
    public function __construct(
        public string $name,
        public int $value
    ) {}

    public function __toString(): string {
        return "AutoStringable($this->name, $this->value)";
    }
}

class ChainToString {
    private array $parts = [];

    public function add(string $part): self {
        $this->parts[] = $part;
        return $this;
    }

    public function __toString(): string {
        return implode(' -> ', $this->parts);
    }
}

class JsonToString implements Stringable {
    public function __construct(private array $data) {}

    public function __toString(): string {
        return json_encode($this->data);
    }
}

echo "=== Stringable interface ===\n";
$str = new StringableObject('Hello Stringable');
echo "StringableObject: $str\n";

$auto = new AutoStringable('test', 42);
echo "AutoStringable: $auto\n";

$chain = new ChainToString();
$chain->add('one')->add('two')->add('three');
echo "ChainToString: $chain\n";

$json = new JsonToString(['key' => 'value', 'num' => 123]);
echo "JsonToString: $json\n";

echo "\n=== Stringable type checks ===\n";
echo "\$str instanceof Stringable: " . ($str instanceof Stringable ? 'yes' : 'no') . "\n";
echo "\$auto instanceof Stringable: " . ($auto instanceof Stringable ? 'yes' : 'no') . "\n";
echo "\$chain instanceof Stringable: " . ($chain instanceof Stringable ? 'yes' : 'no') . "\n";

echo "\n=== Stringable in function ===\n";
function processStringable(Stringable $s): string {
    return "Processed: " . $s->__toString();
}

echo processStringable($str) . "\n";
echo processStringable($auto) . "\n";

echo "\n=== Stringable with concatenation ===\n";
$part1 = new StringableObject('First');
$part2 = new StringableObject('Second');
echo "Concatenated: " . $part1 . " + " . $part2 . "\n";

echo "\n=== Stringable array casting ===\n";
$strArr = [$str, $auto, $chain];
echo "Array implode: " . implode(' | ', $strArr) . "\n";