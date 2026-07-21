<?php
// 电商系统 - 购物车
class CartItem {
    public int $productId;
    public string $name;
    public float $price;
    public int $quantity;
    public array $attributes = [];

    public function __construct(int $productId, string $name, float $price, int $quantity, array $attributes = []) {
        $this->productId = $productId;
        $this->name = $name;
        $this->price = $price;
        $this->quantity = $quantity;
        $this->attributes = $attributes;
    }

    public function subtotal(): float {
        return $this->price * $this->quantity;
    }
}

class Cart {
    private array $items = [];
    public array $discountCodes = [];
    public ?string $couponCode = null;

    public function add(Product $product, int $quantity = 1): void {
        $id = $product->id;
        if (isset($this->items[$id])) {
            $this->items[$id]->quantity += $quantity;
        } else {
            $this->items[$id] = new CartItem($product->id, $product->name, $product->price, $quantity, $product->attributes);
        }
    }

    public function remove(int $productId): void {
        unset($this->items[$productId]);
    }

    public function updateQuantity(int $productId, int $quantity): void {
        if ($quantity <= 0) {
            $this->remove($productId);
        } elseif (isset($this->items[$productId])) {
            $this->items[$productId]->quantity = $quantity;
        }
    }

    public function items(): array {
        return array_values($this->items);
    }

    public function itemCount(): int {
        return array_sum(array_map(fn($i) => $i->quantity, $this->items));
    }

    public function subtotal(): float {
        return array_sum(array_map(fn($i) => $i->subtotal(), $this->items));
    }

    public function discount(): float {
        if ($this->couponCode === null) return 0.0;
        $coupons = [
            'SAVE10' => 0.10,
            'SAVE20' => 0.20,
            'SAVE50' => 0.50,
            'FLAT5' => 5.00,
        ];
        $coupon = $coupons[$this->couponCode] ?? 0;
        if (is_float($coupon) && $coupon < 1.0) {
            return $this->subtotal() * $coupon;
        }
        return min($coupon, $this->subtotal());
    }

    public function tax(float $rate = 0.08): float {
        return ($this->subtotal() - $this->discount()) * $rate;
    }

    public function shipping(float $flatRate = 10.00): float {
        if ($this->subtotal() >= 100.00) return 0.0;
        return $flatRate;
    }

    public function total(float $taxRate = 0.08, float $shippingRate = 10.00): float {
        return $this->subtotal() - $this->discount() + $this->tax($taxRate) + $this->shipping($shippingRate);
    }

    public function applyCoupon(string $code): bool {
        $validCodes = ['SAVE10', 'SAVE20', 'SAVE50', 'FLAT5'];
        if (in_array($code, $validCodes)) {
            $this->couponCode = $code;
            return true;
        }
        return false;
    }

    public function clear(): void {
        $this->items = [];
        $this->couponCode = null;
    }

    public function summary(float $taxRate = 0.08, float $shippingRate = 10.00): array {
        return [
            'items' => count($this->items),
            'total_quantity' => $this->itemCount(),
            'subtotal' => round($this->subtotal(), 2),
            'discount' => round($this->discount(), 2),
            'tax' => round($this->tax($taxRate), 2),
            'shipping' => round($this->shipping($shippingRate), 2),
            'total' => round($this->total($taxRate, $shippingRate), 2),
            'coupon' => $this->couponCode,
        ];
    }
}
