<?php
// Test 161: Object property visibility
class PropVisibility {
    public string $public = 'public';
    protected string $protected = 'protected';
    private string $private = 'private';

    public function getProtected(): string {
        return $this->protected;
    }

    public function getPrivate(): string {
        return $this->private;
    }
}

$obj = new PropVisibility();
echo "public: " . $obj->public . "\n";
echo "getProtected: " . $obj->getProtected() . "\n";
echo "getPrivate: " . $obj->getPrivate() . "\n";