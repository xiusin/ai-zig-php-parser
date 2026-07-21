<?php
// 极度混搭: 策略模式 + 动态切换 + 闭包策略 + 组合策略 + 上下文
echo "=== f036: Strategy + Dynamic Switch + Closure Strategies ===\n";

interface PricingStrategy {
    public function calculate(float $basePrice, array $context): float;
    public function getName(): string;
}

class RegularPricing implements PricingStrategy {
    public function calculate(float $basePrice, array $context): float { return $basePrice; }
    public function getName(): string { return 'regular'; }
}

class DiscountPricing implements PricingStrategy {
    public function __construct(private float $discount) {}
    public function calculate(float $basePrice, array $context): float {
        return $basePrice * (1 - $this->discount);
    }
    public function getName(): string { return "discount_" . (int)($this->discount * 100); }
}

class BulkPricing implements PricingStrategy {
    public function calculate(float $basePrice, array $context): float {
        $qty = $context['quantity'] ?? 1;
        if ($qty >= 100) return $basePrice * 0.7;
        if ($qty >= 50) return $basePrice * 0.8;
        if ($qty >= 10) return $basePrice * 0.9;
        return $basePrice;
    }
    public function getName(): string { return 'bulk'; }
}

class TieredPricing implements PricingStrategy {
    private array $tiers;

    public function __construct(array $tiers) { $this->tiers = $tiers; }

    public function calculate(float $basePrice, array $context): float {
        $qty = $context['quantity'] ?? 1;
        $price = 0;
        $remaining = $qty;
        foreach ($this->tiers as $threshold => $rate) {
            if ($remaining <= 0) break;
            $atThisTier = min($remaining, $threshold);
            $price += $atThisTier * $basePrice * $rate;
            $remaining -= $atThisTier;
        }
        return $price;
    }
    public function getName(): string { return 'tiered'; }
}

class ClosurePricing implements PricingStrategy {
    private \Closure $fn;
    private string $name;

    public function __construct(callable $fn, string $name) {
        $this->fn = \Closure::fromCallable($fn);
        $this->name = $name;
    }

    public function calculate(float $basePrice, array $context): float {
        return ($this->fn)($basePrice, $context);
    }
    public function getName(): string { return $this->name; }
}

class PricingContext {
    private PricingStrategy $strategy;

    public function __construct(private PricingStrategy $default) {
        $this->strategy = $default;
    }

    public function setStrategy(PricingStrategy $strategy): self {
        $this->strategy = $strategy;
        return $this;
    }

    public function calculate(float $basePrice, array $context = []): float {
        return $this->strategy->calculate($basePrice, $context);
    }

    public function getStrategyName(): string { return $this->strategy->getName(); }
}

// 测试
$ctx = new PricingContext(new RegularPricing());

$products = [
    ['name' => 'Widget', 'price' => 10.00, 'qty' => 5],
    ['name' => 'Gadget', 'price' => 25.00, 'qty' => 50],
    ['name' => 'Gizmo', 'price' => 5.00, 'qty' => 200],
];

echo "--- Regular ---\n";
foreach ($products as $p) {
    $total = $ctx->calculate($p['price'], ['quantity' => $p['qty']]);
    echo "  {$p['name']}: \${$p['price']} × {$p['qty']} = \$" . number_format($total * $p['qty'], 2) . "\n";
}

echo "\n--- 20% Discount ---\n";
$ctx->setStrategy(new DiscountPricing(0.2));
foreach ($products as $p) {
    $unit = $ctx->calculate($p['price'], ['quantity' => $p['qty']]);
    echo "  {$p['name']}: \$$unit × {$p['qty']} = \$" . number_format($unit * $p['qty'], 2) . "\n";
}

echo "\n--- Bulk ---\n";
$ctx->setStrategy(new BulkPricing());
foreach ($products as $p) {
    $unit = $ctx->calculate($p['price'], ['quantity' => $p['qty']]);
    echo "  {$p['name']}: \$$unit × {$p['qty']} = \$" . number_format($unit * $p['qty'], 2) . "\n";
}

echo "\n--- Tiered (1-10:100%, 11-50:90%, 51+:80%) ---\n";
$ctx->setStrategy(new TieredPricing([10 => 1.0, 40 => 0.9, 999 => 0.8]));
foreach ($products as $p) {
    $total = $ctx->calculate($p['price'], ['quantity' => $p['qty']]);
    echo "  {$p['name']}: qty={$p['qty']} total=\$" . number_format($total, 2) . "\n";
}

echo "\n--- Closure (loyalty points) ---\n";
$ctx->setStrategy(new ClosurePricing(function($base, $ctx) {
    $points = $ctx['loyalty_points'] ?? 0;
    $discount = min($points / 1000, 0.5);
    return $base * (1 - $discount);
}, 'loyalty'));
echo "  Base \$100, 500 points: \$" . number_format($ctx->calculate(100, ['loyalty_points' => 500]), 2) . "\n";
echo "  Base \$100, 2000 points: \$" . number_format($ctx->calculate(100, ['loyalty_points' => 2000]), 2) . "\n";

echo "\nStrategy: " . $ctx->getStrategyName() . "\n";
echo "=== f036 Done ===\n";
