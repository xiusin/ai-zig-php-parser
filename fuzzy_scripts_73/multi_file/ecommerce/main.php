<?php
// 电商系统 - 主入口
require_once __DIR__ . '/Product.php';
require_once __DIR__ . '/User.php';
require_once __DIR__ . '/Cart.php';
require_once __DIR__ . '/Order.php';

// 创建产品目录
$catalog = new ProductCatalog();
$catalog->add(new Product(1, 'Laptop', 999.99, 'Electronics', 50));
$catalog->add(new Product(2, 'Mouse', 29.99, 'Electronics', 200));
$catalog->add(new Product(3, 'Keyboard', 79.99, 'Electronics', 150));
$catalog->add(new Product(4, 'Monitor', 349.99, 'Electronics', 30));
$catalog->add(new Product(5, 'Desk Chair', 199.99, 'Furniture', 25));
$catalog->add(new Product(6, 'Desk Lamp', 39.99, 'Furniture', 100));
$catalog->add(new Product(7, 'Notebook', 4.99, 'Stationery', 500));
$catalog->add(new Product(8, 'Pen Set', 12.99, 'Stationery', 300));

echo "=== Product Catalog ===\n";
echo "Total products: " . $catalog->count() . "\n";

echo "\nElectronics:\n";
foreach ($catalog->getByCategory('Electronics') as $p) {
    echo "  $p\n";
}

echo "\nFurniture:\n";
foreach ($catalog->getByCategory('Furniture') as $p) {
    echo "  $p\n";
}

// 搜索产品
echo "\nSearch 'Desk':\n";
foreach ($catalog->search('Desk') as $p) {
    echo "  $p\n";
}

// 创建用户
$userRepo = new UserRepository();
$alice = $userRepo->create('Alice', 'alice@shop.com', 'customer');
$alice->addAddress('home', '123 Main St, NYC');
$alice->addAddress('work', '456 Office Blvd, NYC');

$bob = $userRepo->create('Bob', 'bob@shop.com', 'admin');

echo "\n=== Users ===\n";
echo $alice . "\n";
echo "  Addresses: " . json_encode($alice->getAddresses()) . "\n";
echo $bob . "\n";
echo "  Is admin: " . var_export($bob->isAdmin(), true) . "\n";

// 创建购物车
$cart = new Cart($alice);
$cart->add($catalog->get(1), 1);  // Laptop x1
$cart->add($catalog->get(2), 2);  // Mouse x2
$cart->add($catalog->get(7), 5);  // Notebook x5
$cart->add($catalog->get(3), 1);  // Keyboard x1

echo "\n" . $cart->display() . "\n";

// 更新数量
$cart->updateQuantity(7, 3); // Notebook 改为 3
echo "\nAfter update notebook qty to 3:\n";
echo $cart->display() . "\n";

// 创建订单
$order = new Order($cart, $alice);
echo "\n" . $order->display() . "\n";

// 订单状态流转
echo "\n=== Order Status Flow ===\n";
echo "Initial: " . $order->status->label() . "\n";
$order->confirm();
echo "After confirm: " . $order->status->label() . "\n";
$order->ship();
echo "After ship: " . $order->status->label() . "\n";
$order->deliver();
echo "After deliver: " . $order->status->label() . "\n";

// 创建第二个订单
$cart2 = new Cart($bob);
$cart2->add($catalog->get(5), 1);
$cart2->add($catalog->get(6), 2);
$order2 = new Order($cart2, $bob);
echo "\n" . $order2->display() . "\n";
$order2->cancel();
echo "After cancel: " . $order2->status->label() . "\n";

// 统计
echo "\n=== Summary ===\n";
echo "Total users: " . $userRepo->count() . "\n";
echo "Total products: " . $catalog->count() . "\n";
echo "Order #{$order->id} total: $" . number_format($order->getTotal(), 2) . "\n";
echo "Order #{$order2->id} total: $" . number_format($order2->getTotal(), 2) . "\n";
