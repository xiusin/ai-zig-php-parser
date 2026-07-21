<?php
// 异常处理
class HttpException extends Exception {
    public int $statusCode;

    public function __construct(int $statusCode, string $message = '', int $code = 0, ?Throwable $previous = null) {
        $this->statusCode = $statusCode;
        parent::__construct($message, $code, $previous);
    }
}

class NotFoundException extends HttpException {
    public function __construct(string $message = 'Not Found') {
        parent::__construct(404, $message);
    }
}

class UnauthorizedException extends HttpException {
    public function __construct(string $message = 'Unauthorized') {
        parent::__construct(401, $message);
    }
}

class ForbiddenException extends HttpException {
    public function __construct(string $message = 'Forbidden') {
        parent::__construct(403, $message);
    }
}

class BadRequestException extends HttpException {
    public function __construct(string $message = 'Bad Request') {
        parent::__construct(400, $message);
    }
}

class ExceptionHandler {
    private Logger $logger;

    public function __construct() {
        $this->logger = new Logger();
    }

    public function render(Throwable $e): Response {
        if ($e instanceof HttpException) {
            $status = $e->statusCode;
            $message = $e->getMessage();
        } elseif ($e instanceof ValidationException) {
            $status = 422;
            $message = 'Validation failed';
            return Response::json(['error' => $message, 'details' => $e->errors], $status);
        } else {
            $status = 500;
            $message = 'Internal Server Error';
            $this->logger->error('Unhandled exception: ' . $e->getMessage(), [
                'file' => $e->getFile(),
                'line' => $e->getLine(),
            ]);
        }

        return Response::json(['error' => $message, 'code' => $status], $status);
    }

    public function report(Throwable $e): void {
        $level = $e instanceof HttpException ? Logger::WARNING : Logger::ERROR;
        $this->logger->log($level, $e->getMessage(), [
            'type' => get_class($e),
            'file' => $e->getFile(),
            'line' => $e->getLine(),
        ]);
    }
}
