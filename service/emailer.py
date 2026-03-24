"""Email utilities — newsletter and simple notification senders."""

from __future__ import annotations

import logging
import os
import smtplib
import ssl
from collections import defaultdict
from datetime import datetime, timedelta
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from functools import lru_cache
from urllib.parse import urlsplit
from uuid import uuid4

from dotenv import load_dotenv
from jinja2 import Environment, FileSystemLoader
from sqlalchemy.orm import Session

from models import PricePoint, Product, Product_Bundle, Product_Instance, Saved_Product, Saved_Store, User
from models.base import engine

load_dotenv()

logger = logging.getLogger(__name__)

_SMTP_PORT = 465
_PASSWORD = os.getenv("SMTP_PASSWORD")
_SENDER = os.getenv("SMTP_USERNAME")
_RECEIVER = os.getenv("EMAIL_RECEIVER")
_TEST_UNSUBSCRIBE_TOKEN = "test-do-not-unsubscribe"
_TEST_BUNDLE_TOKEN = "test-shared-bundle"
_MAX_PRODUCTS_PER_STORE = 10
_FALLBACK_PRODUCT_IMAGE = "https://via.placeholder.com/92?text=Item"
_FALLBACK_STORE_LOGO = "https://via.placeholder.com/56?text=Store"

_TEMPLATE_ENV = Environment(loader=FileSystemLoader("templates/"))
_NEWSLETTER_HTML = _TEMPLATE_ENV.get_template("newsletter.html")
_NEWSLETTER_TXT = _TEMPLATE_ENV.get_template("newsletter.txt")


def _smtp_connection():
    """Context manager for an authenticated SMTP_SSL connection."""
    ctx = ssl.create_default_context()
    return smtplib.SMTP_SSL("smtp.gmail.com", _SMTP_PORT, context=ctx)


def _lowest_formatted_price(pp) -> str:
    size_label = pp.size if pp.size and pp.size != "N/A" else "each"
    if pp.member_price:
        return f"Member: ${pp.member_price} / {size_label}"
    if pp.sale_price:
        return f"Sale: ${pp.sale_price} / {size_label}"
    if pp.base_price:
        return f"${pp.base_price} / {size_label}"
    return "Price unavailable"


def _parse_price(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return float(str(value).replace("$", "").replace(",", "").strip())
    except ValueError:
        return None


def _effective_price(pp: PricePoint) -> float | None:
    return (
        _parse_price(getattr(pp, "member_price", None))
        or _parse_price(getattr(pp, "sale_price", None))
        or _parse_price(getattr(pp, "base_price", None))
    )


def _fmt_money(value: float | None) -> str:
    return f"${value:.2f}" if value is not None else "N/A"


def _price_change_label(old_value: float, new_value: float) -> str:
    delta = new_value - old_value
    if abs(delta) < 0.001:
        return "No change"
    if delta > 0:
        return f"Up {_fmt_money(abs(delta))}"
    return f"Down {_fmt_money(abs(delta))}"


@lru_cache(maxsize=1)
def _frontend_base_url() -> str:
    raw_value = (os.getenv("BASE_URL") or os.getenv("base_url") or "").strip()
    if not raw_value:
        fallback = "http://localhost:3000"
        logger.warning("BASE_URL is not set; falling back to %s for newsletter links", fallback)
        return fallback

    normalized = raw_value
    if "://" not in normalized:
        scheme = "http" if normalized.startswith(("localhost", "127.0.0.1")) else "https"
        normalized = f"{scheme}://{normalized.lstrip('/')}"
        logger.warning(
            "BASE_URL=%s is missing a scheme; using %s for newsletter links",
            raw_value,
            normalized,
        )

    parsed = urlsplit(normalized)
    if not parsed.scheme or not parsed.netloc:
        raise RuntimeError(
            "BASE_URL must be an absolute frontend URL, for example https://yourdomain.com",
        )
    return normalized.rstrip("/")


def _should_receive_newsletter(user: User) -> bool:
    """Return True if this user is due for a newsletter based on their frequency pref."""
    frequency = str(getattr(user, 'newsletter_frequency', None) or 'weekly')
    last_sent = getattr(user, 'newsletter_last_sent_at', None)
    if last_sent is None or not isinstance(last_sent, datetime):
        return True
    elapsed = datetime.now() - last_sent
    if frequency == 'daily':
        return elapsed >= timedelta(hours=20)
    # weekly (default)
    return elapsed >= timedelta(days=6)


def _unsubscribe_url(token: str) -> str:
    return f"{_frontend_base_url()}/unsubscribe?token={token}"


def _ensure_unsubscribe_token(user: User, sess: Session) -> str:
    token = getattr(user, "unsubscribe_token", None)
    if token:
        return str(token)
    token = uuid4().hex
    setattr(user, "unsubscribe_token", token)
    sess.commit()
    return token


def _ensure_test_bundle(sess: Session, product_ids: list[int]) -> str:
    """Upsert a persistent test bundle keyed by _TEST_BUNDLE_TOKEN and return its share URL."""
    bundle = (
        sess.query(Product_Bundle)
        .filter(Product_Bundle.share_token == _TEST_BUNDLE_TOKEN)
        .first()
    )
    if bundle is None:
        bundle = Product_Bundle(user_id=1, name="Test — New this week")
        setattr(bundle, "share_token", _TEST_BUNDLE_TOKEN)
        sess.add(bundle)
        sess.flush()

    # Sync products: clear and re-add so the test bundle stays fresh.
    bundle_id = int(bundle.id)
    sess.query(Saved_Product).filter(Saved_Product.bundle_id == bundle_id).delete()
    for pid in set(product_ids):
        sess.add(Saved_Product(product_id=pid, bundle_id=bundle_id))
    sess.commit()
    return f"{_frontend_base_url()}/shared-bundle?token={_TEST_BUNDLE_TOKEN}"


def _enrich_instances(data: dict, sess: Session) -> None:
    """Attach .prod and .price to every product instance in place."""
    products_by_id = {int(p.id): p for p in data["products"] if p.id is not None}
    latest_price_by_instance: dict[int, PricePoint] = {}

    for pp in data["price_points"]:
        if pp.instance_id is None:
            continue
        instance_id = int(pp.instance_id)
        current = latest_price_by_instance.get(instance_id)
        if current is None:
            latest_price_by_instance[instance_id] = pp
            continue
        current_created = getattr(current, "created_at", None)
        incoming_created = getattr(pp, "created_at", None)
        if not isinstance(current_created, datetime):
            current_created = datetime.min
        if not isinstance(incoming_created, datetime):
            incoming_created = datetime.min
        if incoming_created >= current_created:
            latest_price_by_instance[instance_id] = pp

    for pi in data["product_instances"]:
        pi.prod = products_by_id.get(int(pi.product_id)) if pi.product_id is not None else None
        if pi.prod is None:
            pi.prod = sess.get(Product, pi.product_id)
        pi.image_url = _FALLBACK_PRODUCT_IMAGE
        if pi.prod is not None and getattr(pi.prod, "picture_url", None):
            pi.image_url = str(getattr(pi.prod, "picture_url"))

        pi.price = "Price unavailable"
        if pi.id is not None:
            matched = latest_price_by_instance.get(int(pi.id))
            if matched is not None:
                pi.price = _lowest_formatted_price(matched)


def _build_sections(stores, product_instances) -> list[dict]:
    """Return a list of {store, products, total_count, has_more} dicts."""
    sections = []
    for store in stores:
        if not getattr(store, "company_logo", None):
            store.company_logo = _FALLBACK_STORE_LOGO
        store_products = [pi for pi in product_instances if pi.store_id == int(store.id)]
        if store_products:
            total = len(store_products)
            sections.append({
                "store": store,
                "products": store_products[:_MAX_PRODUCTS_PER_STORE],
                "total_count": total,
                "has_more": total > _MAX_PRODUCTS_PER_STORE,
            })
    return sections


def _create_newsletter_bundle(
    sess: Session,
    user_id: int,
    product_ids: list[int],
    date_str: str,
) -> str:
    """Create a 'New this week' bundle for the user and return its share URL."""
    token = uuid4().hex
    bundle = Product_Bundle(user_id=user_id, name=f"New this week — {date_str}")
    setattr(bundle, "share_token", token)
    sess.add(bundle)
    sess.flush()
    for pid in set(product_ids):
        sess.add(Saved_Product(product_id=pid, bundle_id=int(bundle.id)))
    sess.commit()
    return f"{_frontend_base_url()}/shared-bundle?token={token}"


def _bundle_price_changes(
    sess: Session,
    user_id: int,
    store_ids: set[int],
    products_by_id: dict[int, Product],
    stores_by_id: dict[int, object],
) -> list[dict]:
    """Return changed-price entries for products in the user's bundles at saved stores."""
    saved_rows = (
        sess.query(Saved_Product.product_id)
        .join(Product_Bundle, Saved_Product.bundle_id == Product_Bundle.id)
        .filter(Product_Bundle.user_id == user_id)
        .all()
    )
    saved_product_ids = {int(row[0]) for row in saved_rows if row[0] is not None}
    if not saved_product_ids or not store_ids:
        return []

    instances = (
        sess.query(Product_Instance)
        .filter(Product_Instance.product_id.in_(list(saved_product_ids)))
        .filter(Product_Instance.store_id.in_(list(store_ids)))
        .all()
    )
    if not instances:
        return []

    instance_ids = [int(inst.id) for inst in instances if inst.id is not None]
    if not instance_ids:
        return []

    points = (
        sess.query(PricePoint)
        .filter(PricePoint.instance_id.in_(instance_ids))
        .order_by(
            PricePoint.instance_id.asc(),
            PricePoint.collected_on.desc(),
            PricePoint.created_at.desc(),
            PricePoint.id.desc(),
        )
        .all()
    )

    latest_two_by_instance: dict[int, list[PricePoint]] = defaultdict(list)
    for point in points:
        instance_id = int(getattr(point, "instance_id"))
        bucket = latest_two_by_instance[instance_id]
        if len(bucket) < 2:
            bucket.append(point)

    by_instance = {int(inst.id): inst for inst in instances if inst.id is not None}
    changes: list[dict] = []
    for instance_id, bucket in latest_two_by_instance.items():
        if len(bucket) < 2:
            continue
        newest, previous = bucket[0], bucket[1]
        new_price = _effective_price(newest)
        old_price = _effective_price(previous)
        if new_price is None or old_price is None or abs(new_price - old_price) < 0.001:
            continue

        instance = by_instance.get(instance_id)
        if instance is None:
            continue

        product_id = int(getattr(instance, "product_id"))
        product = products_by_id.get(product_id)
        if product is None:
            product = sess.get(Product, product_id)
            if product is None:
                continue

        store = stores_by_id.get(int(getattr(instance, "store_id")))
        if store is None:
            continue

        changes.append(
            {
                "product_name": product.name,
                "product_brand": product.brand,
                "store_name": getattr(store, "company_name", "Store"),
                "old_price": _fmt_money(old_price),
                "new_price": _fmt_money(new_price),
                "change_label": _price_change_label(old_price, new_price),
            }
        )

    changes.sort(key=lambda entry: abs(float(entry["new_price"].replace("$", "")) - float(entry["old_price"].replace("$", ""))), reverse=True)
    return changes[:8]


def _subject(sections: list[dict], total_count: int) -> str:
    first_store = sections[0]["store"].company_name if sections else "your stores"
    extra = len(sections) - 1
    tail = f" + {extra} more store{'s' if extra != 1 else ''}" if extra > 0 else ""
    return f"New this week: {total_count} item{'s' if total_count != 1 else ''} at {first_store}{tail}"


def _mail_credentials() -> tuple[str, str]:
    if not _SENDER or not _PASSWORD:
        raise RuntimeError("SMTP_USERNAME and SMTP_PASSWORD must be set")
    return _SENDER, _PASSWORD


def send(data: dict, recipient_override: str | None = None) -> None:
    """Send personalized newsletters to users whose saved stores have new products.

    If *recipient_override* is set, skip the user query and send one email
    covering all stores/products in *data* to that address instead.
    """
    sess = Session(engine, expire_on_commit=False)
    try:
        _enrich_instances(data, sess)

        if not data["product_instances"]:
            logger.info("newsletter: no new products — skipping")
            return

        companies_by_id = {int(c.id): c for c in data["companies"]}
        products_by_id = {int(p.id): p for p in data["products"] if p.id is not None}
        for store in data["stores"]:
            company = companies_by_id.get(int(store.company_id))
            if company:
                store.company_name = company.name
                store.company_logo = company.logo_url
        stores_by_id = {int(s.id): s for s in data["stores"] if s.id is not None}

        today = datetime.now().strftime("%B %-d, %Y")

        if recipient_override:
            sections = _build_sections(data["stores"], data["product_instances"])
            total_count = len(data["product_instances"])
            product_ids = [
                int(pi.product_id)
                for pi in data["product_instances"]
                if pi.product_id is not None
            ]
            test_bundle_url = _ensure_test_bundle(sess, product_ids)
            _deliver(
                recipient_override,
                sections,
                total_count,
                today,
                price_changes=[],
                unsubscribe_url=_unsubscribe_url(_TEST_UNSUBSCRIBE_TOKEN),
                bundle_url=test_bundle_url,
            )
            logger.info("newsletter: test send to %s items=%s", recipient_override, total_count)
            return

        active_store_ids = {pi.store_id for pi in data["product_instances"]}

        # Users who have an email and at least one saved store with new products
        rows = (
            sess.query(User, Saved_Store)
            .join(Saved_Store, User.id == Saved_Store.user_id)
            .filter(User.email.isnot(None))
            .filter(User.newsletter_opt_in.isnot(False))
            .filter(Saved_Store.store_id.in_(list(active_store_ids)))
            .all()
        )

        if not rows:
            logger.info("newsletter: no users with emails matching active stores — skipping")
            return

        # Group saved store ids per user
        user_store_ids: dict[int, set[int]] = defaultdict(set)
        user_objects: dict[int, User] = {}
        for user, saved_store in rows:
            user_store_ids[int(user.id)].add(int(saved_store.store_id))
            user_objects[int(user.id)] = user

        for uid, store_ids in user_store_ids.items():
            user = user_objects[uid]
            if not _should_receive_newsletter(user):
                logger.info(
                    "newsletter: skipping user_id=%s (frequency=%s, last_sent=%s)",
                    uid,
                    getattr(user, 'newsletter_frequency', 'weekly'),
                    getattr(user, 'newsletter_last_sent_at', None),
                )
                continue
            user_stores = [s for s in data["stores"] if int(s.id) in store_ids]
            user_instances = [pi for pi in data["product_instances"] if pi.store_id in store_ids]
            if not user_instances:
                continue

            sections = _build_sections(user_stores, user_instances)
            total_count = len(user_instances)
            new_product_ids = [int(pi.product_id) for pi in user_instances if pi.product_id is not None]
            bundle_url = _create_newsletter_bundle(sess, uid, new_product_ids, today)
            unsubscribe_url = _unsubscribe_url(_ensure_unsubscribe_token(user, sess))
            price_changes = _bundle_price_changes(
                sess,
                uid,
                store_ids,
                products_by_id,
                stores_by_id,
            )
            _deliver(
                str(user.email),
                sections,
                total_count,
                today,
                price_changes=price_changes,
                unsubscribe_url=unsubscribe_url,
                bundle_url=bundle_url,
            )
            setattr(user, 'newsletter_last_sent_at', datetime.now())
            sess.commit()
            logger.info(
                "newsletter: sent to user_id=%s stores=%s items=%s",
                uid, store_ids, total_count,
            )
    finally:
        sess.close()


def _deliver(
    recipient: str,
    sections: list[dict],
    total_count: int,
    date: str,
    *,
    price_changes: list[dict],
    unsubscribe_url: str | None,
    bundle_url: str | None,
) -> None:
    """Render templates and send one newsletter email."""
    html = _NEWSLETTER_HTML.render(
        sections=sections,
        date=date,
        total_count=total_count,
        price_changes=price_changes,
        unsubscribe_url=unsubscribe_url,
        bundle_url=bundle_url,
    )
    txt = _NEWSLETTER_TXT.render(
        sections=sections,
        date=date,
        total_count=total_count,
        price_changes=price_changes,
        unsubscribe_url=unsubscribe_url,
        bundle_url=bundle_url,
    )
    sender, password = _mail_credentials()

    msg = MIMEMultipart("alternative")
    msg.set_charset("utf8")
    msg["Subject"] = _subject(sections, total_count)
    msg["From"] = sender
    msg["To"] = recipient
    msg.attach(MIMEText(txt, "plain", "UTF-8"))
    msg.attach(MIMEText(html, "html", "UTF-8"))

    with _smtp_connection() as server:
        server.login(sender, password)
        server.sendmail(sender, recipient, msg.as_string())


def simple_send(body: str) -> None:
    """Send a plain-text notification email.  First line becomes the subject."""
    if not _RECEIVER:
        raise RuntimeError("EMAIL_RECEIVER must be set")
    sender, password = _mail_credentials()

    subject, _, rest = body.partition("\n")
    msg = MIMEMultipart("alternative")
    msg.set_charset("utf8")
    msg["Subject"] = subject
    msg["From"] = sender
    msg["To"] = _RECEIVER
    msg.attach(MIMEText(rest, "plain", "UTF-8"))

    with _smtp_connection() as server:
        server.login(sender, password)
        server.sendmail(sender, _RECEIVER, msg.as_string())


if __name__ == "__main__":
    from models import Product_Instance, PricePoint, Store, Company
    from models.bootstrap import ensure_runtime_schema

    ensure_runtime_schema()

    dummy = {
        "products": [
            Product(id=1, company_id=1, name="Banana", brand="Produce",
                    picture_url="https://upload.wikimedia.org/wikipedia/commons/8/8a/Banana-Single.jpg"),
        ],
        "product_instances": [Product_Instance(id=1, store_id=1, product_id=1)],
        "price_points": [PricePoint(base_price="0.29", sale_price="0.19", size="per lb", instance_id=1)],
        "stores": [
            Store(id=1, company_id=1, scraper_id=10413, address="442 Washington St",
                  zipcode="02482", town="Wellesley", state="Massachusetts"),
        ],
        "companies": [
            Company(id=1, logo_url="https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1", name="Whole Foods"),
        ],
    }
    if not _RECEIVER:
        raise RuntimeError("EMAIL_RECEIVER must be set for dummy sends")
    send(dummy, recipient_override=_RECEIVER)
