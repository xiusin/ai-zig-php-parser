<?php
// Test 026: Readonly properties, readonly classes (PHP 8.2), and immutability
class ReadonlyLab {
    public function __construct(
        public readonly string $name,
        public readonly int $value,
        public readonly array $tags = [],
        private readonly DateTime $created = new DateTime()
    ) {}

    public function getCreated(): DateTime {
        return $this->created;
    }

    public function with(string $name, int $value): array {
        return [
            'name' => $name,
            'value' => $value,
            'tags' => $this->tags,
        ];
    }
}

readonly class ImmutableUser {
    public function __construct(
        public string $name,
        public int $id,
        public array $permissions = []
    ) {}

    public function withPermission(string $perm): array {
        return [
            'name' => $this->name,
            'id' => $this->id,
            'permissions' => [...$this->permissions, $perm],
        ];
    }
}

class ImmutableConfig {
    private array $secrets = ['api_key' => 'secret123'];

    public function __construct(
        public readonly string $host,
        public readonly int $port
    ) {}

    public function getSecrets(): array {
        return $this->secrets;
    }

    public function withPort(int $newPort): array {
        return [
            'host' => $this->host,
            'port' => $newPort,
            'secrets' => $this->secrets,
        ];
    }
}

echo "=== Readonly properties ===\n";
$lab = new ReadonlyLab('Test', 42, ['php', 'zig']);
echo "Name: {$lab->name}\n";
echo "Value: {$lab->value}\n";
echo "Tags: " . implode(',', $lab->tags) . "\n";
echo "Created: " . $lab->getCreated()->format('Y-m-d') . "\n";

echo "\n=== Readonly class (PHP 8.2) ===\n";
$user = new ImmutableUser('Alice', 1, ['read', 'write']);
echo "User: {$user->name}, ID: {$user->id}\n";
echo "Permissions: " . implode(',', $user->permissions) . "\n";

$updated = $user->withPermission('delete');
echo "Updated permissions: " . implode(',', $updated['permissions']) . "\n";

echo "\n=== ImmutableConfig with secrets ===\n";
$config = new ImmutableConfig('localhost', 8080);
echo "Host: {$config->host}, Port: {$config->port}\n";
echo "Secrets: " . json_encode($config->getSecrets()) . "\n";

$newConfig = $config->withPort(443);
echo "New config port: {$newConfig['port']}\n";

echo "\n=== Clone with modification (simulating with() methods) ===\n";
$original = new ReadonlyLab('Original', 100);
echo "Original: {$original->name} = {$original->value}\n";

$withMethod = $original->with('Modified', 200);
echo "With: {$withMethod['name']} = {$withMethod['value']}\n";
echo "Original still: {$original->name} = {$original->value}\n";

echo "\n=== Readonly and named arguments ===\n";
function createReadonly(string $name, int $value, array $tags = []): array {
    return ['name' => $name, 'value' => $value, 'tags' => $tags];
}

$result = createReadonly(
    name: 'Named',
    value: 999,
    tags: ['named', 'readonly']
);
echo "Named result: " . json_encode($result) . "\n";

echo "\n=== Readonly with Countable & Traversable via interface ===\n";
class CountableTraversable implements Countable, Traversable {
    private array $data;
    public function __construct(array $data) {
        $this->data = $data;
    }
    public function count(): int {
        return count($this->data);
    }
    public function getIterator(): Iterator {
        return new ArrayIterator($this->data);
    }
}

class IntersectionLab {
    public function __construct(
        public readonly CountableTraversable $iterable
    ) {}
}

$it = new IntersectionLab(new CountableTraversable([1, 2, 3]));
echo "Has iterable: " . ($it->iterable !== null ? 'yes' : 'no') . "\n";
echo "Count: " . count($it->iterable) . "\n";