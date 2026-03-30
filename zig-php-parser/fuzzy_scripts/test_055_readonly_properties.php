<?php
// 测试55: PHP 8.1 readonly属性 - 初始化后不可变的属性
// 测试目的：验证readonly属性的行为和边界情况

class ImmutableDTO {
    public function __construct(
        public readonly string $id,
        public readonly array $data,
        public readonly ?DateTime $createdAt = null
    ) {
        // readonly属性可以在构造函数中初始化
        // 但不能在此之后修改
    }
    
    public function getSummary(): string {
        $count = count($this->data);
        $time = $this->createdAt?->format('Y-m-d') ?? 'unknown';
        return "ID: {$this->id}, Items: $count, Created: $time";
    }
    
    // 不能在方法中修改readonly属性
    // public function setId(string $id): void {
    //     $this->id = $id; // 编译错误！
    // }
}

// 测试正常创建
$dto = new ImmutableDTO(
    id: 'user_123',
    data: ['name' => 'Alice', 'role' => 'admin'],
    createdAt: new DateTime()
);

echo "DTO Summary: " . $dto->getSummary() . "\n";
echo "ID: {$dto->id}\n";
echo "Data: " . json_encode($dto->data) . "\n";

// 尝试修改会导致错误（这里只是演示，实际会编译失败）
// $dto->id = 'new_id'; // Error: Cannot modify readonly property

// readonly属性的深不变性问题
class ShallowImmutable {
    public function __construct(
        public readonly array $items
    ) {}
}

$shallow = new ShallowImmutable(['a' => 1, 'b' => 2]);
// 数组本身不是只读的，只有属性引用是只读的
// $shallow->items = ['new']; // 错误
// 但可以修改数组内容（PHP的限制）
// $shallow->items['a'] = 100; // 这在PHP中是允许的

echo "Shallow items: " . json_encode($shallow->items) . "\n";

// 使用clone创建变体
class Config {
    public function __construct(
        public readonly string $environment,
        public readonly bool $debug,
        public readonly array $database
    ) {}
    
    public function withDebug(bool $debug): static {
        return new static(
            environment: $this->environment,
            debug: $debug,
            database: $this->database
        );
    }
    
    public function withDatabase(array $db): static {
        return new static(
            environment: $this->environment,
            debug: $this->debug,
            database: $db
        );
    }
}

$prodConfig = new Config(
    environment: 'production',
    debug: false,
    database: ['host' => 'db.prod.com', 'port' => 5432]
);

$devConfig = $prodConfig->withDebug(true);
$stagingConfig = $devConfig->withDatabase(['host' => 'db.staging.com', 'port' => 5432]);

echo "\nConfigs:\n";
echo "Prod: env={$prodConfig->environment}, debug=" . ($prodConfig->debug ? 'true' : 'false') . "\n";
echo "Dev: env={$devConfig->environment}, debug=" . ($devConfig->debug ? 'true' : 'false') . "\n";
echo "Staging: host={$stagingConfig->database['host']}\n";

// readonly属性与继承
class BaseConfig {
    public function __construct(
        public readonly string $version = '1.0.0'
    ) {}
}

class DerivedConfig extends BaseConfig {
    public function __construct(
        string $version,
        public readonly string $name
    ) {
        parent::__construct($version);
    }
}

$derived = new DerivedConfig('2.0.0', 'MyApp');
echo "\nDerived: version={$derived->version}, name={$derived->name}\n";

// 只读对象集合
class UserRepository {
    /** @var ImmutableDTO[] */
    private array $users = [];
    
    public function add(ImmutableDTO $user): void {
        $this->users[$user->id] = $user;
    }
    
    public function get(string $id): ?ImmutableDTO {
        return $this->users[$id] ?? null;
    }
    
    public function all(): array {
        return $this->users;
    }
}

$repo = new UserRepository();
$repo->add(new ImmutableDTO('u1', ['name' => 'Alice']));
$repo->add(new ImmutableDTO('u2', ['name' => 'Bob']));

echo "\nRepository users:\n";
foreach ($repo->all() as $user) {
    echo "  {$user->id}: " . json_encode($user->data) . "\n";
}
?>
