from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_product_search_empty_store_ids():
    """Search should work with empty store IDs — returns results from all stores."""
    resp = client.post(
        "/stores/product_search",
        json={"ids": [], "tags": [], "search": "milk", "on_sale": False, "has_spread": False},
    )
    assert resp.status_code == 200

def test_product_search_with_company_ids():
    """Search should accept optional company_ids (chain filter)."""
    resp = client.post(
        "/stores/product_search",
        json={"ids": [], "tags": [], "search": "milk", "on_sale": False, "has_spread": False, "company_ids": [1]},
    )
    assert resp.status_code == 200
