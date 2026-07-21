<?php
// 极度混搭: 深层继承链 + __set_state/__serialize/__unserialize + 方法重写 + final + static属性共享
echo "=== f004: Deep Inheritance + Serialization + Final + Static ===\n";

class BaseEntity {
    protected static int $entityCount = 0;
    protected array $meta = [];

    public function __construct(
        public readonly string $uuid
    ) {
        static::$entityCount++;
    }

    public function setMeta(string $key, mixed $value): void {
        $this->meta[$key] = $value;
    }

    public function getMeta(string $key, mixed $default = null): mixed {
        return $this->meta[$key] ?? $default;
    }

    public function __serialize(): array {
        return ['uuid' => $this->uuid, 'meta' => $this->meta];
    }

    public function __unserialize(array $data): void {
        $this->uuid = $data['uuid'];
        $this->meta = $data['meta'];
    }

    final public function getUuid(): string {
        return $this->uuid;
    }

    public static function getEntityCount(): int {
        return static::$entityCount;
    }
}

class User extends BaseEntity {
    protected static int $entityCount = 0;

    public function __construct(
        string $uuid,
        public string $name,
        public string $email,
        public array $roles = []
    ) {
        parent::__construct($uuid);
    }

    public function __serialize(): array {
        return array_merge(parent::__serialize(), [
            'name' => $this->name,
            'email' => $this->email,
            'roles' => $this->roles,
        ]);
    }

    public function __unserialize(array $data): void {
        parent::__unserialize($data);
        $this->name = $data['name'];
        $this->email = $data['email'];
        $this->roles = $data['roles'];
    }

    public function hasRole(string $role): bool {
        return in_array($role, $this->roles);
    }

    public function __toString(): string {
        return sprintf("User[%s]{%s, %s, roles=[%s]}", $this->uuid, $this->name, $this->email, implode(',', $this->roles));
    }
}

class AdminUser extends User {
    protected static int $entityCount = 0;
    private array $permissions = [];

    public function __construct(
        string $uuid,
        string $name,
        string $email,
        array $permissions = []
    ) {
        parent::__construct($uuid, $name, $email, ['admin']);
        $this->permissions = $permissions;
    }

    public function __serialize(): array {
        return array_merge(parent::__serialize(), ['permissions' => $this->permissions]);
    }

    public function __unserialize(array $data): void {
        parent::__unserialize($data);
        $this->permissions = $data['permissions'];
    }

    public function hasPermission(string $perm): bool {
        return in_array($perm, $this->permissions) || in_array('*', $this->permissions);
    }

    public function __toString(): string {
        return sprintf("AdminUser[%s]{%s, perms=[%s]}", $this->uuid, $this->name, implode(',', $this->permissions));
    }
}

// 测试
$user = new User("U001", "Alice", "alice@example.com", ['user', 'editor']);
$user->setMeta('created', '2025-01-01');
$user->setMeta('ip', '192.168.1.1');
echo $user . "\n";
echo "Has editor role: " . var_export($user->hasRole('editor'), true) . "\n";
echo "Meta created: " . $user->getMeta('created') . "\n";

// 序列化/反序列化
$serialized = $user->__serialize();
echo "Serialized: " . json_encode($serialized) . "\n";

$user2 = new User("TEMP", "TEMP", "TEMP");
$user2->__unserialize($serialized);
echo "Unserialized: $user2\n";

// Admin
$admin = new AdminUser("A001", "Bob", "bob@example.com", ['read', 'write', 'delete']);
echo $admin . "\n";
echo "Has delete: " . var_export($admin->hasPermission('delete'), true) . "\n";
echo "Has execute: " . var_export($admin->hasPermission('execute'), true) . "\n";

$superAdmin = new AdminUser("A002", "Super", "super@example.com", ['*']);
echo "Super has anything: " . var_export($superAdmin->hasPermission('anything'), true) . "\n";

// 计数
echo "BaseEntity count: " . BaseEntity::getEntityCount() . "\n";
echo "User count: " . User::getEntityCount() . "\n";
echo "AdminUser count: " . AdminUser::getEntityCount() . "\n";

// final 方法测试（不能重写getUuid）
echo "User UUID: " . $user->getUuid() . "\n";
echo "Admin UUID: " . $admin->getUuid() . "\n";

echo "=== f004 Done ===\n";
