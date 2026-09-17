class DomainException(Exception):
    """Base domain exception."""
    pass

class ItemNotFoundException(DomainException):
    """Raised when an item is not found in database."""
    def __init__(self, item_id: int):
        super().__init__(f"Item with id {item_id} not found.")

class LLMServiceException(DomainException):
    """Raised when LLM fails to generate or format output."""
    pass

class SearchServiceException(DomainException):
    """Raised when search API fails or yields invalid response."""
    pass

class FactVerificationException(DomainException):
    """Raised when fact verification fails."""
    pass
