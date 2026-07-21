<?php
// 电商系统 - 订单 + 支付
class Order {
    public ?int $id = null;
    public int $customerId;
    public array $items = [];
    public float $subtotal;
    public float $discount;
    public float $tax;
    public float $shipping;
    public float $total;
    public string $status; // pending, paid, shipped, delivered, cancelled, refunded
    public ?string $couponCode = null;
    public string $shippingAddress;
    public string $paymentMethod;
    public ?string $transactionId = null;
    public string $createdAt;

    public function __construct(array $data = []) {
        foreach ($data as $k => $v) {
            $camel = str_replace('_', '', lcfirst(ucwords($k, '_')));
            if (property_exists($this, $camel)) $this->$camel = $v;
            elseif (property_exists($this, $k)) $this->$k = $v;
        }
        if (!isset($this->status)) $this->status = 'pending';
        if (!isset($this->createdAt)) $this->createdAt = date('Y-m-d H:i:s');
        if (!isset($this->subtotal)) $this->subtotal = 0;
        if (!isset($this->discount)) $this->discount = 0;
        if (!isset($this->tax)) $this->tax = 0;
        if (!isset($this->shipping)) $this->shipping = 0;
        if (!isset($this->total)) $this->total = 0;
    }

    public static function createFromCart(int $customerId, Cart $cart, string $shippingAddress, string $paymentMethod): self {
        $order = new self([
            'customer_id' => $customerId,
            'shipping_address' => $shippingAddress,
            'payment_method' => $paymentMethod,
            'coupon_code' => $cart->couponCode,
        ]);

        $summary = $cart->summary();
        $order->subtotal = $summary['subtotal'];
        $order->discount = $summary['discount'];
        $order->tax = $summary['tax'];
        $order->shipping = $summary['shipping'];
        $order->total = $summary['total'];

        // 保存订单
        $order->id = ShopDB::getInstance()->insert('orders', [
            'customer_id' => $customerId,
            'subtotal' => $order->subtotal,
            'discount' => $order->discount,
            'tax' => $order->tax,
            'shipping' => $order->shipping,
            'total' => $order->total,
            'status' => 'pending',
            'coupon_code' => $order->couponCode,
            'shipping_address' => $shippingAddress,
            'payment_method' => $paymentMethod,
            'created_at' => $order->createdAt,
        ]);

        // 保存订单项
        foreach ($cart->items() as $item) {
            ShopDB::getInstance()->insert('order_items', [
                'order_id' => $order->id,
                'product_id' => $item->productId,
                'name' => $item->name,
                'price' => $item->price,
                'quantity' => $item->quantity,
                'subtotal' => $item->subtotal(),
            ]);
            $order->items[] = $item;
        }

        // 扣减库存
        foreach ($cart->items() as $item) {
            $product = Product::find($item->productId);
            if ($product) $product->reduceStock($item->quantity);
        }

        return $order;
    }

    public static function find(int $id): ?self {
        $row = ShopDB::getInstance()->selectOne('orders', ['id' => $id]);
        if (!$row) return null;
        $order = new self($row);
        $items = ShopDB::getInstance()->select('order_items', ['order_id' => $id]);
        foreach ($items as $itemRow) {
            $order->items[] = new CartItem(
                $itemRow['product_id'],
                $itemRow['name'],
                $itemRow['price'],
                $itemRow['quantity'],
            );
        }
        return $order;
    }

    public static function byCustomer(int $customerId): array {
        $rows = ShopDB::getInstance()->select('orders', ['customer_id' => $customerId], null, 0, 'id', 'DESC');
        return array_map(fn($r) => new self($r), $rows);
    }

    public function pay(): bool {
        if ($this->status !== 'pending') return false;

        // 模拟支付处理
        $this->transactionId = 'txn_' . bin2hex(random_bytes(8));
        $this->status = 'paid';

        ShopDB::getInstance()->update('orders', ['id' => $this->id], [
            'status' => 'paid',
            'transaction_id' => $this->transactionId,
        ]);

        // 记录支付
        ShopDB::getInstance()->insert('payments', [
            'order_id' => $this->id,
            'amount' => $this->total,
            'method' => $this->paymentMethod,
            'transaction_id' => $this->transactionId,
            'status' => 'completed',
            'created_at' => date('Y-m-d H:i:s'),
        ]);

        return true;
    }

    public function ship(string $trackingNumber): bool {
        if ($this->status !== 'paid') return false;
        $this->status = 'shipped';
        ShopDB::getInstance()->update('orders', ['id' => $this->id], [
            'status' => 'shipped',
        ]);
        ShopDB::getInstance()->insert('shipments', [
            'order_id' => $this->id,
            'tracking_number' => $trackingNumber,
            'carrier' => 'ExpressShip',
            'status' => 'in_transit',
            'created_at' => date('Y-m-d H:i:s'),
        ]);
        return true;
    }

    public function deliver(): bool {
        if ($this->status !== 'shipped') return false;
        $this->status = 'delivered';
        ShopDB::getInstance()->update('orders', ['id' => $this->id], ['status' => 'delivered']);
        return true;
    }

    public function cancel(): bool {
        if (in_array($this->status, ['shipped', 'delivered'])) return false;
        $this->status = 'cancelled';
        ShopDB::getInstance()->update('orders', ['id' => $this->id], ['status' => 'cancelled']);

        // 恢复库存
        foreach ($this->items as $item) {
            $product = Product::find($item->productId);
            if ($product) $product->addStock($item->quantity);
        }
        return true;
    }

    public function refund(): bool {
        if ($this->status !== 'paid' && $this->status !== 'delivered') return false;
        $this->status = 'refunded';
        ShopDB::getInstance()->update('orders', ['id' => $this->id], ['status' => 'refunded']);
        ShopDB::getInstance()->insert('refunds', [
            'order_id' => $this->id,
            'amount' => $this->total,
            'reason' => 'customer_request',
            'status' => 'processed',
            'created_at' => date('Y-m-d H:i:s'),
        ]);

        // 恢复库存
        foreach ($this->items as $item) {
            $product = Product::find($item->productId);
            if ($product) $product->addStock($item->quantity);
        }
        return true;
    }

    public function toArray(): array {
        return [
            'id' => $this->id,
            'customer_id' => $this->customerId,
            'subtotal' => $this->subtotal,
            'discount' => $this->discount,
            'tax' => $this->tax,
            'shipping' => $this->shipping,
            'total' => $this->total,
            'status' => $this->status,
            'coupon_code' => $this->couponCode,
            'payment_method' => $this->paymentMethod,
            'transaction_id' => $this->transactionId,
            'item_count' => count($this->items),
            'created_at' => $this->createdAt,
        ];
    }
}
