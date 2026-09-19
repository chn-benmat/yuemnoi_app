class DomainException(Exception):
    """Base exception for domain layer errors."""
    pass


class LLMProviderException(DomainException):
    """Raised when an individual LLM provider encounters an error (rate limit, timeout, failure)."""
    def __init__(self, provider: str, model: str, message: str, status_code: int = 500):
        super().__init__(f"[{provider}:{model}] {message}")
        self.provider = provider
        self.model = model
        self.status_code = status_code


class AllLLMProvidersExhaustedException(DomainException):
    """Raised when all primary and fallback LLM models have been exhausted without success."""
    def __init__(self, message: str = "All cloud LLM models in the cascade failed or exhausted quotas."):
        super().__init__(message)


class DatabaseException(DomainException):
    """Raised when database query or connection fails."""
    pass


class SearchException(DomainException):
    """Raised when web search fails."""
    pass
