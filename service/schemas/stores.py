from pydantic import BaseModel, ConfigDict
from typing import Optional
from datetime import datetime


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


class StoreSuggestionRequest(BaseModel):
    company_id: int
    address: str
    town: str
    state: str
    zipcode: str


class StoreSuggestionResponse(BaseModel):
    id: int
    company_id: int
    address: str
    town: str
    state: str
    zipcode: str
    status: str
    created_at: Optional[datetime] = None
