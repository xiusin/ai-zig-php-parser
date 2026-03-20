<?php
// Test 103: __toString, Stringable
class ToStringImpl implements Stringable {
    public function __construct(private string $value) {}

    public function __toString(): string {
        return $this->value;
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

echo "=== __toString ===\n";
$obj = new ToStringImpl('Hello World');
echo "Stringable object: $obj\n";

echo "\n=== Chained __toString ===\n";
$chain = new ChainToString();
$chain->add('one')->add('two')->add('three');
echo "Chain: $chain\n";

echo "\n=== Stringable instanceof ===\n";
echo "obj instanceof Stringable: " . ($obj instanceof Stringable ? 'yes' : 'no') . "\n";
echo "chain instanceof Stringable: " . ($chain instanceof Stringable ? 'yes' : 'no') . "\n";

echo "\n=== String casting ===\n";
echo "(string)obj: " . (string)$obj . "\n";

echo "\n=== In function expecting Stringable ===\n";
function expectStringable(Stringable $s): string {
    return $s->__toString();
}
echo "expectStringable(obj): " . expectStringable($obj) . "\n";