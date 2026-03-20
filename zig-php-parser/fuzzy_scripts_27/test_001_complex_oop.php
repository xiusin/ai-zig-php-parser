<?php
// Test 001: Complex OOP with magic methods, traits, and reflections
trait Loggable {
    private array $logs = [];
    public function log(string $msg): void {
        $this->logs[] = date('Y-m-d H:i:s') . ': ' . $msg;
    }
    public function getLogs(): array {
        return $this->logs;
    }
}

interface Serializable {
    public function serialize(): array;
    public static function deserialize(array $data): self;
}

abstract class BaseEntity {
    use Loggable;
    protected static int $counter = 0;
    protected int $id;
    protected DateTime $createdAt;

    public function __construct() {
        $this->id = ++self::$counter;
        $this->createdAt = new DateTime();
        $this->log('Entity created: ' . $this->id);
    }

    abstract public function getType(): string;

    public function __sleep(): array {
        return ['id', 'createdAt'];
    }

    public function __wakeup(): void {
        $this->log('Entity awakened: ' . $this->id);
    }
}

class User extends BaseEntity implements Serializable {
    private string $name;
    private array $emails;
    private static array $instances = [];

    public function __construct(
        private readonly string $username,
        private mixed $password = null,
        ...$emails
    ) {
        parent::__construct();
        $this->emails = $emails;
        self::$instances[$this->id] = $this;
        $this->log("User constructed: $username");
    }

    public function getType(): string { return 'User'; }

    public function serialize(): array {
        return [
            'id' => $this->id,
            'username' => $this->username,
            'emails' => $this->emails,
            'created' => $this->createdAt->format('c'),
        ];
    }

    public static function deserialize(array $data): self {
        $u = new self($data['username']);
        $u->id = $data['id'];
        return $u;
    }

    public function __call(string $method, array $args): mixed {
        if (str_starts_with($method, 'get')) {
            $prop = strtolower(substr($method, 3));
            return $this->$prop ?? null;
        }
        throw new BadMethodCallException("Method $method does not exist");
    }

    public static function getInstance(int $id): ?self {
        return self::$instances[$id] ?? null;
    }

    public function __get(string $name): mixed {
        if ($name === 'virtual') {
            return "virtual_".$this->id;
        }
        throw new RuntimeException("Property $name does not exist");
    }

    public function __isset(string $name): bool {
        return isset($this->$name) || $name === 'virtual';
    }
}

$user = new User('admin', 'secret123', 'admin@example.com', 'root@example.com');
$user->log('Testing magic call');

echo "Type: " . $user->getType() . "\n";
echo "Username: " . $user->getUsername() . "\n";
echo "Email count: " . count($user->getEmails()) . "\n";
echo "Virtual: " . ($user->virtual ?? 'none') . "\n";
echo "Logs:\n";
foreach ($user->getLogs() as $log) {
    echo "  $log\n";
}

$serialized = $user->serialize();
echo "Serialized: " . json_encode($serialized) . "\n";

$reflection = new ReflectionClass($user);
echo "Is User final? " . ($reflection->isFinal() ? 'yes' : 'no') . "\n";
echo "Properties: " . implode(', ', array_map(fn($p) => $p->getName(), $reflection->getProperties())) . "\n";
echo "Methods: " . count($reflection->getMethods()) . " methods\n";