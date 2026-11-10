<?php
try {
    try {
        $r = array_map(function($v) { throw new LogicException("in"); }, [1]);
    } catch (LogicException $e) {
        echo "inner: ", $e->getMessage(), "\n";
        throw new RuntimeException("re");
    }
} catch (RuntimeException $e) { echo "outer: ", $e->getMessage(), "\n"; }
echo "tail\n";
