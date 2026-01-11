<?php
/**
 * 测试联合类型注解
 */

class TestUnion {
    public function testUnion(int|string $value): int|string {
        return $value;
    }
}

echo "Union type test passed\n";
