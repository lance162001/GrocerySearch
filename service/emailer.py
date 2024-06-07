import smtplib, ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv
import os
from jinja2 import Environment, FileSystemLoader
from models import Product, Product_Instance, PricePoint, Store, Company
from models.base import Base, engine
from sqlalchemy.orm import Session

sess = Session(engine)

environment = Environment(loader=FileSystemLoader("templates/"))
newsletter = environment.get_template("newsletter.html")
plaintext = environment.get_template("newsletter.txt")
load_dotenv()

port = 465
password = os.getenv("password")
sender_email = os.getenv("username")
receiver_email = "lancegruber2@gmail.com"

message = MIMEMultipart("alternative")
message.set_charset("utf8")
message["Subject"] = "testing!"
message["From"] = sender_email
message["To"] = receiver_email

def build_message(data):
    html = newsletter.render(
        stores=data["stores"],
        companies=data["companies"],
        products=data["product_instances"]
    )
    txt = plaintext.render(
        stores=data["stores"],
        companies=data["companies"],
        products=data["product_instances"]
    )
    message.attach(MIMEText(txt.encode('utf-8'),"plain", "UTF-8"))
    message.attach(MIMEText(html.encode('utf-8'),"html", "UTF-8"))
    return message
def lowest_formatted_price(pp):
    if pp.size == "N/A":
        pp.size = "each"
    if pp.member_price:
        return "Member Sale: $" + str(pp.member_price) + " : " + pp.size
    elif pp.sale_price:
        return "Sale: $" + str(pp.sale_price) + " : " + pp.size
    else:
        return "$" + str(pp.base_price) + " : " + pp.size

def send(data):
    for p in data["product_instances"]:
        #p.prod = Product(company_id=10,name="---",brand="---",picture_url="https://logos-world.net/wp-content/uploads/2022/02/Trader-Joes-Emblem.png")
        for prod in data["products"]:
            if prod.id == p.product_id:
                p.prod = prod
                break
        if not p.prod:
            p.prod = sess.query(Product).get(p.product_id)
        for pp in data["price_points"]:
            if pp.instance_id == p.id:
                p.price = lowest_formatted_price(pp)
                data["price_points"].remove(pp)
                break

    data["companies"].sort(key=lambda c: c.id)
    for s in data["stores"]:
        s.company_name = data["companies"][s.company_id-1].name
        s.company_logo = data["companies"][s.company_id-1].logo_url

    message = build_message(data)
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL("smtp.gmail.com",port,context=context) as server:
        server.login(sender_email,password)
        server.sendmail(sender_email, receiver_email, message.as_string())

def simple_send(message):
    msg = MIMEText(message, _charset="UTF-8")
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL("smtp.gmail.com",port,context=context) as server:
        server.login(sender_email,password)
        server.sendmail(sender_email, receiver_email, msg.as_string())

if __name__ == "__main__":
    dummy_data = { "products": [], "product_instances": [], "price_points": [], "stores": [], "companies": []}
    dummy_data["companies"].append(Company(id=1, logo_url="https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1&ipt=21419f3cd82d823842c0297318a102a87ac9b6b801dd2417cc5661c32591fbc4&ipo=images", name="Whole Foods"))
    dummy_data["companies"].append(Company(id=2, logo_url="https://logos-world.net/wp-content/uploads/2022/02/Trader-Joes-Emblem.png", name="Trader Joes"))
    dummy_data["stores"].append(Store(id=1, company_id=1, scraper_id=10413, address="442 Washington St", zipcode='02482', town='Wellesley', state='Massachusetts'))
    dummy_data["stores"].append(Store(id=2, company_id=2, scraper_id=509, address="958 Highland Ave", zipcode='02494', town='Needham', state='Massachusetts'))
    dummy_data["products"].append(Product(id=1, company_id=1,name="Banana",brand="Produce",picture_url="https://i5.walmartimages.com/seo/Fresh-Banana-Fruit-Each_5939a6fa-a0d6-431c-88c6-b4f21608e4be.f7cd0cc487761d74c69b7731493c1581.jpeg?odnHeight=640&odnWidth=640&odnBg=FFFFFF"))
    dummy_data["product_instances"].append(Product_Instance(store_id=1,product_id=1))
    dummy_data["price_points"].append(PricePoint(base_price="0.29",sale_price="0.19",size="per lb",instance_id=1))
    send(dummy_data)