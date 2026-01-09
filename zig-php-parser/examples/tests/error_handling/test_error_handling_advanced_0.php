<?php
class CustomException extends Exception {}
class ValidationException extends Exception {}

function validate($value) {
    if ($value === null) {
        throw new ValidationException("Value cannot be null");
    }
    if ($value === "") {
        throw new CustomException("Value cannot be empty");
    }
    return true;
}

try {
    validate(null);
} catch (ValidationException $e) {
    echo "Caught ValidationException: " . $e->getMessage() . "\n";
} catch (CustomException $e) {
    echo "Caught CustomException: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}

try {
    validate("");
} catch (ValidationException $e) {
    echo "Caught ValidationException: " . $e->getMessage() . "\n";
} catch (CustomException $e) {
    echo "Caught CustomException: " . $e->getMessage() . "\n";
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}

try {
    validate("valid");
    echo "Validation passed\n";
} catch (Exception $e) {
    echo "Caught Exception: " . $e->getMessage() . "\n";
}
?>