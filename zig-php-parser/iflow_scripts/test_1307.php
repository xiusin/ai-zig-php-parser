<?php
$prime = true; for ($i = 2; $i <= 25; $i++) { if (25 % $i == 0 && $i != 25) { $prime = false; break; } } echo $prime ? "prime" : "not";?>
