<?php

echo "=== Kiro HTTP Server with Cookie and Session Demo ===\n";

// This function will be our main request handler
function handle_request($request, $response) {
    // --- Cookie Demo ---
    $visit_cookie = $request->getCookie('visit_time');
    $response->setCookie('visit_time', time(), ['path' => '/']);

    // --- Session Demo ---
    $session = $request->session();

    $count = $session->get('page_views');
    if ($count === null) {
        $count = 1;
    } else {
        $count = $count + 1;
    }
    $session->set('page_views', $count);

    // --- Generate Response ---
    $body = "<h1>Welcome to Kiro!</h1>";
    $body .= "<p>Page views in this session: " . $count . "</p>";
    if ($visit_cookie) {
        $body .= "<p>Last visit (from cookie): " . date('Y-m-d H:i:s', $visit_cookie) . "</p>";
    } else {
        $body .= "<p>This is your first visit! We've set a cookie for next time.</p>";
    }

    $response->html($body);
}

// In a real application, the server would be started here.
// For this example, we assume the server is running and `handle_request`
// is registered as the handler for a route, e.g., '/'.
function handle_user($request, $response) {
    $user_id = $request->getParam('id');
    $response->text("User ID: " . $user_id);
}


echo "Server handler 'handle_request' is defined.\n";
echo "To test, run the http_server and navigate to the root URL.\n";
echo "You should see a page view counter that increments on refresh.\n";
echo "You should also see a 'visit_time' cookie being set in your browser.\n";

?>
