<?php
// 电商系统 - 商品模型 + 分类 + 库存
class Category {
    public ?int $id = null;
    public string $name;
    public ?int $parentId = null;

    public function __construct(array $data = []) {
        foreach ($data as $k => $v) {
            $camel = str_replace('_', '', lcfirst(ucwords($k, '_')));
            if (property_exists($this, $camel)) $this->$camel = $v;
            elseif (property_exists($this, $k)) $this->$k = $v;
        }
    }

    public static function create(string $name, ?int $parentId = null): self {
        $cat = new self(['name' => $name, 'parent_id' => $parentId]);
        $cat->id = ShopDB::getInstance()->insert('categories', ['name' => $name, 'parent_id' => $parentId]);
        return $cat;
    }

    public function children(): array {
        $rows = ShopDB::getInstance()->select('categories', ['parent_id' => $this->id]);
        return array_map(fn($r) => new self($r), $rows);
    }

    public function products(): array {
        $rows = ShopDB::getInstance()->select('products', ['category_id' => $this->id]);
        return array_map(fn($r) => new Product($r), $rows);
    }
}

class Product {
    public ?int $id = null;
    public string $name;
    public string $description;
    public float $price;
    public int $categoryId;
    public string $sku;
    public string $status; // active, inactive, out_of_stock
    public int $stockQty;
    public array $attributes = [];

    public function __construct(array $data = []) {
        foreach ($data as $k => $v) {
            $camel = str_replace('_', '', lcfirst(ucwords($k, '_')));
            if ($camel === 'attributes' && is_string($v)) {
                $this->attributes = json_decode($v, true) ?? [];
            } elseif (property_exists($this, $camel)) {
                $this->$camel = $v;
            } elseif (property_exists($this, $k)) {
                $this->$k = $v;
            }
        }
        if (!isset($this->status)) $this->status = 'active';
        if (!isset($this->stockQty)) $this->stockQty = 0;
    }

    public static function create(string $name, string $desc, float $price, int $categoryId, string $sku, int $stock = 0, array $attrs = []): self {
        $p = new self([
            'name' => $name, 'description' => $desc, 'price' => $price,
            'category_id' => $categoryId, 'sku' => $sku, 'stock_qty' => $stock,
            'status' => 'active', 'attributes' => $attrs,
        ]);
        $p->id = ShopDB::getInstance()->insert('products', [
            'name' => $name, 'description' => $desc, 'price' => $price,
            'category_id' => $categoryId, 'sku' => $sku, 'stock_qty' => $stock,
            'status' => 'active', 'attributes' => json_encode($attrs),
        ]);
        return $p;
    }

    public static function find(int $id): ?self {
        $row = ShopDB::getInstance()->selectOne('products', ['id' => $id]);
        if (!$row) return null;
        $p = new self($row);
        if (isset($row['attributes'])) $p->attributes = json_decode($row['attributes'], true) ?? [];
        return $p;
    }

    public static function all(int $limit = 50, int $offset = 0): array {
        $rows = ShopDB::getInstance()->select('products', [], $limit, $offset, 'id', 'DESC');
        return array_map(function($r) {
            $p = new self($r);
            if (isset($r['attributes'])) $p->attributes = json_decode($r['attributes'], true) ?? [];
            return $p;
        }, $rows);
    }

    public static function byCategory(int $categoryId): array {
        $rows = ShopDB::getInstance()->select('products', ['category_id' => $categoryId, 'status' => 'active']);
        return array_map(fn($r) => new self($r), $rows);
    }

    public static function search(string $keyword): array {
        $all = ShopDB::getInstance()->select('products', ['status' => 'active']);
        $results = [];
        foreach ($all as $row) {
            if (stripos($row['name'], $keyword) !== false || stripos($row['description'], $keyword) !== false) {
                $results[] = new self($row);
            }
        }
        return $results;
    }

    public function category(): ?Category {
        $row = ShopDB::getInstance()->selectOne('categories', ['id' => $this->categoryId]);
        return $row ? new Category($row) : null;
    }

    public function reduceStock(int $qty): bool {
        if ($this->stockQty < $qty) return false;
        $this->stockQty -= $qty;
        if ($this->stockQty === 0) $this->status = 'out_of_stock';
        ShopDB::getInstance()->update('products', ['id' => $this->id], ['stock_qty' => $this->stockQty, 'status' => $this->status]);
        return true;
    }

    public function addStock(int $qty): void {
        $this->stockQty += $qty;
        if ($this->status === 'out_of_stock') $this->status = 'active';
        ShopDB::getInstance()->update('products', ['id' => $this->id], ['stock_qty' => $this->stockQty, 'status' => $this->status]);
    }

    public function setAttribute(string $key, mixed $value): void {
        $this->attributes[$key] = $value;
        ShopDB::getInstance()->update('products', ['id' => $this->id], ['attributes' => json_encode($this->attributes)]);
    }

    public function getAttribute(string $key, mixed $default = null): mixed {
        return $this->attributes[$key] ?? $default;
    }

    public function toArray(): array {
        return [
            'id' => $this->id, 'name' => $this->name, 'description' => $this->description,
            'price' => $this->price, 'category_id' => $this->categoryId, 'sku' => $this->sku,
            'status' => $this->status, 'stock_qty' => $this->stockQty,
            'attributes' => $this->attributes,
        ];
    }
}
