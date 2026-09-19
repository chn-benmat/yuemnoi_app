from pydantic import BaseModel, Field


class SearchSource(BaseModel):
    """Domain entity representing a web search result source."""
    title: str = ""
    url: str = ""
    link: str = ""
    domain: str = ""
    snippet: str = ""

    def __init__(self, **data):
        super().__init__(**data)
        if not self.url and self.link:
            self.url = self.link
        elif not self.link and self.url:
            self.link = self.url
