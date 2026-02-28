<?php
$prime = true; for ($i = 2; $i <= 29; $i++) { if (29 % $i == 0 && $i != 29) { $prime = false; break; } } echo $prime ? "prime" : "not";?>
