class DomainException(Exception):
    """Base exception for domain layer errors."""
    pass


class KnowledgeDocumentException(DomainException):
    """Safe operational error without exposing document or filesystem contents."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(f"Knowledge document error: {code}")


class LLMProviderException(DomainException):
    """Raised when an individual LLM provider encounters an error (rate limit, timeout, failure)."""
    def __init__(self, provider: str, model: str, message: str, status_code: int = 500,
                 retry_after: float | None = None, error_code: str = "provider_failure"):
        super().__init__(f"[{provider}:{model}] {message}")
        self.provider = provider
        self.model = model
        self.status_code = status_code
        self.retry_after = retry_after
        self.error_code = error_code


class RuntimeConfigurationException(DomainException):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


class AllLLMProvidersExhaustedException(DomainException):
    """Raised when all primary and fallback LLM models have been exhausted without success."""
    def __init__(self, message: str = "All cloud LLM models in the cascade failed or exhausted quotas.",
                 code: str = "providers_exhausted", retry_after: float | None = None):
        super().__init__(message)
        self.code = code
        self.retry_after = retry_after


class DatabaseException(DomainException):
    """Raised when database query or connection fails."""
    pass


class SearchException(DomainException):
    """Raised when web search fails."""
    pass
