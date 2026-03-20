<?php
// Test 136: Multiple catch with different exception types
function testExceptions(int $type): void {
    throw match($type) {
        0 => new RuntimeException('Runtime'),
        1 => new InvalidArgumentException('Invalid'),
        2 => new LogicException('Logic'),
        3 => new DomainException('Domain'),
        default => new Exception('Generic'),
    };
}

echo "=== Multiple catch ===\n";
for ($i = 0; $i < 5; $i++) {
    try {
        testExceptions($i);
    } catch (DomainException $e) {
        echo "DomainException: " . $e->getMessage() . "\n";
    } catch (LogicException | InvalidArgumentException $e) {
        echo "Logic/Invalid: " . get_class($e) . " - " . $e->getMessage() . "\n";
    } catch (RuntimeException $e) {
        echo "RuntimeException: " . $e->getMessage() . "\n";
    } catch (Throwable $e) {
        echo "Throwable: " . get_class($e) . " - " . $e->getMessage() . "\n";
    }
}