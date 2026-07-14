<?php
// 类型安全构建器：流式接口/不可变对象/校验
echo "=== Type-Safe Builder ===\n\n";

// 不可变值对象
final class Email {
    public function __construct(public readonly string $value) {
        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidArgumentException("Invalid email: $value");
        }
    }

    public function __toString(): string { return $this->value; }
    public function getDomain(): string { return substr($this->value, strpos($this->value, '@') + 1); }
    public function getLocalPart(): string { return substr($this->value, 0, strpos($this->value, '@')); }
}

final class Money {
    public function __construct(
        public readonly int $amount,
        public readonly string $currency = 'USD'
    ) {
        if ($amount < 0) throw new InvalidArgumentException("Money cannot be negative");
    }

    public function add(Money $other): Money {
        if ($this->currency !== $other->currency) {
            throw new InvalidArgumentException("Currency mismatch: {$this->currency} vs {$other->currency}");
        }
        return new Money($this->amount + $other->amount, $this->currency);
    }

    public function subtract(Money $other): Money {
        return new Money($this->amount - $other->amount, $this->currency);
    }

    public function multiply(int $factor): Money {
        return new Money($this->amount * $factor, $this->currency);
    }

    public function format(): string {
        return sprintf("%s%.2f", $this->currency, $this->amount / 100);
    }
}

final class Address {
    public function __construct(
        public readonly string $street,
        public readonly string $city,
        public readonly string $state,
        public readonly string $zip,
        public readonly string $country = 'US'
    ) {}

    public function __toString(): string {
        return "$this->street, $this->city, $this->state $this->zip, $this->country";
    }
}

// User 不可变对象
final class User {
    public function __construct(
        public readonly string $id,
        public readonly string $name,
        public readonly Email $email,
        public readonly int $age,
        public readonly ?Address $address = null,
        public readonly array $roles = [],
        public readonly ?Money $balance = null,
        public readonly array $metadata = []
    ) {}

    public function withName(string $name): self {
        return new self($this->id, $name, $this->email, $this->age, $this->address, $this->roles, $this->balance, $this->metadata);
    }

    public function withAddress(Address $address): self {
        return new self($this->id, $this->name, $this->email, $this->age, $address, $this->roles, $this->balance, $this->metadata);
    }

    public function withRole(string $role): self {
        if (in_array($role, $this->roles)) return $this;
        return new self($this->id, $this->name, $this->email, $this->age, $this->address, [...$this->roles, $role], $this->balance, $this->metadata);
    }

    public function withBalance(Money $balance): self {
        return new self($this->id, $this->name, $this->email, $this->age, $this->address, $this->roles, $balance, $this->metadata);
    }

    public function hasRole(string $role): bool { return in_array($role, $this->roles); }
}

// Builder
class UserBuilder {
    private ?string $id = null;
    private ?string $name = null;
    private ?Email $email = null;
    private ?int $age = null;
    private ?Address $address = null;
    private array $roles = [];
    private ?Money $balance = null;
    private array $metadata = [];
    private array $errors = [];

    public function setId(string $id): self { $this->id = $id; return $this; }
    public function setName(string $name): self { $this->name = $name; return $this; }

    public function setEmail(string $email): self {
        try {
            $this->email = new Email($email);
        } catch (InvalidArgumentException $e) {
            $this->errors[] = $e->getMessage();
        }
        return $this;
    }

    public function setAge(int $age): self {
        if ($age < 0 || $age > 150) {
            $this->errors[] = "Invalid age: $age";
        } else {
            $this->age = $age;
        }
        return $this;
    }

    public function setAddress(string $street, string $city, string $state, string $zip, string $country = 'US'): self {
        $this->address = new Address($street, $city, $state, $zip, $country);
        return $this;
    }

    public function addRole(string $role): self { $this->roles[] = $role; return $this; }

    public function setBalance(int $cents, string $currency = 'USD'): self {
        $this->balance = new Money($cents, $currency);
        return $this;
    }

    public function addMetadata(string $key, mixed $value): self {
        $this->metadata[$key] = $value;
        return $this;
    }

    public function validate(): array {
        $errors = [...$this->errors];
        if ($this->id === null) $errors[] = "ID is required";
        if ($this->name === null || trim($this->name) === '') $errors[] = "Name is required";
        if ($this->email === null) $errors[] = "Email is required";
        if ($this->age === null) $errors[] = "Age is required";
        return $errors;
    }

    public function build(): User {
        $errors = $this->validate();
        if (!empty($errors)) {
            throw new RuntimeException("Validation failed: " . implode('; ', $errors));
        }
        return new User(
            $this->id, $this->name, $this->email, $this->age,
            $this->address, $this->roles, $this->balance, $this->metadata
        );
    }

    public function reset(): self {
        $this->id = $this->name = $this->email = null;
        $this->age = null; $this->address = null;
        $this->roles = []; $this->balance = null;
        $this->metadata = []; $this->errors = [];
        return $this;
    }
}

// === 测试 ===
echo "--- Builder Pattern ---\n";

$builder = new UserBuilder();

$user = $builder
    ->setId('USR-001')
    ->setName('Alice Johnson')
    ->setEmail('alice@example.com')
    ->setAge(30)
    ->setAddress('123 Main St', 'NYC', 'NY', '10001')
    ->addRole('admin')
    ->addRole('user')
    ->setBalance(50000)
    ->addMetadata('department', 'Engineering')
    ->addMetadata('joined', '2024-01-15')
    ->build();

echo "ID: {$user->id}\n";
echo "Name: {$user->name}\n";
echo "Email: {$user->email}\n";
echo "Domain: {$user->email->getDomain()}\n";
echo "Age: {$user->age}\n";
echo "Address: {$user->address}\n";
echo "Roles: " . implode(', ', $user->roles) . "\n";
echo "Balance: {$user->balance->format()}\n";
echo "Metadata: " . json_encode($user->metadata) . "\n";

// 不可变更新
echo "\n--- Immutable Updates ---\n";

$user2 = $user
    ->withName('Alice Smith')
    ->withRole('manager')
    ->withBalance(new Money(75000));

echo "Original name: {$user->name}\n";
echo "Updated name: {$user2->name}\n";
echo "Original roles: " . implode(', ', $user->roles) . "\n";
echo "Updated roles: " . implode(', ', $user2->roles) . "\n";
echo "Original balance: {$user->balance->format()}\n";
echo "Updated balance: {$user2->balance->format()}\n";

// Money 运算
echo "\n--- Money Operations ---\n";

$price = new Money(9999);  // $99.99
$tax = new Money(800);     // $8.00
$total = $price->add($tax);
$discount = new Money(500); // $5.00
$final = $total->subtract($discount);

echo "Price: {$price->format()}\n";
echo "Tax: {$tax->format()}\n";
echo "Total: {$total->format()}\n";
echo "Discount: {$discount->format()}\n";
echo "Final: {$final->format()}\n";
echo "3x final: {$final->multiply(3)->format()}\n";

// 验证失败测试
echo "\n--- Validation Errors ---\n";

$badBuilder = new UserBuilder();
$badBuilder->setEmail('not-an-email');
$badBuilder->setAge(200);

$errors = $badBuilder->validate();
echo "Validation errors:\n";
foreach ($errors as $err) {
    echo "  - $err\n";
}

try {
    $badBuilder->build();
} catch (RuntimeException $e) {
    echo "Build failed: {$e->getMessage()}\n";
}

// Email 校验
echo "\n--- Email Validation ---\n";

$emails = ['valid@test.com', 'invalid', '@nodomain.com', 'test@', 'good.email+tag@domain.co.uk'];
foreach ($emails as $email) {
    try {
        $e = new Email($email);
        echo "  $email -> valid (local: {$e->getLocalPart()}, domain: {$e->getDomain()})\n";
    } catch (InvalidArgumentException $ex) {
        echo "  $email -> invalid\n";
    }
}

// Builder 重置
echo "\n--- Builder Reset ---\n";
$builder->reset();
$user3 = $builder
    ->setId('USR-002')
    ->setName('Bob')
    ->setEmail('bob@test.com')
    ->setAge(25)
    ->build();
echo "New user: {$user3->name} ({$user3->email})\n";
echo "Has address: " . ($user3->address !== null ? 'true' : 'false') . "\n";
