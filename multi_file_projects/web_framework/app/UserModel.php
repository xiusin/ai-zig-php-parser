<?php
// 用户模型
class User extends Model {
    protected string $table = 'users';
    protected array $fillable = ['name', 'email', 'password', 'role', 'status'];
    protected array $hidden = ['password'];
    protected array $casts = [
        'id' => 'integer',
        'status' => 'string',
    ];

    public function isAdmin(): bool {
        return $this->role === 'admin';
    }

    public function isActive(): bool {
        return $this->status === 'active';
    }

    public function posts(): array {
        return Post::where('user_id', $this->id)->get();
    }

    public static function findByEmail(string $email): ?self {
        $row = Database::getInstance()->table('users')->where('email', $email)->first();
        if ($row) {
            $model = new self();
            $model->forceFill($row);
            $model->exists = true;
            return $model;
        }
        return null;
    }

    public function verifyPassword(string $password): bool {
        return password_verify($password, $this->attributes['password'] ?? '');
    }

    public static function hashPassword(string $password): string {
        return password_hash($password, PASSWORD_DEFAULT);
    }
}
