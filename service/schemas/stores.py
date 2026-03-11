from pydantic import BaseModel, ConfigDict
from typing import Optional


class Company(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: Optional[int] = None
    logo_url: str
    name: str


class Store(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: Optional[int] = None
    company_id: int
    scraper_id: int
    address: str
    town: str
    state: str
    zipcode: str
