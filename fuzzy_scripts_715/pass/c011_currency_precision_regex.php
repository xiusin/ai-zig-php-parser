<?php
// 极度混搭: 货币系统 + 精度运算 + 正则 + 字符串格式化 + 数组聚合
echo "=== c011: Currency + Precision + Regex + Formatting ===\n\n";

class Money {
    private int $cents;

    public function __construct(float|int|string $amount, string $currency = 'USD') {
        $this->cents = self::toCents($amount);
        $this->currency = $currency;
    }

    public string $currency;

    public static function toCents(float|int|string $amount): int {
        if (is_string($amount)) {
            $amount = (float)$amount;
        }
        return (int)round($amount * 100);
    }

    public static function fromCents(int $cents, string $currency = 'USD'): self {
        $m = new self(0, $currency);
        $m->cents = $cents;
        return $m;
    }

    public function getAmount(): float {
        return $this->cents / 100;
    }

    public function getCents(): int {
        return $this->cents;
    }

    public function add(self $other): self {
        return self::fromCents($this->cents + $other->cents, $this->currency);
    }

    public function subtract(self $other): self {
        return self::fromCents($this->cents - $other->cents, $this->currency);
    }

    public function multiply(float $factor): self {
        return self::fromCents((int)round($this->cents * $factor), $this->currency);
    }

    public function split(int $parts): array {
        $base = intdiv($this->cents, $parts);
        $remainder = $this->cents % $parts;
        $result = [];
        for ($i = 0; $i < $parts; $i++) {
            $c = $base + ($i < $remainder ? 1 : 0);
            $result[] = self::fromCents($c, $this->currency);
        }
        return $result;
    }

    public function format(): string {
        $sign = $this->cents < 0 ? '-' : '';
        $abs = abs($this->cents);
        $dollars = intdiv($abs, 100);
        $cents = $abs % 100;
        $symbol = match($this->currency) {
            'USD' => '$',
            'EUR' => '€',
            'CNY' => '¥',
            'GBP' => '£',
            default => '',
        };
        return $sign . $symbol . number_format($dollars, 0) . '.' . str_pad((string)$cents, 2, '0', STR_PAD_LEFT);
    }

    public function __toString(): string {
        return $this->format();
    }
}

class Invoice {
    private array $lineItems = [];

    public function add(string $desc, Money $price, int $qty = 1): self {
        $this->lineItems[] = [
            'desc' => $desc,
            'price' => $price,
            'qty' => $qty,
            'total' => $price->multiply($qty),
        ];
        return $this;
    }

    public function subtotal(): Money {
        $total = 0;
        foreach ($this->lineItems as $item) {
            $total += $item['total']->getCents();
        }
        return Money::fromCents($total);
    }

    public function tax(float $rate): Money {
        return $this->subtotal()->multiply($rate);
    }

    public function total(float $taxRate): Money {
        return $this->subtotal()->add($this->tax($taxRate));
    }

    public function print(float $taxRate): void {
        echo str_pad("Description", 30) . str_pad("Price", 12) . str_pad("Qty", 6) . str_pad("Total", 12) . "\n";
        echo str_repeat("-", 60) . "\n";
        foreach ($this->lineItems as $item) {
            echo str_pad($item['desc'], 30)
                . str_pad((string)$item['price'], 12)
                . str_pad((string)$item['qty'], 6)
                . str_pad((string)$item['total'], 12)
                . "\n";
        }
        echo str_repeat("-", 60) . "\n";
        echo str_pad("Subtotal", 48) . (string)$this->subtotal() . "\n";
        echo str_pad("Tax (" . ($taxRate * 100) . "%)", 48) . (string)$this->tax($taxRate) . "\n";
        echo str_pad("Total", 48) . (string)$this->total($taxRate) . "\n";
    }
}

// === 测试 ===

echo "--- Basic Money Operations ---\n";
$m1 = new Money(10.50);
$m2 = new Money(3.25);
echo "m1: $m1\n";
echo "m2: $m2\n";
echo "add: " . $m1->add($m2) . "\n";
echo "sub: " . $m1->subtract($m2) . "\n";
echo "mul: " . $m1->multiply(1.5) . "\n";

echo "\n--- Split (fair division) ---\n";
$bill = new Money(100.00);
$shares = $bill->split(3);
foreach ($shares as $i => $share) {
    echo "  Share " . ($i + 1) . ": $share\n";
}
echo "Verify sum: " . $bill . "\n";

echo "\n--- Multi-currency ---\n";
$usd = new Money(99.99, 'USD');
$eur = new Money(50.50, 'EUR');
$cny = new Money(888.88, 'CNY');
echo "USD: $usd EUR: $eur CNY: $cny\n";

echo "\n--- Invoice System ---\n";
$invoice = new Invoice();
$invoice->add("Widget A", new Money(12.99), 3);
$invoice->add("Widget B", new Money(25.00), 2);
$invoice->add("Service Fee", new Money(75.50), 1);
$invoice->add("Discount", new Money(-10.00), 1);
$invoice->print(0.08);

echo "\n--- String Parsing with Regex ---\n";
$prices = "Apple:1.25, Banana:0.75, Cherry:3.99, Date:2.50";
preg_match_all('/(\w+):(\d+\.?\d*)/', $prices, $matches);
foreach ($matches[1] as $i => $name) {
    $price = new Money($matches[2][$i]);
    echo "  $name: $price\n";
}

echo "\n--- Currency Conversion ---\n";
$rates = [
    'USD' => 1.0,
    'EUR' => 1.08,
    'CNY' => 0.14,
    'GBP' => 1.27,
];
foreach ($rates as $cur => $rate) {
    $m = new Money(100, $cur);
    $converted = $m->multiply($rate);
    echo "  100 $cur -> {$converted->format()} USD\n";
}

echo "\n=== c011 Done ===\n";
