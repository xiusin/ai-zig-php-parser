<?php
// Test 094: Class constant visibility
class ConstVisibility {
    public const PUBLIC = 'public_const';
    protected const PROTECTED = 'protected_const';
    private const PRIVATE = 'private_const';

    public function getProtected(): string {
        return self::PROTECTED;
    }

    public function getPrivate(): string {
        return self::PRIVATE;
    }
}

class ChildConst extends ConstVisibility {
    public function accessParentProtected(): string {
        return parent::PROTECTED;
    }
}

echo "=== Constant visibility ===\n";
$obj = new ConstVisibility();
echo "PUBLIC: " . ConstVisibility::PUBLIC . "\n";
echo "getProtected: " . $obj->getProtected() . "\n";
echo "getPrivate: " . $obj->getPrivate() . "\n";

echo "\n=== Child access ===\n";
$child = new ChildConst();
echo "accessParentProtected: " . $child->accessParentProtected() . "\n";

echo "\n=== Interface constant visibility ===\n";
interface IfaceConst {
    public const PUBLIC_CONST = 'public';
    const IMPLICIT_PUBLIC = 'implicit';
}

echo "PUBLIC_CONST: " . IfaceConst::PUBLIC_CONST . "\n";
echo "IMPLICIT_PUBLIC: " . IfaceConst::IMPLICIT_PUBLIC . "\n";

echo "\n=== Trait constant ===\n";
trait TraitConst {
    public const TRAIT_CONST = 'from_trait';
}

class UseTraitConst {
    use TraitConst;
    public const CLASS_CONST = 'from_class';
}

echo "TRAIT_CONST: " . UseTraitConst::TRAIT_CONST . "\n";
echo "CLASS_CONST: " . UseTraitConst::CLASS_CONST . "\n";