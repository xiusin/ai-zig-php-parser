<?php
// Test 067: Type casting, type conversion
class TypeCasting {
    public function process(): string {
        $out = "";

        $out .= "=== Integer casting ===\n";
        $out .= "(int)'123': " . (int)'123' . "\n";
        $out .= "(int)'12.3': " . (int)'12.3' . "\n";
        $out .= "(int)12.9: " . (int)12.9 . "\n";
        $out .= "(int)'abc': " . (int)'abc' . "\n";
        $out .= "(int)true: " . (int)true . "\n";
        $out .= "(int)false: " . (int)false . "\n";
        $out .= "(int)null: " . (int)null . "\n";

        $out .= "\n=== Float casting ===\n";
        $out .= "(float)'3.14': " . (float)'3.14' . "\n";
        $out .= "(float)'123': " . (float)'123' . "\n";
        $out .= "(float)100: " . (float)100 . "\n";

        $out .= "\n=== String casting ===\n";
        $out .= "(string)123: " . (string)123 . "\n";
        $out .= "(string)3.14: " . (string)3.14 . "\n";
        $out .= "(string)true: " . (string)true . "\n";
        $out .= "(string)false: " . (string)false . "\n";
        $out .= "(string)null: " . (string)null . "\n";
        $out .= "(string)['a','b']: " . (string)['a','b'] . "\n";

        $out .= "\n=== Boolean casting ===\n";
        $out .= "(bool)1: " . ((bool)1 ? 'true' : 'false') . "\n";
        $out .= "(bool)0: " . ((bool)0 ? 'true' : 'false') . "\n";
        $out .= "(bool)'': " . ((bool)'' ? 'true' : 'false') . "\n";
        $out .= "(bool)'non-empty': " . ((bool)'non-empty' ? 'true' : 'false') . "\n";
        $out .= "(bool)[]: " . ((bool)[] ? 'true' : 'false') . "\n";
        $out .= "(bool)[1]: " . ((bool)[1] ? 'true' : 'false') . "\n";

        $out .= "\n=== Array casting ===\n";
        $out .= "(array)123: " . json_encode((array)123) . "\n";
        $out .= "(array)'string': " . json_encode((array)'string') . "\n";
        $out .= "(array)true: " . json_encode((array)true) . "\n";
        $out .= "(array)null: " . json_encode((array)null) . "\n";

        $out .= "\n=== Object casting ===\n";
        $out .= "(object)['a'=>1,'b'=>2]: " . json_encode((object)['a'=>1,'b'=>2]) . "\n";
        $out .= "(object)123: " . json_encode((object)123) . "\n";
        $out .= "(object)'str': " . json_encode((object)'str') . "\n";

        return $out;
    }
}

$lab = new TypeCasting();
echo $lab->process();

echo "\n=== Settype ===\n";
$value = '123';
var_dump($value);
settype($value, 'int');
var_dump($value);

$value = 3.14;
settype($value, 'string');
var_dump($value);

$value = 'yes';
settype($value, 'bool');
var_dump($value);