<?php
// 电商系统 - 购物车
class CartItem {
    public function __construct(
        public readonly Product $product,
        public int $quantity
    ) {}

    public function subtotal(): float {
        return $this->product->price * $this->quantity;
    }

    public function __toString(): string {
        return sprintf("%s x%d = $%.2f", $this->product->name, $this->quantity, $this->subtotal());
    }
}

class Cart {
    private array $items = [];
    private ?User $user = null;

    public function __construct(?User $user = null) {
        $this->user = $user;
    }

    public function add(Product $product, int $quantity = 1): void {
        $productId = $product->id;
        if (isset($this->items[$productId])) {
            $this->items[$productId]->quantity += $quantity;
        } else {
            $this->items[$productId] = new CartItem($product, $quantity);
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

    public function getItems(): array {
        return array_values($this->items);
    }

    public function count(): int {
        return count($this->items);
    }

    public function totalQuantity(): int {
        return array_sum(array_map(fn($item) => $item->quantity, $this->items));
    }

    public function subtotal(): float {
        return array_sum(array_map(fn($item) => $item->subtotal(), $this->items));
    }

    public function tax(float $rate = 0.08): float {
        return $this->subtotal() * $rate;
    }

    public function total(float $taxRate = 0.08): float {
        return $this->subtotal() + $this->tax($taxRate);
    }

    public function clear(): void {
        $this->items = [];
    }

    public function getUser(): ?User {
        return $this->user;
    }

    public function display(): string {
        $lines = ["=== Shopping Cart ==="];
        if ($this->user) {
            $lines[] = "User: " . $this->user->name;
        }
        if (empty($this->items)) {
            $lines[] = "(empty)";
        } else {
            foreach ($this->items as $item) {
                $lines[] = "  " . $item;
            }
            $lines[] = sprintf("---");
            $lines[] = sprintf("Subtotal: $%.2f", $this->subtotal());
            $lines[] = sprintf("Tax (8%%): $%.2f", $this->tax());
            $lines[] = sprintf("Total: $%.2f", $this->total());
        }
        return implode("\n", $lines);
    }
}
