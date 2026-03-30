<?php
// Test 037: Superglobals simulation, $GLOBALS, $_SERVER, $_ENV
class GlobalsLab {
    public function process(): string {
        $out = "";

        $GLOBALS['test_var'] = 'Hello from globals';
        $out .= "GLOBALS['test_var']: " . $GLOBALS['test_var'] . "\n";

        $out .= "count(GLOBALS): " . count($GLOBALS) . " keys\n";

        unset($GLOBALS['test_var']);
        $out .= "After unset, isset(GLOBALS['test_var']): " . (isset($GLOBALS['test_var']) ? 'true' : 'false') . "\n";

        return $out;
    }

    public function extractSim(): string {
        $out = "";

        $data = [
            'name' => 'Alice',
            'age' => 30,
            'city' => 'NYC',
        ];

        extract($data);
        $out .= "After extract: name=$name, age=$age, city=$city\n";

        $data2 = [
            'name' => 'Bob',
            'age' => 25,
        ];
        extract($data2, EXTR_SKIP);
        $out .= "After extract with SKIP: name=$name, age=$age\n";

        $data3 = [
            'prefix_name' => 'Charlie',
            'prefix_age' => 35,
        ];
        extract($data3, EXTR_PREFIX_ALL, 'pre');
        $out .= "After extract with PREFIX_ALL: pre_name=$pre_name, pre_age=$pre_age\n";

        return $out;
    }

    public function compactSim(): string {
        $out = "";

        $name = 'Test';
        $value = 42;
        $active = true;

        $result = compact('name', 'value', 'active');
        $out .= "compact result: " . json_encode($result) . "\n";

        $result2 = compact(['name', 'value']);
        $out .= "compact with array: " . json_encode($result2) . "\n";

        return $out;
    }

    public function getDefinedVars(): string {
        $out = "";
        $vars = get_defined_vars();
        $keys = array_slice(array_keys($vars), 0, 10);
        $out .= "get_defined_vars keys (first 10): " . implode(', ', $keys) . "\n";
        return $out;
    }
}

echo "=== Globals Lab ===\n";
$lab = new GlobalsLab();
echo $lab->process();

echo "\n=== Extract simulation ===\n";
echo $lab->extractSim();

echo "\n=== Compact simulation ===\n";
echo $lab->compactSim();

echo "\n=== get_defined_vars ===\n";
echo $lab->getDefinedVars();

echo "\n=== $_SERVER simulation ===\n";
echo "PHP_SAPI: " . PHP_SAPI . "\n";
echo "PHP_VERSION: " . PHP_VERSION . "\n";
echo "DEFAULT_INCLUDE_PATH: " . DEFAULT_INCLUDE_PATH . "\n";
echo "PHP_OS_FAMILY: " . PHP_OS_FAMILY . "\n";

echo "\n=== getenv simulation ===\n";
$path = getenv('PATH');
echo "PATH exists: " . ($path !== false ? 'yes' : 'no') . "\n";
putenv('TEST_VAR=test_value');
echo "TEST_VAR after putenv: " . getenv('TEST_VAR') . "\n";
putenv('TEST_VAR');
echo "TEST_VAR after unset: " . (getenv('TEST_VAR') ?: 'not set') . "\n";