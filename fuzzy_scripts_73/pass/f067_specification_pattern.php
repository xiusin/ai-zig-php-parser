<?php
// 规约模式：业务规则组合/AND/OR/NOT
echo "=== Specification Pattern ===\n\n";

class Order {
    public function __construct(
        public int $id,
        public float $total,
        public string $status,
        public string $customerType,
        public int $itemCount,
        public string $country,
        public bool $isExpress
    ) {}
}

interface Specification {
    public function isSatisfiedBy($candidate): bool;
    public function and(Specification $other): Specification;
    public function or(Specification $other): Specification;
    public function not(): Specification;
}

abstract class AbstractSpec implements Specification {
    public function and(Specification $other): Specification { return new AndSpec($this, $other); }
    public function or(Specification $other): Specification { return new OrSpec($this, $other); }
    public function not(): Specification { return new NotSpec($this); }
}

class AndSpec extends AbstractSpec {
    public function __construct(private Specification $a, private Specification $b) {}
    public function isSatisfiedBy($candidate): bool {
        return $this->a->isSatisfiedBy($candidate) && $this->b->isSatisfiedBy($candidate);
    }
}

class OrSpec extends AbstractSpec {
    public function __construct(private Specification $a, private Specification $b) {}
    public function isSatisfiedBy($candidate): bool {
        return $this->a->isSatisfiedBy($candidate) || $this->b->isSatisfiedBy($candidate);
    }
}

class NotSpec extends AbstractSpec {
    public function __construct(private Specification $spec) {}
    public function isSatisfiedBy($candidate): bool {
        return !$this->spec->isSatisfiedBy($candidate);
    }
}

// 具体规约
class TotalOverSpec extends AbstractSpec {
    public function __construct(private float $threshold) {}
    public function isSatisfiedBy($o): bool { return $o->total > $this->threshold; }
}

class StatusSpec extends AbstractSpec {
    public function __construct(private string $status) {}
    public function isSatisfiedBy($o): bool { return $o->status === $this->status; }
}

class CustomerTypeSpec extends AbstractSpec {
    public function __construct(private string $type) {}
    public function isSatisfiedBy($o): bool { return $o->customerType === $this->type; }
}

class CountrySpec extends AbstractSpec {
    public function __construct(private string $country) {}
    public function isSatisfiedBy($o): bool { return $o->country === $this->country; }
}

class ExpressSpec extends AbstractSpec {
    public function isSatisfiedBy($o): bool { return $o->isExpress; }
}

class ItemCountSpec extends AbstractSpec {
    public function __construct(private int $min, private int $max = PHP_INT_MAX) {}
    public function isSatisfiedBy($o): bool { return $o->itemCount >= $this->min && $o->itemCount <= $this->max; }
}

// 创建订单数据
$orders = [
    new Order(1, 150.00, 'pending', 'regular', 3, 'US', false),
    new Order(2, 500.00, 'shipped', 'vip', 10, 'US', true),
    new Order(3, 75.00, 'pending', 'regular', 2, 'CN', false),
    new Order(4, 1200.00, 'completed', 'vip', 5, 'CN', true),
    new Order(5, 300.00, 'cancelled', 'regular', 8, 'JP', false),
    new Order(6, 50.00, 'pending', 'vip', 1, 'US', true),
    new Order(7, 800.00, 'shipped', 'regular', 15, 'JP', true),
    new Order(8, 250.00, 'pending', 'vip', 4, 'CN', false),
];

// 定义业务规则
echo "--- Business Rule Queries ---\n\n";

// 1. VIP 客户且总金额 > 200
$vipHighValue = (new CustomerTypeSpec('vip'))->and(new TotalOverSpec(200));
echo "VIP customers with total > 200:\n";
foreach ($orders as $o) {
    if ($vipHighValue->isSatisfiedBy($o)) {
        echo "  Order #{$o->id}: \${$o->total} ({$o->customerType})\n";
    }
}

// 2. 待处理且（美国或加拿大）且非快递
$pendingUSorCN = (new StatusSpec('pending'))
    ->and((new CountrySpec('US'))->or(new CountrySpec('CN')))
    ->and((new ExpressSpec())->not());
echo "\nPending orders in US/CN that are NOT express:\n";
foreach ($orders as $o) {
    if ($pendingUSorCN->isSatisfiedBy($o)) {
        echo "  Order #{$o->id}: {$o->status} {$o->country} express=" . ($o->isExpress ? 'Y' : 'N') . "\n";
    }
}

// 3. 总金额 > 100 且商品数 3-10 或 快递订单
$complexRule = (new TotalOverSpec(100))
    ->and(new ItemCountSpec(3, 10))
    ->or(new ExpressSpec());
echo "\nOrders: (total > 100 AND items 3-10) OR express:\n";
foreach ($orders as $o) {
    if ($complexRule->isSatisfiedBy($o)) {
        echo "  Order #{$o->id}: \${$o->total}, {$o->itemCount} items, express=" . ($o->isExpress ? 'Y' : 'N') . "\n";
    }
}

// 4. 已取消或（非 VIP 且总金额 < 100）
$cancelledOrCheap = (new StatusSpec('cancelled'))
    ->or((new CustomerTypeSpec('vip'))->not()->and(new TotalOverSpec(100))->not());
echo "\nCancelled OR (not VIP AND total <= 100):\n";
foreach ($orders as $o) {
    if ($cancelledOrCheap->isSatisfiedBy($o)) {
        echo "  Order #{$o->id}: {$o->status} {$o->customerType} \${$o->total}\n";
    }
}

// 统计
echo "\n--- Statistics ---\n";
$specs = [
    'All pending' => new StatusSpec('pending'),
    'All VIP' => new CustomerTypeSpec('vip'),
    'Total > 200' => new TotalOverSpec(200),
    'Express' => new ExpressSpec(),
    'US orders' => new CountrySpec('US'),
    'Items 3-10' => new ItemCountSpec(3, 10),
];

foreach ($specs as $name => $spec) {
    $count = 0;
    $total = 0.0;
    foreach ($orders as $o) {
        if ($spec->isSatisfiedBy($o)) {
            $count++;
            $total += $o->total;
        }
    }
    echo sprintf("  %-20s: %d orders, $%.2f total\n", $name, $count, $total);
}

// 规约组合复杂度测试
echo "\n--- Complex Nested Specification ---\n";
$complex = (
    (new CustomerTypeSpec('vip'))->and(new TotalOverSpec(500))
)->or(
    (new CountrySpec('US'))->and(new StatusSpec('pending'))->and(new ExpressSpec())
);

echo "Complex rule: (VIP AND total>500) OR (US AND pending AND express):\n";
foreach ($orders as $o) {
    if ($complex->isSatisfiedBy($o)) {
        echo "  Order #{$o->id}: {$o->customerType} \${$o->total} {$o->country} {$o->status} express=" . ($o->isExpress ? 'Y' : 'N') . "\n";
    }
}
