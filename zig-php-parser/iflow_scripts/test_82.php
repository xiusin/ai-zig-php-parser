<?php

\$arr = [1, 2, 3];
\$mapped = array_map(function(\$x) { return \$x * 2; }, \$arr);
echo implode(",", \$mapped);

?>
