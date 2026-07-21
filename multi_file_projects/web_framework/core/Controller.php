<?php
// 控制器基类
abstract class Controller {
    protected Container $container;

    public function __construct() {
        $this->container = Container::getInstance();
    }

    protected function json(mixed $data, int $status = 200): Response {
        return Response::json($data, $status);
    }

    protected function view(string $template, array $data = [], int $status = 200): Response {
        $engine = $this->container->make('template');
        $html = $engine->render($template, $data);
        return Response::html($html, $status);
    }

    protected function redirect(string $url, int $status = 302): Response {
        return Response::redirect($url, $status);
    }

    protected function validate(Request $request, array $rules): array {
        $validator = new Validator($request->all(), $rules);
        if (!$validator->passes()) {
            throw new ValidationException($validator->errors());
        }
        return $validator->validated();
    }
}
