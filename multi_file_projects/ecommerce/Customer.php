<?php
// 电商系统 - 客户 + 优惠券
class Customer {
    public ?int $id = null;
    public string $name;
    public string $email;
    public string $phone;
    public string $address;
    public string $password;
    public string $createdAt;

    public function __construct(array $data = []) {
        foreach ($data as $k => $v) {
            $camel = str_replace('_', '', lcfirst(ucwords($k, '_')));
            if (property_exists($this, $camel)) $this->$camel = $v;
            elseif (property_exists($this, $k)) $this->$k = $v;
        }
        if (!isset($this->createdAt)) $this->createdAt = date('Y-m-d H:i:s');
    }

    public static function create(string $name, string $email, string $phone, string $address, string $password): self {
        $c = new self([
            'name' => $name, 'email' => $email, 'phone' => $phone,
            'address' => $address, 'password' => password_hash($password, PASSWORD_DEFAULT),
        ]);
        $c->id = ShopDB::getInstance()->insert('customers', [
            'name' => $c->name, 'email' => $c->email, 'phone' => $c->phone,
            'address' => $c->address, 'password' => $c->password, 'created_at' => $c->createdAt,
        ]);
        return $c;
    }

    public static function find(int $id): ?self {
        $row = ShopDB::getInstance()->selectOne('customers', ['id' => $id]);
        return $row ? new self($row) : null;
    }

    public static function findByEmail(string $email): ?self {
        $row = ShopDB::getInstance()->selectOne('customers', ['email' => $email]);
        return $row ? new self($row) : null;
    }

    public function orders(): array {
        return Order::byCustomer($this->id);
    }

    public function totalSpent(): float {
        $orders = $this->orders();
        $total = 0.0;
        foreach ($orders as $order) {
            if (in_array($order->status, ['paid', 'shipped', 'delivered'])) {
                $total += $order->total;
            }
        }
        return $total;
    }

    public function verifyPassword(string $password): bool {
        return password_verify($password, $this->password);
    }

    public function toArray(): array {
        return [
            'id' => $this->id, 'name' => $this->name, 'email' => $this->email,
            'phone' => $this->phone, 'address' => $this->address, 'created_at' => $this->createdAt,
        ];
    }
}

class Coupon {
    public ?int $id = null;
    public string $code;
    public string $type; // percentage, fixed
    public float $value;
    public float $minSpend;
    public int $usageLimit;
    public int $usedCount;
    public string $expiresAt;
    public bool $active;

    public function __construct(array $data = []) {
        foreach ($data as $k => $v) {
            $camel = str_replace('_', '', lcfirst(ucwords($k, '_')));
            if (property_exists($this, $camel)) $this->$camel = $v;
            elseif (property_exists($this, $k)) $this->$k = $v;
        }
        if (!isset($this->usedCount)) $this->usedCount = 0;
        if (!isset($this->active)) $this->active = true;
    }

    public static function create(string $code, string $type, float $value, float $minSpend = 0, int $usageLimit = 1000, string $expiresAt = '2027-12-31'): self {
        $c = new self([
            'code' => $code, 'type' => $type, 'value' => $value,
            'min_spend' => $minSpend, 'usage_limit' => $usageLimit,
            'used_count' => 0, 'expires_at' => $expiresAt, 'active' => true,
        ]);
        $c->id = ShopDB::getInstance()->insert('coupons', [
            'code' => $code, 'type' => $type, 'value' => $value,
            'min_spend' => $minSpend, 'usage_limit' => $usageLimit,
            'used_count' => 0, 'expires_at' => $expiresAt, 'active' => 1,
        ]);
        return $c;
    }

    public static function findByCode(string $code): ?self {
        $row = ShopDB::getInstance()->selectOne('coupons', ['code' => $code, 'active' => 1]);
        return $row ? new self($row) : null;
    }

    public function isValid(float $cartSubtotal): bool {
        if (!$this->active) return false;
        if ($this->usedCount >= $this->usageLimit) return false;
        if ($cartSubtotal < $this->minSpend) return false;
        if (strtotime($this->expiresAt) < time()) return false;
        return true;
    }

    public function calculateDiscount(float $subtotal): float {
        if (!$this->isValid($subtotal)) return 0.0;
        if ($this->type === 'percentage') {
            return $subtotal * ($this->value / 100);
        }
        return min($this->value, $subtotal);
    }

    public function redeem(): void {
        $this->usedCount++;
        ShopDB::getInstance()->update('coupons', ['id' => $this->id], ['used_count' => $this->usedCount]);
        if ($this->usedCount >= $this->usageLimit) {
            $this->active = false;
            ShopDB::getInstance()->update('coupons', ['id' => $this->id], ['active' => 0]);
        }
    }

    public function toArray(): array {
        return [
            'id' => $this->id, 'code' => $this->code, 'type' => $this->type,
            'value' => $this->value, 'min_spend' => $this->minSpend,
            'usage_limit' => $this->usageLimit, 'used_count' => $this->usedCount,
            'expires_at' => $this->expiresAt, 'active' => $this->active,
        ];
    }
}
