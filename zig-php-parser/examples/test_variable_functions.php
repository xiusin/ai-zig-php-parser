<?php

echo "=== Testing PHP Variable Functions ===\n";

// Test is_null function
echo "\n--- Testing is_null() ---\n";
$null_var = null;
$int_var = 42;
$string_var = "hello";
$empty_string = "";

echo "is_null(null): " . (is_null($null_var) ? "true" : "false") . "\n";
echo "is_null(42): " . (is_null($int_var) ? "true" : "false") . "\n";
echo "is_null('hello'): " . (is_null($string_var) ? "true" : "false") . "\n";
echo "is_null(''): " . (is_null($empty_string) ? "true" : "false") . "\n";

// Test empty function
echo "\n--- Testing empty() ---\n";
$false_var = false;
$true_var = true;
$zero_int = 0;
$nonzero_int = 123;
$zero_float = 0.0;
$nonzero_float = 3.14;
$zero_string = "0";
$empty_array = [];
$nonempty_array = [1, 2, 3];

echo "empty(null): " . (empty($null_var) ? "true" : "false") . "\n";
echo "empty(false): " . (empty($false_var) ? "true" : "false") . "\n";
echo "empty(true): " . (empty($true_var) ? "true" : "false") . "\n";
echo "empty(0): " . (empty($zero_int) ? "true" : "false") . "\n";
echo "empty(123): " . (empty($nonzero_int) ? "true" : "false") . "\n";
echo "empty(0.0): " . (empty($zero_float) ? "true" : "false") . "\n";
echo "empty(3.14): " . (empty($nonzero_float) ? "true" : "false") . "\n";
echo "empty(''): " . (empty($empty_string) ? "true" : "false") . "\n";
echo "empty('0'): " . (empty($zero_string) ? "true" : "false") . "\n";
echo "empty('hello'): " . (empty($string_var) ? "true" : "false") . "\n";
echo "empty([]): " . (empty($empty_array) ? "true" : "false") . "\n";
echo "empty([1,2,3]): " . (empty($nonempty_array) ? "true" : "false") . "\n";

// Test unset function
echo "\n--- Testing unset() ---\n";
$test_var = "I will be unset";
echo "Before unset: \$test_var = '$test_var'\n";
unset($test_var);
echo "After unset: is_null(\$test_var) = " . (is_null($test_var) ? "true" : "false") . "\n";

// Test with array elements
echo "\n--- Testing unset() with arrays ---\n";
$test_array = ["a" => 1, "b" => 2, "c" => 3];
echo "Before unset: array has " . count($test_array) . " elements\n";
unset($test_array["b"]);
echo "After unset(\$test_array['b']): array has " . count($test_array) . " elements\n";

// Practical examples
echo "\n--- Practical Examples ---\n";

// Form validation example
function validateForm($data) {
    $errors = [];
    
    if (empty($data['name'])) {
        $errors[] = "Name is required";
    }
    
    if (empty($data['email'])) {
        $errors[] = "Email is required";
    }
    
    if (!empty($data['age']) && $data['age'] < 0) {
        $errors[] = "Age must be positive";
    }
    
    return $errors;
}

$form_data1 = ['name' => '', 'email' => 'test@example.com', 'age' => 25];
$form_data2 = ['name' => 'John', 'email' => 'john@example.com', 'age' => -5];
$form_data3 = ['name' => 'Jane', 'email' => 'jane@example.com'];

echo "Form validation results:\n";
$errors1 = validateForm($form_data1);
echo "Form 1 errors: " . (empty($errors1) ? "None" : implode(", ", $errors1)) . "\n";

$errors2 = validateForm($form_data2);
echo "Form 2 errors: " . (empty($errors2) ? "None" : implode(", ", $errors2)) . "\n";

$errors3 = validateForm($form_data3);
echo "Form 3 errors: " . (empty($errors3) ? "None" : implode(", ", $errors3)) . "\n";

// Cleanup example
echo "\n--- Cleanup Example ---\n";
$temp_vars = ['temp1' => 'data1', 'temp2' => 'data2', 'temp3' => 'data3'];
echo "Before cleanup: " . count($temp_vars) . " temp variables\n";

foreach ($temp_vars as $key => $value) {
    if (!is_null($value)) {
        unset($temp_vars[$key]);
    }
}

echo "After cleanup: " . count($temp_vars) . " temp variables\n";

echo "\n=== Tests completed ===\n";

?>