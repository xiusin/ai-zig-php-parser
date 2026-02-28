<?php

$arr = ["img2.png", "img10.png", "img1.png"];
sort($arr);
echo implode(",", $arr);
natsort($arr);
echo implode(",", $arr);

?>
