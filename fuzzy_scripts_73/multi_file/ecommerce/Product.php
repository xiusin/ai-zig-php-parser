<?php
// 电商系统 - 产品模型
class Product {
    public function __construct(
        public readonly int $id,
        public readonly string $name,
        public readonly float $price,
        public readonly string $category,
        public int $stock = 0
    ) {}

    public function applyDiscount(float $percentage): float {
        return $this->price * (1 - $percentage / 100);
    }

    public function inStock(): bool {
        return $this->stock > 0;
    }

    public function __toString(): string {
        return sprintf("[%d] %s (%s) - $%.2f (stock: %d)",
            $this->id, $this->name, $this->category, $this->price, $this->stock);
    }
}

class ProductCatalog {
    private array $products = [];

    public function add(Product $product): void {
        $this->products[$product->id] = $product;
    }

    public function get(int $id): ?Product {
        return $this->products[$id] ?? null;
    }

    public function getByCategory(string $category): array {
        return array_values(array_filter($this->products, fn($p) => $p->category === $category));
    }

    public function search(string $keyword): array {
        return array_values(array_filter($this->products, fn($p) => stripos($p->name, $keyword) !== false));
    }

    public function count(): int {
        return count($this->products);
    }

    public function all(): array {
        return array_values($this->products);
    }
}
