<?php
// Nullsafe运算符测试 (PHP 8.0+)

// 基础nullsafe操作
class User {
    public function __construct(
        public ?string $name,
        public ?Address $address = null
    ) {}
}

class Address {
    public function __construct(
        public string $city,
        public string $country
    ) {}

    public function getCity(): string {
        return $this->city;
    }
}

// 无nullsafe
$user1 = new User('Alice', new Address('NYC', 'USA'));
$user2 = new User('Bob');

// 传统方式检查null
$city1 = $user1->address !== null ? $user1->address->getCity() : null;
echo "Traditional city1: " . var_export($city1, true) . "\n";

// 使用nullsafe运算符
$city2 = $user1?->address?->getCity();
echo "Nullsafe city1: " . var_export($city2, true) . "\n";

$city3 = $user2?->address?->getCity();
echo "Nullsafe city2: " . var_export($city3, true) . "\n";

// 链式调用
class Company {
    public function __construct(
        public ?Department $department = null
    ) {}
}

class Department {
    public function __construct(
        public ?Manager $manager = null
    ) {}
}

class Manager {
    public function __construct(
        public string $name
    ) {}

    public function getName(): string {
        return $this->name;
    }
}

// 完整链条
$company1 = new Company(new Department(new Manager('John')));
$company2 = new Company();
$company3 = new Company(new Department());

echo "Manager 1: " . ($company1?->department?->manager?->getName() ?? 'No manager') . "\n";
echo "Manager 2: " . ($company2?->department?->manager?->getName() ?? 'No manager') . "\n";
echo "Manager 3: " . ($company3?->department?->manager?->getName() ?? 'No manager') . "\n";

// 与方法调用结合
class Service {
    private ?Repository $repo = null;

    public function setRepo(?Repository $repo): void {
        $this->repo = $repo;
    }

    public function getData(): ?string {
        return $this->repo?->find();
    }
}

class Repository {
    public function find(): string {
        return 'data found';
    }
}

$service = new Service();
echo "No repo: " . var_export($service->getData(), true) . "\n";
$service->setRepo(new Repository());
echo "With repo: " . $service->getData() . "\n";

// 数组访问
class Config {
    public function __construct(
        public ?array $settings = null
    ) {}

    public function getSettings(): ?array {
        return $this->settings;
    }
}

$config = new Config(['debug' => true, 'cache' => false]);
$configEmpty = new Config();

echo "Config debug: " . var_export($config?->getSettings()['debug'] ?? null, true) . "\n";
echo "Empty config debug: " . var_export($configEmpty?->getSettings()['debug'] ?? null, true) . "\n";

// 在表达式中使用
class Item {
    public function __construct(
        public ?float $price = null
    ) {}

    public function getPrice(): ?float {
        return $this->price;
    }
}

$item = new Item(99.99);
$itemNull = new Item();

$price1 = $item?->getPrice() ?? 0;
$price2 = $itemNull?->getPrice() ?? 0;
echo "Price 1: $price1\n";
echo "Price 2: $price2\n";

// 静态调用nullsafe不适用，但可以通过实例
class Factory {
    public static function create(): ?self {
        return new self();
    }

    public function getName(): string {
        return 'Factory';
    }
}

$factory = Factory::create();
echo "Factory name: " . ($factory?->getName() ?? 'No factory') . "\n";

// 复杂场景
class Order {
    public function __construct(
        public ?Customer $customer = null
    ) {}
}

class Customer {
    public function __construct(
        public ?Profile $profile = null
    ) {}
}

class Profile {
    public function __construct(
        public string $email
    ) {}

    public function getEmail(): string {
        return $this->email;
    }
}

$order = new Order(new Customer(new Profile('test@example.com')));
echo "Order email: " . ($order?->customer?->profile?->getEmail() ?? 'no email') . "\n";

$orderNoCustomer = new Order();
echo "Order no customer email: " . ($orderNoCustomer?->customer?->profile?->getEmail() ?? 'no email') . "\n";

echo "Nullsafe operator tests completed\n";
