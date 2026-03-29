<?php
// 测试48: 空安全运算符长链与混合访问 - PHP 8.0特性
// 测试目的：验证?->运算符在复杂链式调用中的行为

class Database {
    public ?Connection $connection = null;
    public function __construct() {
        $this->connection = new Connection();
    }
}

class Connection {
    public ?QueryBuilder $query = null;
    public function __construct() {
        $this->query = new QueryBuilder();
    }
    public function ping(): string {
        return "pong";
    }
}

class QueryBuilder {
    public ?Result $lastResult = null;
    public function select(string $table): self {
        return $this;
    }
    public function where(string $condition): self {
        return $this;
    }
    public function execute(): ?Result {
        return new Result(['id' => 1, 'name' => 'Test']);
    }
}

class Result {
    public ?array $data = null;
    public function __construct(?array $data) {
        $this->data = $data;
    }
    public function first(): ?array {
        return $this->data ?? null;
    }
    public function count(): int {
        return count($this->data ?? []);
    }
}

// 场景1：全部为空
$nullDb = new Database();
$nullDb->connection = null;
$chainResult = $nullDb?->connection?->query?->execute()?->first()['name'] ?? 'fallback';
echo "Null chain result: $chainResult
";

// 场景2：中间环节为空
$partialDb = new Database();
$partialDb->connection->query = null;
$middleNull = $partialDb?->connection?->query?->execute()?->data ?? ['empty' => true];
echo "Middle null: " . json_encode($middleNull) . "
";

// 场景3：完整链式调用
$db = new Database();
$userName = $db?->connection?->query?->execute()?->first()['name'] ?? 'unknown';
echo "User name: $userName
";

// 场景4：与方法调用结合
class User {
    public ?Profile $profile = null;
    public function __construct() { $this->profile = new Profile(); }
    public function getName(): string { return "User"; }
}

class Profile {
    public ?Address $address = null;
    public function __construct() { $this->address = new Address(); }
    public function getBio(): string { return "Bio here"; }
}

class Address {
    public ?string $city = null;
    public function __construct() { $this->city = "Beijing"; }
    public function getCountry(): string { return "China"; }
}

$user = new User();
$location = $user?->profile?->address?->city ?? 'Unknown City';
$country = $user?->profile?->address?->getCountry() ?? 'Unknown';
echo "Location: $location, Country: $country
";

// 场景5：数组访问混合
$response = [
    'data' => [
        'user' => new User()
    ]
];
$bio = $response['data']['user']?->profile?->getBio() ?? 'No bio';
echo "Bio: $bio
";

// 场景6：null安全与方法链
$maybeUser = null;
$result1 = $maybeUser?->getName() ?? 'Anonymous';
echo "Maybe user: $result1
";

$maybeUser = new User();
$result2 = $maybeUser?->getName() ?? 'Anonymous';
echo "Maybe user with value: $result2
";

// 场景7：复杂嵌套空安全
$config = [
    'database' => [
        'primary' => new Database(),
        'replica' => null
    ]
];
$primaryPing = $config['database']['primary']?->connection?->ping() ?? 'no connection';
$replicaPing = $config['database']['replica']?->connection?->ping() ?? 'no replica';
echo "Primary: $primaryPing, Replica: $replicaPing
";
?>