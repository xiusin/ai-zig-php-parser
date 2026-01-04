<?php
// Multiple interfaces implementation
interface Identifiable {
    public function getId();
    public function setId($id);
}

interface Nameable {
    public function getName();
    public function setName($name);
}

interface Describable {
    public function getDescription();
    public function setDescription($description);
}

interface Timestampable {
    public function getCreatedAt();
    public function getUpdatedAt();
    public function updateTimestamp();
}

interface Validatable {
    public function validate(): bool;
    public function getErrors(): array;
}

interface Serializable {
    public function serialize(): string;
    public function unserialize($data): bool;
}

interface Comparable {
    public function compareTo($other): int;
}

class Product implements Identifiable, Nameable, Describable, Timestampable, Validatable, Serializable, Comparable {
    private $id;
    private $name;
    private $description;
    private $price;
    private $quantity;
    private $created_at;
    private $updated_at;
    private $errors = [];
    
    public function __construct($id, $name, $description, $price, $quantity) {
        $this->id = $id;
        $this->name = $name;
        $this->description = $description;
        $this->price = $price;
        $this->quantity = $quantity;
        $this->created_at = time();
        $this->updated_at = time();
    }
    
    // Identifiable
    public function getId() {
        return $this->id;
    }
    
    public function setId($id) {
        $this->id = $id;
        $this->updateTimestamp();
    }
    
    // Nameable
    public function getName() {
        return $this->name;
    }
    
    public function setName($name) {
        $this->name = $name;
        $this->updateTimestamp();
    }
    
    // Describable
    public function getDescription() {
        return $this->description;
    }
    
    public function setDescription($description) {
        $this->description = $description;
        $this->updateTimestamp();
    }
    
    // Timestampable
    public function getCreatedAt() {
        return $this->created_at;
    }
    
    public function getUpdatedAt() {
        return $this->updated_at;
    }
    
    public function updateTimestamp() {
        $this->updated_at = time();
    }
    
    // Validatable
    public function validate(): bool {
        $this->errors = [];
        
        if (empty($this->name)) {
            $this->errors[] = "Name cannot be empty";
        }
        
        if ($this->price < 0) {
            $this->errors[] = "Price cannot be negative";
        }
        
        if ($this->quantity < 0) {
            $this->errors[] = "Quantity cannot be negative";
        }
        
        return empty($this->errors);
    }
    
    public function getErrors(): array {
        return $this->errors;
    }
    
    // Serializable
    public function serialize(): string {
        return json_encode([
            'id' => $this->id,
            'name' => $this->name,
            'description' => $this->description,
            'price' => $this->price,
            'quantity' => $this->quantity,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at
        ]);
    }
    
    public function unserialize($data): bool {
        $decoded = json_decode($data, true);
        if (!$decoded) {
            return false;
        }
        
        $this->id = $decoded['id'];
        $this->name = $decoded['name'];
        $this->description = $decoded['description'];
        $this->price = $decoded['price'];
        $this->quantity = $decoded['quantity'];
        $this->created_at = $decoded['created_at'];
        $this->updated_at = $decoded['updated_at'];
        
        return true;
    }
    
    // Comparable
    public function compareTo($other): int {
        if ($other instanceof Product) {
            return $this->price <=> $other->price;
        }
        return 0;
    }
    
    // Additional methods
    public function getPrice() {
        return $this->price;
    }
    
    public function setPrice($price) {
        if ($price >= 0) {
            $this->price = $price;
            $this->updateTimestamp();
        }
    }
    
    public function getQuantity() {
        return $this->quantity;
    }
    
    public function setQuantity($quantity) {
        if ($quantity >= 0) {
            $this->quantity = $quantity;
            $this->updateTimestamp();
        }
    }
}

// Test multiple interfaces
echo "=== Multiple Interfaces Testing ===\n";

$product1 = new Product(1, "Laptop", "High-performance laptop", 999.99, 10);
$product2 = new Product(2, "Mouse", "Wireless mouse", 29.99, 50);
$product3 = new Product(3, "", "", -10, 5);

echo "Product 1:\n";
echo "  ID: {$product1->getId()}\n";
echo "  Name: {$product1->getName()}\n";
echo "  Description: {$product1->getDescription()}\n";
echo "  Price: \${$product1->getPrice()}\n";
echo "  Quantity: {$product1->getQuantity()}\n";
echo "  Valid: " . ($product1->validate() ? "Yes" : "No") . "\n";
echo "  Created: " . date('Y-m-d H:i:s', $product1->getCreatedAt()) . "\n";

echo "\nProduct 2:\n";
echo "  ID: {$product2->getId()}\n";
echo "  Name: {$product2->getName()}\n";
echo "  Price: \${$product2->getPrice()}\n";

echo "\nProduct 3:\n";
echo "  Valid: " . ($product3->validate() ? "Yes" : "No") . "\n";
echo "  Errors: " . implode(', ', $product3->getErrors()) . "\n";

// Test comparison
echo "\nPrice comparison:\n";
$cmp = $product1->compareTo($product2);
if ($cmp > 0) {
    echo "{$product1->getName()} is more expensive than {$product2->getName()}\n";
} elseif ($cmp < 0) {
    echo "{$product1->getName()} is cheaper than {$product2->getName()}\n";
} else {
    echo "Both products have the same price\n";
}

// Test serialization
echo "\nSerialization:\n";
$serialized = $product1->serialize();
echo "Serialized: " . substr($serialized, 0, 50) . "...\n";

$newProduct = new Product(0, "", "", 0, 0);
$newProduct->unserialize($serialized);
echo "Unserialized ID: {$newProduct->getId()}\n";
echo "Unserialized Name: {$newProduct->getName()}\n";

echo "\nDone\n";
