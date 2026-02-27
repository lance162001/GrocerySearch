import os
import io
import requests
from PIL import Image, UnidentifiedImageError
from sqlalchemy.orm import Session
from models.base import engine
from models import Company


def ensure_logo_dir():
    path = os.path.join(os.path.dirname(__file__), 'static', 'logos')
    os.makedirs(path, exist_ok=True)
    return path


def download_logo(company, session: Session, out_dir: str) -> bool:
    url = (company.logo_url or '').strip()
    if url == '':
        return False
    # If already a local path, skip
    if url.startswith('/') and '/static/' in url:
        return True
    if not url.startswith('http'):
        # some entries store hostless paths like 'traderjoes.com/..'
        url = 'http://' + url

    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
    except Exception as e:
        print(f"[logo_downloader] failed request for company {company.id}: {e}")
        return False

    try:
        img = Image.open(io.BytesIO(resp.content))
        img = img.convert('RGBA')
    except UnidentifiedImageError as e:
        print(f"[logo_downloader] content not an image for company {company.id}: {e}")
        return False
    except Exception as e:
        print(f"[logo_downloader] image open error for company {company.id}: {e}")
        return False

    out_path = os.path.join(out_dir, f'company_{company.id}.png')
    try:
        img.save(out_path, format='PNG')
    except Exception as e:
        print(f"[logo_downloader] failed to save image for company {company.id}: {e}")
        return False

    # update DB to point to local static path
    local_url = f"/static/logos/company_{company.id}.png"
    company.logo_url = local_url
    try:
        session.add(company)
        session.commit()
    except Exception as e:
        print(f"[logo_downloader] failed to update DB for company {company.id}: {e}")
        session.rollback()
        return False

    print(f"[logo_downloader] saved logo for company {company.id} -> {local_url}")
    return True


def run_download_all():
    ensure_logo_dir()
    out_dir = os.path.join(os.path.dirname(__file__), 'static', 'logos')
    sess = Session(engine)
    companies = sess.query(Company).all()
    for c in companies:
        try:
            download_logo(c, sess, out_dir)
        except Exception as e:
            print(f"[logo_downloader] unexpected error for company {c.id}: {e}")


if __name__ == '__main__':
    run_download_all()
