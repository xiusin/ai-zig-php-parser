<?php
// Test 105: Final constants (PHP 8.3)
class FinalConstants {
    final const FINAL_STRING = 'final_string';
    final const FINAL_INT = 42;
    final const FINAL_ARRAY = ['a', 'b', 'c'];
}

class ChildFinal extends FinalConstants {
    public const CHILD_ONLY = 'child';
}

echo "=== Final constants ===\n";
echo "FINAL_STRING: " . FinalConstants::FINAL_STRING . "\n";
echo "FINAL_INT: " . FinalConstants::FINAL_INT . "\n";
echo "FINAL_ARRAY: " . json_encode(FinalConstants::FINAL_ARRAY) . "\n";

echo "\n=== Cannot override final constant ===\n";
echo "ChildFinal::CHILD_ONLY: " . ChildFinal::CHILD_ONLY . "\n";
echo "ChildFinal::FINAL_STRING: " . ChildFinal::FINAL_STRING . "\n";