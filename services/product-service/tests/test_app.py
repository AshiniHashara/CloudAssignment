import pytest
from app import app, InMemoryStore


@pytest.fixture
def client():
    app.config["TESTING"] = True
    # Fresh store per test so seed data / stock mutations don't leak between tests.
    import app as app_module
    app_module.store = InMemoryStore()
    with app.test_client() as client:
        yield client


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "healthy"


def test_ready(client):
    res = client.get("/ready")
    assert res.status_code == 200


def test_list_products_returns_seed_data(client):
    res = client.get("/products")
    body = res.get_json()
    assert res.status_code == 200
    assert body["count"] == 6
    assert len(body["products"]) == 6


def test_list_products_filter_by_category(client):
    res = client.get("/products?category=electronics")
    body = res.get_json()
    assert res.status_code == 200
    assert all(p["category"] == "electronics" for p in body["products"])


def test_list_products_search(client):
    res = client.get("/products?search=headphone")
    body = res.get_json()
    assert body["count"] == 1
    assert body["products"][0]["id"] == "prod-001"


def test_get_product_by_id(client):
    res = client.get("/products/prod-001")
    assert res.status_code == 200
    assert res.get_json()["name"] == "Wireless Bluetooth Headphones"


def test_get_product_not_found(client):
    res = client.get("/products/does-not-exist")
    assert res.status_code == 404


def test_create_product(client):
    res = client.post("/products", json={"name": "Test Widget", "price": 9.99})
    body = res.get_json()
    assert res.status_code == 201
    assert body["name"] == "Test Widget"
    assert body["price"] == 9.99
    # Newly created product should be retrievable
    res2 = client.get(f"/products/{body['id']}")
    assert res2.status_code == 200


def test_create_product_missing_fields(client):
    res = client.post("/products", json={"description": "no name or price"})
    assert res.status_code == 400


def test_update_product(client):
    res = client.put("/products/prod-001", json={"price": 99.99})
    body = res.get_json()
    assert res.status_code == 200
    assert body["price"] == 99.99


def test_update_product_not_found(client):
    res = client.put("/products/does-not-exist", json={"price": 1})
    assert res.status_code == 404


def test_delete_product(client):
    res = client.delete("/products/prod-001")
    assert res.status_code == 200
    res2 = client.get("/products/prod-001")
    assert res2.status_code == 404


def test_check_stock(client):
    res = client.get("/products/prod-001/stock")
    body = res.get_json()
    assert res.status_code == 200
    assert body["stock"] == 150
    assert body["available"] is True


def test_decrement_stock(client):
    res = client.post("/products/prod-001/stock/decrement", json={"quantity": 10})
    assert res.status_code == 200
    stock_res = client.get("/products/prod-001/stock")
    assert stock_res.get_json()["stock"] == 140


def test_decrement_stock_insufficient(client):
    res = client.post(
        "/products/prod-001/stock/decrement", json={"quantity": 999999}
    )
    assert res.status_code == 409


def test_list_categories(client):
    res = client.get("/categories")
    body = res.get_json()
    assert res.status_code == 200
    assert "electronics" in body["categories"]
    assert body["categories"] == sorted(body["categories"])
