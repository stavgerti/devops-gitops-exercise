from app import app


def test_index_is_html_with_version_and_pod():
    r = app.test_client().get("/")
    assert r.status_code == 200
    assert r.content_type.startswith("text/html")
    body = r.get_data(as_text=True)
    assert "Version:" in body and "Served by pod:" in body


def test_healthz():
    assert app.test_client().get("/healthz").status_code == 200
