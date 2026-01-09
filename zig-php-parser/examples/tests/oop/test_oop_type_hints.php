<?php
// Type hints and return types
interface RepositoryInterface {
    public function find(int $id): ?array;
    public function findAll(): array;
    public function save(array $data): bool;
    public function delete(int $id): bool;
}

class UserRepository implements RepositoryInterface {
    private $data = [
        1 => ['id' => 1, 'name' => 'John', 'email' => 'john@example.com'],
        2 => ['id' => 2, 'name' => 'Jane', 'email' => 'jane@example.com'],
        3 => ['id' => 3, 'name' => 'Bob', 'email' => 'bob@example.com'],
    ];
    
    public function find(int $id): ?array {
        return $this->data[$id] ?? null;
    }
    
    public function findAll(): array {
        return array_values($this->data);
    }
    
    public function save(array $data): bool {
        if (!isset($data['id'])) {
            return false;
        }
        $this->data[$data['id']] = $data;
        return true;
    }
    
    public function delete(int $id): bool {
        if (!isset($this->data[$id])) {
            return false;
        }
        unset($this->data[$id]);
        return true;
    }
}

class UserService {
    private RepositoryInterface $repository;
    
    public function __construct(RepositoryInterface $repository) {
        $this->repository = $repository;
    }
    
    public function getUser(int $id): ?array {
        return $this->repository->find($id);
    }
    
    public function getAllUsers(): array {
        return $this->repository->findAll();
    }
    
    public function createUser(string $name, string $email): bool {
        $id = count($this->repository->findAll()) + 1;
        $data = [
            'id' => $id,
            'name' => $name,
            'email' => $email,
        ];
        return $this->repository->save($data);
    }
    
    public function deleteUser(int $id): bool {
        return $this->repository->delete($id);
    }
    
    public function searchUsers(string $term): array {
        $allUsers = $this->repository->findAll();
        return array_filter($allUsers, function($user) use ($term) {
            return strpos($user['name'], $term) !== false || 
                   strpos($user['email'], $term) !== false;
        });
    }
}

class Calculator {
    public function add(float $a, float $b): float {
        return $a + $b;
    }
    
    public function subtract(float $a, float $b): float {
        return $a - $b;
    }
    
    public function multiply(float $a, float $b): float {
        return $a * $b;
    }
    
    public function divide(float $a, float $b): float {
        if ($b == 0) {
            throw new InvalidArgumentException("Cannot divide by zero");
        }
        return $a / $b;
    }
    
    public function power(float $base, float $exponent): float {
        return pow($base, $exponent);
    }
    
    public function calculate(array $operations): float {
        $result = 0;
        foreach ($operations as $op) {
            $result = match($op['operator']) {
                'add' => $this->add($result, $op['value']),
                'subtract' => $this->subtract($result, $op['value']),
                'multiply' => $this->multiply($result, $op['value']),
                'divide' => $this->divide($result, $op['value']),
                'power' => $this->power($result, $op['value']),
                default => throw new InvalidArgumentException("Unknown operator"),
            };
        }
        return $result;
    }
}

// Test type hints
echo "=== Repository Testing ===\n";
$repository = new UserRepository();

echo "Find user 1:\n";
$user = $repository->find(1);
print_r($user);

echo "\nFind all users:\n";
$users = $repository->findAll();
foreach ($users as $u) {
    echo "  {$u['name']} ({$u['email']})\n";
}

echo "\nCreate new user:\n";
$result = $repository->save(['id' => 4, 'name' => 'Alice', 'email' => 'alice@example.com']);
echo "Result: " . ($result ? "Success" : "Failed") . "\n";

echo "\nDelete user 2:\n";
$result = $repository->delete(2);
echo "Result: " . ($result ? "Success" : "Failed") . "\n";

echo "\n=== Service Testing ===\n";
$service = new UserService($repository);

echo "Get user 1:\n";
$user = $service->getUser(1);
print_r($user);

echo "\nSearch users with 'Joh':\n";
$results = $service->searchUsers('Joh');
foreach ($results as $r) {
    echo "  {$r['name']}\n";
}

echo "\n=== Calculator Testing ===\n";
$calc = new Calculator();

echo "Add: " . $calc->add(10, 5) . "\n";
echo "Subtract: " . $calc->subtract(10, 5) . "\n";
echo "Multiply: " . $calc->multiply(10, 5) . "\n";
echo "Divide: " . $calc->divide(10, 5) . "\n";
echo "Power: " . $calc->power(2, 3) . "\n";

echo "\nCalculate with operations:\n";
$operations = [
    ['operator' => 'add', 'value' => 10],
    ['operator' => 'multiply', 'value' => 2],
    ['operator' => 'subtract', 'value' => 5],
];
$result = $calc->calculate($operations);
echo "Result: {$result}\n";

echo "\nDone\n";
