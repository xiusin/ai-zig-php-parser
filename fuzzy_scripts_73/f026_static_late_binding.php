<?php
// f026: 后期静态绑定 (Late Static Binding)
echo "=== Late Static Binding ===\n\n";

class Base {
    protected static string $table = 'base_table';
    protected static array $config = ['base' => true];

    public static function create(): static {
        return new static();
    }

    public static function getTable(): string {
        return static::$table;
    }

    public static function getConfig(): array {
        return static::$config;
    }

    public static function getClassName(): string {
        return get_called_class();
    }

    public static function describe(): string {
        return static::getClassName() . ' uses ' . static::getTable();
    }

    public function getInfo(): string {
        return "Instance of " . get_class($this) . " (called: " . get_called_class() . ")";
    }
}

class User extends Base {
    protected static string $table = 'users_table';
    protected static array $config = ['base' => false, 'cache' => true];
}

class Admin extends User {
    protected static string $table = 'admins_table';
}

class Product extends Base {
    protected static string $table = 'products_table';
}

echo "--- Static Properties ---\n";
echo "Base::getTable(): " . Base::getTable() . "\n";
echo "User::getTable(): " . User::getTable() . "\n";
echo "Admin::getTable(): " . Admin::getTable() . "\n";
echo "Product::getTable(): " . Product::getTable() . "\n";

echo "\n--- get_called_class ---\n";
echo "Base::getClassName(): " . Base::getClassName() . "\n";
echo "User::getClassName(): " . User::getClassName() . "\n";
echo "Admin::getClassName(): " . Admin::getClassName() . "\n";

echo "\n--- static::create() ---\n";
$user = User::create();
echo "User::create() class: " . get_class($user) . "\n";
$admin = Admin::create();
echo "Admin::create() class: " . get_class($admin) . "\n";

echo "\n--- describe() ---\n";
echo Base::describe() . "\n";
echo User::describe() . "\n";
echo Admin::describe() . "\n";
echo Product::describe() . "\n";

echo "\n--- Instance getInfo ---\n";
$base = new Base();
echo $base->getInfo() . "\n";
echo $user->getInfo() . "\n";
echo $admin->getInfo() . "\n";

echo "\n--- Config ---\n";
foreach (Base::getConfig() as $k => $v) {
    echo "  Base config: $k=" . ($v ? 'true' : 'false') . "\n";
}
foreach (User::getConfig() as $k => $v) {
    echo "  User config: $k=" . ($v ? 'true' : 'false') . "\n";
}

echo "\n--- static::class ---\n";
echo "Base::class via static: " . Base::getClassName() . "\n";
echo "User::class via static: " . User::getClassName() . "\n";
