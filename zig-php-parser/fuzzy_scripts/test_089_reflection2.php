<?php
// Test 089: ReflectionMethod, ReflectionParameter
class ParamTarget {
    public function method(string $a, int $b = 10, ?string $c = null): string {
        return "$a, $b, " . ($c ?? 'null');
    }
}

echo "=== ReflectionMethod ===\n";
$rm = new ReflectionMethod(ParamTarget::class, 'method');
echo "Name: " . $rm->getName() . "\n";
echo "Number of parameters: " . $rm->getNumberOfParameters() . "\n";
echo "Number of required params: " . $rm->getNumberOfRequiredParameters() . "\n";

echo "\n=== ReflectionParameter ===\n";
$params = $rm->getParameters();
foreach ($params as $param) {
    echo "  {$param->getName()}:\n";
    echo "    Position: " . $param->getPosition() . "\n";
    echo "    Optional: " . ($param->isOptional() ? 'yes' : 'no') . "\n";
    echo "    Allows null: " . ($param->allowsNull() ? 'yes' : 'no') . "\n";
    if ($param->isDefaultAvailable()) {
        $default = $param->getDefaultValue();
        echo "    Default: " . var_export($default, true) . "\n";
    }
}

echo "\n=== Invoke ===\n";
$obj = new ParamTarget();
echo "Invoke: " . $rm->invoke($obj, 'test', 20) . "\n";

echo "\n=== InvokeArgs ===\n";
echo "InvokeArgs: " . $rm->invokeArgs($obj, ['arg1', 30, 'arg3']) . "\n";