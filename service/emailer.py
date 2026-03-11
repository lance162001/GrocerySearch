"""Email utilities — newsletter and simple notification senders."""

from __future__ import annotations

import os
import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from dotenv import load_dotenv
from jinja2 import Environment, FileSystemLoader
from sqlalchemy.orm import Session

from models import Product
from models.base import engine

load_dotenv()

_SMTP_PORT = 465
_PASSWORD = os.getenv("password")
_SENDER = os.getenv("username")
_RECEIVER = "lancegruber2@gmail.com"

_TEMPLATE_ENV = Environment(loader=FileSystemLoader("templates/"))
_NEWSLETTER_HTML = _TEMPLATE_ENV.get_template("newsletter.html")
_NEWSLETTER_TXT = _TEMPLATE_ENV.get_template("newsletter.txt")


def _smtp_connection():
    """Context manager for an authenticated SMTP_SSL connection."""
    ctx = ssl.create_default_context()
    return smtplib.SMTP_SSL("smtp.gmail.com", _SMTP_PORT, context=ctx)


def _lowest_formatted_price(pp) -> str:
    size_label = pp.size if pp.size != "N/A" else "each"
    if pp.member_price:
        return f"Member Sale: ${pp.member_price} : {size_label}"
    if pp.sale_price:
        return f"Sale: ${pp.sale_price} : {size_label}"
    return f"${pp.base_price} : {size_label}"


def send(data: dict) -> None:
    """Send the HTML newsletter with new product data."""
    sess = Session(engine)
    try:
        # Enrich product instances with product info and price
        for pi in data["product_instances"]:
            pi.prod = next((p for p in data["products"] if p.id == pi.product_id), None)
            if pi.prod is None:
                pi.prod = sess.get(Product, pi.product_id)
            for pp in list(data["price_points"]):
                if pp.instance_id == pi.id:
                    pi.price = _lowest_formatted_price(pp)
                    data["price_points"].remove(pp)
                    break

        data["companies"].sort(key=lambda c: c.id)
        for store in data["stores"]:
            company = data["companies"][store.company_id - 1]
            store.company_name = company.name
            store.company_logo = company.logo_url

        html = _NEWSLETTER_HTML.render(
            stores=data["stores"],
            companies=data["companies"],
            products=data["product_instances"],
        )
        txt = _NEWSLETTER_TXT.render(
            stores=data["stores"],
            companies=data["companies"],
            products=data["product_instances"],
        )

        msg = MIMEMultipart("alternative")
        msg.set_charset("utf8")
        msg["Subject"] = "GrocerySearch Newsletter"
        msg["From"] = _SENDER
        msg["To"] = _RECEIVER
        msg.attach(MIMEText(txt.encode("utf-8"), "plain", "UTF-8"))
        msg.attach(MIMEText(html.encode("utf-8"), "html", "UTF-8"))

        with _smtp_connection() as server:
            server.login(_SENDER, _PASSWORD)
            server.sendmail(_SENDER, _RECEIVER, msg.as_string())
    finally:
        sess.close()


def simple_send(body: str) -> None:
    """Send a plain-text notification email.  First line becomes the subject."""
    subject, _, rest = body.partition("\n")
    msg = MIMEMultipart("alternative")
    msg.set_charset("utf8")
    msg["Subject"] = subject
    msg["From"] = _SENDER
    msg["To"] = _RECEIVER
    msg.attach(MIMEText(rest, "plain", "UTF-8"))

    with _smtp_connection() as server:
        server.login(_SENDER, _PASSWORD)
        server.sendmail(_SENDER, _RECEIVER, msg.as_string())


if __name__ == "__main__":
    from models import Product_Instance, PricePoint, Store, Company

    dummy = {
        "products": [
            Product(id=1, company_id=1, name="Banana", brand="Produce",
                    picture_url="https://i5.walmartimages.com/seo/Fresh-Banana-Fruit-Each.jpeg"),
        ],
        "product_instances": [Product_Instance(store_id=1, product_id=1)],
        "price_points": [PricePoint(base_price="0.29", sale_price="0.19", size="per lb", instance_id=1)],
        "stores": [
            Store(id=1, company_id=1, scraper_id=10413, address="442 Washington St",
                  zipcode="02482", town="Wellesley", state="Massachusetts"),
            Store(id=2, company_id=2, scraper_id=509, address="958 Highland Ave",
                  zipcode="02494", town="Needham", state="Massachusetts"),
        ],
        "companies": [
            Company(id=1, logo_url="https://example.com/wf.png", name="Whole Foods"),
            Company(id=2, logo_url="https://example.com/tj.png", name="Trader Joes"),
        ],
    }
    send(dummy)