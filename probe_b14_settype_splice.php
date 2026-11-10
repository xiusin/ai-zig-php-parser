<?php
$a = 42;
try { $r = settype($a, "bogus_type"); var_dump($r); } catch (ValueError $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($a);
$a = 42;
try { $r = settype($a, 123); var_dump($r); } catch (ValueError $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($a);
$a = "1.5"; var_dump(settype($a, "double")); var_dump($a);
$a = [1,2]; var_dump(settype($a, "null")); var_dump($a);
$s = "str";
try { $r = array_splice($s, 0); var_dump($r); } catch (TypeError $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($s);
$arr = [1,2,3,4];
$r = array_splice($arr, 1, 2);
echo json_encode($r), " ", json_encode($arr), "\n";
