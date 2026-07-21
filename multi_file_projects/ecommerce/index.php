<?php
// 电商系统入口 - 多文件 AOT 测试
echo "============================================\n";
echo "E-Commerce System Multi-File AOT Test\n";
echo "============================================\n\n";

require_once 'Database.php';
require_once 'Product.php';
require_once 'Cart.php';
require_once 'Order.php';
require_once 'Customer.php';

$db = ShopDB::getInstance();

// === 创建分类 ===
echo "--- Create Categories ---\n";
$electronics = Category::create('Electronics');
$phones = Category::create('Phones', $electronics->id);
$laptops = Category::create('Laptops', $electronics->id);
$books = Category::create('Books');
$clothing = Category::create('Clothing');

echo "  Categories: {$electronics->name}(id={$electronics->id})";
foreach ($electronics->children() as $child) echo " > {$child->name}({$child->id})";
echo "\n";

// === 创建商品 ===
echo "\n--- Create Products ---\n";
$iphone = Product::create('iPhone 15 Pro', 'Latest iPhone with A17 Pro chip', 999.99, $phones->id, 'IPHONE15PRO', 50, ['color' => 'blue', 'storage' => '256GB']);
$macbook = Product::create('MacBook Pro 14', 'M3 Pro chip, 18GB RAM', 1999.99, $laptops->id, 'MBP14-M3', 30, ['color' => 'space gray', 'ram' => '18GB']);
$airpods = Product::create('AirPods Pro 2', 'Active noise cancellation', 249.99, $electronics->id, 'APP2', 100, ['color' => 'white']);
$phpBook = Product::create('PHP AOT Guide', 'Complete guide to PHP AOT compilation', 39.99, $books->id, 'BOOK-PHP-AOT', 200);
$tshirt = Product::create('Developer T-Shirt', '100% cotton, "I compile therefore I am"', 25.99, $clothing->id, 'TSHIRT-DEV', 500, ['size' => 'L', 'color' => 'black']);

echo "  Products created: {$iphone->name}(\${$iphone->price}), {$macbook->name}(\${$macbook->price}), {$airpods->name}(\${$airpods->price}), {$phpBook->name}(\${$phpBook->price}), {$tshirt->name}(\${$tshirt->price})\n";

// === 创建优惠券 ===
echo "\n--- Create Coupons ---\n";
$coupon10 = Coupon::create('SAVE10', 'percentage', 10, 50);
$coupon20 = Coupon::create('SAVE20', 'percentage', 20, 200);
$couponFlat = Coupon::create('FLAT5', 'fixed', 5, 0);
echo "  Coupons: {$coupon10->code}(10% off, min \$50), {$coupon20->code}(20% off, min \$200), {$couponFlat->code}(\$5 off)\n";

// === 注册客户 ===
echo "\n--- Register Customers ---\n";
$alice = Customer::create('Alice', 'alice@shop.com', '555-0101', '123 Main St', 'alice_pass');
$bob = Customer::create('Bob', 'bob@shop.com', '555-0102', '456 Oak Ave', 'bob_pass');
echo "  Customers: {$alice->name}(id={$alice->id}), {$bob->name}(id={$bob->id})\n";
echo "  Login test: " . ($alice->verifyPassword('alice_pass') ? 'SUCCESS' : 'FAIL') . "\n";

// === 购物车操作 ===
echo "\n--- Cart Operations (Alice) ---\n";
$cart = new Cart();
$cart->add($iphone, 1);
$cart->add($airpods, 2);
$cart->add($tshirt, 3);

echo "  Items: " . $cart->itemCount() . "\n";
$summary = $cart->summary();
echo "  Subtotal: \${$summary['subtotal']}\n";
echo "  Shipping: \${$summary['shipping']}\n";
echo "  Tax: \${$summary['tax']}\n";
echo "  Total: \${$summary['total']}\n";

// 应用优惠券
echo "\n--- Apply Coupon ---\n";
$applied = $cart->applyCoupon('SAVE10');
echo "  Apply SAVE10: " . ($applied ? 'SUCCESS' : 'FAIL') . "\n";
$summary = $cart->summary();
echo "  Discount: \${$summary['discount']}\n";
echo "  New total: \${$summary['total']}\n";

// 添加更多商品达到免邮门槛
echo "\n--- Add MacBook (free shipping threshold) ---\n";
$cart->add($macbook, 1);
$summary = $cart->summary();
echo "  Subtotal: \${$summary['subtotal']}\n";
echo "  Shipping: \${$summary['shipping']} " . ($summary['shipping'] == 0 ? '(FREE!)' : '') . "\n";
echo "  Total: \${$summary['total']}\n";

// === 下单 ===
echo "\n--- Place Order ---\n";
$order = Order::createFromCart($alice->id, $cart, $alice->address, 'credit_card');
echo "  Order ID: {$order->id}\n";
echo "  Status: {$order->status}\n";
echo "  Total: \${$order->total}\n";
echo "  Items: " . count($order->items) . "\n";

// 检查库存扣减
$iphoneAfter = Product::find($iphone->id);
echo "  iPhone stock after order: {$iphoneAfter->stockQty} (was {$iphone->stockQty})\n";
$airpodsAfter = Product::find($airpods->id);
echo "  AirPods stock after order: {$airpodsAfter->stockQty} (was {$airpods->stockQty})\n";

// === 支付 ===
echo "\n--- Payment ---\n";
$paid = $order->pay();
echo "  Payment: " . ($paid ? 'SUCCESS' : 'FAIL') . "\n";
echo "  Transaction ID: {$order->transactionId}\n";
echo "  Status: {$order->status}\n";

// === 发货 ===
echo "\n--- Shipping ---\n";
$shipped = $order->ship('TRACK-' . strtoupper(bin2hex(random_bytes(4))));
echo "  Ship: " . ($shipped ? 'SUCCESS' : 'FAIL') . "\n";
echo "  Status: {$order->status}\n";

// === 送达 ===
echo "\n--- Delivery ---\n";
$delivered = $order->deliver();
echo "  Deliver: " . ($delivered ? 'SUCCESS' : 'FAIL') . "\n";
echo "  Status: {$order->status}\n";

// === Bob 的订单（取消） ===
echo "\n--- Bob's Order (Cancel) ---\n";
$cart2 = new Cart();
$cart2->add($phpBook, 5);
$cart2->add($tshirt, 2);
echo "  Bob's cart total: \${$cart2->summary()['total']}\n";

$order2 = Order::createFromCart($bob->id, $cart2, $bob->address, 'paypal');
echo "  Order ID: {$order2->id}, Status: {$order2->status}\n";

$cancelled = $order2->cancel();
echo "  Cancel: " . ($cancelled ? 'SUCCESS' : 'FAIL') . "\n";
echo "  Status: {$order2->status}\n";

// 检查库存恢复
$phpBookAfter = Product::find($phpBook->id);
echo "  PHP Book stock after cancel: {$phpBookAfter->stockQty} (should be " . ($phpBook->stockQty) . ")\n";

// === 退款 ===
echo "\n--- Refund (Alice's order) ---\n";
$refunded = $order->refund();
echo "  Refund: " . ($refunded ? 'SUCCESS' : 'FAIL') . "\n";
echo "  Status: {$order->status}\n";

// 检查库存恢复
$iphoneRefunded = Product::find($iphone->id);
echo "  iPhone stock after refund: {$iphoneRefunded->stockQty}\n";

// === 搜索商品 ===
echo "\n--- Product Search ---\n";
$results = Product::search('iPhone');
echo "  Search 'iPhone': " . count($results) . " results\n";
foreach ($results as $p) echo "    - {$p->name} (\${$p->price})\n";

$results = Product::search('Pro');
echo "  Search 'Pro': " . count($results) . " results\n";
foreach ($results as $p) echo "    - {$p->name} (\${$p->price})\n";

// === 分类商品 ===
echo "\n--- Products by Category ---\n";
$phoneProducts = Product::byCategory($phones->id);
echo "  Phones: " . count($phoneProducts) . " products\n";
foreach ($phoneProducts as $p) echo "    - {$p->name}\n";

// === 客户订单历史 ===
echo "\n--- Customer Order History ---\n";
$aliceOrders = Order::byCustomer($alice->id);
echo "  Alice's orders: " . count($aliceOrders) . "\n";
foreach ($aliceOrders as $o) {
    echo "    [{$o->id}] \${$o->total} - {$o->status}\n";
}

echo "  Alice total spent: \$" . number_format($alice->totalSpent(), 2) . "\n";

// === 优惠券验证 ===
echo "\n--- Coupon Validation ---\n";
$testCoupon = Coupon::findByCode('SAVE20');
echo "  SAVE20 valid for \$150: " . ($testCoupon && $testCoupon->isValid(150) ? 'YES' : 'NO') . "\n";
echo "  SAVE20 valid for \$250: " . ($testCoupon && $testCoupon->isValid(250) ? 'YES' : 'NO') . "\n";
echo "  SAVE20 discount for \$300: \$" . $testCoupon->calculateDiscount(300) . "\n";

// === 商品属性 ===
echo "\n--- Product Attributes ---\n";
echo "  iPhone color: {$iphone->getAttribute('color')}\n";
echo "  iPhone storage: {$iphone->getAttribute('storage')}\n";
$iphone->setAttribute('color', 'red');
echo "  iPhone color after update: {$iphone->getAttribute('color')}\n";

// === 数据库统计 ===
echo "\n=== Database Statistics ===\n";
echo "  Customers: " . ShopDB::getInstance()->count('customers') . "\n";
echo "  Products: " . ShopDB::getInstance()->count('products') . "\n";
echo "  Categories: " . ShopDB::getInstance()->count('categories') . "\n";
echo "  Orders: " . ShopDB::getInstance()->count('orders') . "\n";
echo "  Order Items: " . ShopDB::getInstance()->count('order_items') . "\n";
echo "  Coupons: " . ShopDB::getInstance()->count('coupons') . "\n";
echo "  Payments: " . ShopDB::getInstance()->count('payments') . "\n";
echo "  Shipments: " . ShopDB::getInstance()->count('shipments') . "\n";
echo "  Refunds: " . ShopDB::getInstance()->count('refunds') . "\n";

echo "\n=== Event Log (last 15) ===\n";
foreach (array_slice(ShopDB::getInstance()->eventLog, -15) as $event) {
    echo "  $event\n";
}

echo "\n============================================\n";
echo "E-Commerce System Test Complete\n";
echo "============================================\n";
