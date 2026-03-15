<?php
// 测试51: 命名参数与位置参数混合、跳过默认参数
// 测试目的：验证PHP 8.0命名参数的灵活性和边界情况

// 复杂函数签名
function createOrder(
    string $product,
    int $quantity,
    float $price = 0.0,
    string $currency = 'USD',
    ?string $coupon = null,
    bool $express = false,
    array $options = []
): array {
    return [
        'product' => $product,
        'quantity' => $quantity,
        'price' => $price,
        'currency' => $currency,
        'coupon' => $coupon,
        'express' => $express,
        'options' => $options
    ];
}

// 全位置参数
$order1 = createOrder('Laptop', 2, 999.99, 'USD', null, true, ['gift_wrap' => true]);
echo "Order 1 (positional): {$order1['product']}, express={$order1['express']}\n";

// 全命名参数
$order2 = createOrder(
    product: 'Mouse',
    quantity: 5,
    price: 29.99,
    express: false,
    options: ['color' => 'black']
);
echo "Order 2 (named): {$order2['product']}, qty={$order2['quantity']}\n";

// 混合：位置参数后跟命名参数
$order3 = createOrder('Keyboard', 3, express: true, currency: 'EUR');
echo "Order 3 (mixed): {$order3['product']}, currency={$order3['currency']}, express={$order3['express']}\n";

// 跳过中间参数使用默认值
$order4 = createOrder('Monitor', 1, price: 299.99, express: true);
echo "Order 4 (skip defaults): {$order4['product']}, price={$order4['price']}, currency={$order4['currency']}\n";

// 类构造函数使用命名参数
class Payment {
    public function __construct(
        public string $method,
        public string $account,
        public float $amount = 0.0,
        public ?string $description = null,
        public array $metadata = []
    ) {}
    
    public function getSummary(): string {
        $desc = $this->description ?? 'No description';
        return "{$this->method}: {$this->amount} to {$this->account} ($desc)";
    }
}

$payment1 = new Payment('credit_card', '****1234', 150.00, description: 'Monthly subscription');
echo "Payment 1: " . $payment1->getSummary() . "\n";

$payment2 = new Payment(
    method: 'bank_transfer',
    account: 'ACC5678',
    amount: 5000.00,
    metadata: ['reference' => 'INV-001']
);
echo "Payment 2: " . $payment2->getSummary() . "\n";

// 可变参数与命名参数
function logMessage(string $level, string $message, ...$context): string {
    $formatted = sprintf("[%s] %s", $level, $message);
    if (!empty($context)) {
        $formatted .= " " . json_encode($context);
    }
    return $formatted;
}

$log1 = logMessage('ERROR', 'Connection failed', context: ['host' => 'localhost', 'port' => 3306]);
echo "$log1\n";

// 静态方法使用命名参数
class Config {
    private static array $settings = [];
    
    public static function set(string $key, mixed $value, bool $overwrite = true): void {
        if ($overwrite || !isset(self::$settings[$key])) {
            self::$settings[$key] = $value;
        }
    }
    
    public static function get(string $key, mixed $default = null): mixed {
        return self::$settings[$key] ?? $default;
    }
}

Config::set('app.name', 'MyApp', overwrite: false);
Config::set('debug', true);
echo "App name: " . Config::get('app.name') . "\n";

// 回调中使用命名参数
$orders = [
    ['product' => 'A', 'qty' => 2],
    ['product' => 'B', 'qty' => 5],
];
$created = array_map(
    fn($o) => createOrder(product: $o['product'], quantity: $o['qty'], express: $o['qty'] > 3),
    $orders
);
echo "Created " . count($created) . " orders\n";
?>
