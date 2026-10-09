class GuidanceGenerationError(Exception):
    """Safe operational failure without fabricated dialogue or catalog matches."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(f"Catalog guidance error: {code}")
