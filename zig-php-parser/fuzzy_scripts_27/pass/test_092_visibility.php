<?php
// Test 092: Method visibility and overriding
class VisibilityBase {
    public function publicMethod(): string { return "public"; }
    protected function protectedMethod(): string { return "protected"; }
    private function privateMethod(): string { return "private"; }

    public function callProtected(): string { return $this->protectedMethod(); }
    public function callPrivate(): string { return $this->privateMethod(); }
}

class VisibilityChild extends VisibilityBase {
    public function childPublic(): string { return "child_public"; }
    protected function protectedMethod(): string { return "child_protected"; }
    private function childPrivate(): string { return "child_private"; }

    public function getParentProtected(): string {
        return parent::callProtected();
    }
}

echo "=== Visibility ===\n";
$child = new VisibilityChild();
echo "publicMethod: " . $child->publicMethod() . "\n";
echo "childPublic: " . $child->childPublic() . "\n";
echo "callProtected (child override): " . $child->callProtected() . "\n";
echo "getParentProtected: " . $child->getParentProtected() . "\n";

echo "\n=== Cannot access private parent method ===\n";
echo "callPrivate: " . $child->callPrivate() . "\n";

echo "\n=== Static method visibility ===\n";
class StaticVis {
    public static function publicStatic(): string { return "public_static"; }
    protected static function protectedStatic(): string { return "protected_static"; }
}

class StaticVisChild extends StaticVis {
    public static function childStatic(): string { return "child_static"; }
}

echo "publicStatic: " . StaticVis::publicStatic() . "\n";
echo "childStatic: " . StaticVisChild::childStatic() . "\n";