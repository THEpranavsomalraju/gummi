"""Contract errors: HTTP status plus {"error": {"code", "message"}} (CONTRACT section 1, codes listed in 1.3)."""


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message
