<?php
$v = "s"; try { rsort($v); } catch (TypeError $e) { echo "rsort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { asort($v); } catch (TypeError $e) { echo "asort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { arsort($v); } catch (TypeError $e) { echo "arsort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { ksort($v); } catch (TypeError $e) { echo "ksort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { krsort($v); } catch (TypeError $e) { echo "krsort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { natsort($v); } catch (TypeError $e) { echo "natsort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { natcasesort($v); } catch (TypeError $e) { echo "natcasesort caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { shuffle($v); } catch (TypeError $e) { echo "shuffle caught: ", $e->getMessage(), "\n"; }
$v = "s"; try { sort($v); } catch (TypeError $e) { echo "top-level-style\n"; }
$a = [3,1,2]; var_dump(rsort($a)); echo json_encode($a), "\n";
