<?php
// 博客系统 - 用户与权限
class BlogUser {
    public ?int $id = null;
    public string $name;
    public string $email;
    public string $password;
    public string $role; // admin, editor, author, reader
    public string $status;
    public string $createdAt;

    public function __construct(array $data = []) {
        foreach ($data as $key => $value) {
            if (property_exists($this, $key)) $this->$key = $value;
        }
        if (!isset($this->createdAt)) $this->createdAt = date('Y-m-d H:i:s');
    }

    public static function create(string $name, string $email, string $password, string $role = 'reader'): self {
        $user = new self([
            'name' => $name,
            'email' => $email,
            'password' => password_hash($password, PASSWORD_DEFAULT),
            'role' => $role,
            'status' => 'active',
        ]);
        $id = BlogDB::getInstance()->insert('users', [
            'name' => $user->name,
            'email' => $user->email,
            'password' => $user->password,
            'role' => $user->role,
            'status' => $user->status,
            'created_at' => $user->createdAt,
        ]);
        $user->id = $id;
        return $user;
    }

    public static function find(int $id): ?self {
        $row = BlogDB::getInstance()->selectOne('users', ['id' => $id]);
        return $row ? new self($row) : null;
    }

    public static function findByEmail(string $email): ?self {
        $row = BlogDB::getInstance()->selectOne('users', ['email' => $email]);
        return $row ? new self($row) : null;
    }

    public static function all(int $limit = 50, int $offset = 0): array {
        $rows = BlogDB::getInstance()->select('users', [], $limit, $offset, 'id', 'DESC');
        return array_map(fn($r) => new self($r), $rows);
    }

    public function verifyPassword(string $password): bool {
        return password_verify($password, $this->password);
    }

    public function save(): void {
        BlogDB::getInstance()->update('users', ['id' => $this->id], [
            'name' => $this->name,
            'email' => $this->email,
            'role' => $this->role,
            'status' => $this->status,
        ]);
    }

    public function delete(): void {
        BlogDB::getInstance()->delete('users', ['id' => $this->id]);
    }

    public function can(string $permission): bool {
        $permissions = [
            'admin' => ['create_post', 'edit_post', 'delete_post', 'create_comment', 'delete_comment', 'manage_users', 'manage_tags'],
            'editor' => ['create_post', 'edit_post', 'create_comment', 'delete_comment', 'manage_tags'],
            'author' => ['create_post', 'edit_post', 'create_comment', 'delete_comment'],
            'reader' => ['create_comment'],
        ];
        return in_array($permission, $permissions[$this->role] ?? []);
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'role' => $this->role,
            'status' => $this->status,
            'created_at' => $this->createdAt,
        ];
    }
}
