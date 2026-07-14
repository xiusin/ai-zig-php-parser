<?php
// 电商系统 - 用户模型
class User {
    private array $addresses = [];

    public function __construct(
        public readonly int $id,
        public readonly string $name,
        public readonly string $email,
        public readonly string $role = 'customer'
    ) {}

    public function addAddress(string $label, string $address): void {
        $this->addresses[$label] = $address;
    }

    public function getAddress(string $label): ?string {
        return $this->addresses[$label] ?? null;
    }

    public function getAddresses(): array {
        return $this->addresses;
    }

    public function isAdmin(): bool {
        return $this->role === 'admin';
    }

    public function __toString(): string {
        return sprintf("[%d] %s <%s> (%s)", $this->id, $this->name, $this->email, $this->role);
    }
}

class UserRepository {
    private array $users = [];
    private int $nextId = 1;

    public function create(string $name, string $email, string $role = 'customer'): User {
        $user = new User($this->nextId++, $name, $email, $role);
        $this->users[$user->id] = $user;
        return $user;
    }

    public function find(int $id): ?User {
        return $this->users[$id] ?? null;
    }

    public function findByEmail(string $email): ?User {
        foreach ($this->users as $user) {
            if ($user->email === $email) return $user;
        }
        return null;
    }

    public function count(): int {
        return count($this->users);
    }

    public function all(): array {
        return array_values($this->users);
    }
}
