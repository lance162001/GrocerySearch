import emailer

from datetime import datetime
import sys
import time
from concurrent.futures import ThreadPoolExecutor, wait, as_completed
import threading

from models.base import Base, engine
from sqlalchemy.orm import Session
from models import Product, Product_Instance, PricePoint, Store, Tag, Tag_Instance, Company
from urllib.request import Request, urlopen
import json
import re
import random
import schedule

sess_id = random.randint(1,1000000000)
sess_start_time=datetime.now()
sess = Session(engine)
headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36'}

wf_categories = ["produce","dairy-eggs","meat","prepared-foods","pantry-essentials","breads-rolls-bakery","desserts","frozen-foods","snacks-chips-salsas-dips","seafood","beverages"]
tj_categories = ["Fresh Fruits and Veggies","Dairy & Eggs","Meat, Seafood & Plant-based","For the Pantry","Bakery","Candies & Cookies", "From The Freezer", ["Chips, Crackers & Crunchy Bites", "Nuts, Dried Fruits, Seeds", "Bars, Jerky &... Surprises"]]
categories = ["produce", "dairy-eggs", "meat", "prepared-foods", "pantry", "bakery", "desserts", "frozen", "snacks", "seafood", "beverages"]
diet_types = ["organic", "vegan", "kosher", "gluten free", "dairy free", "vegetarian"]
tags = {}


blank_emailer_info = { "products": [], "product_instances": [], "price_points": [], "stores": [], "companies": []}
emailer_info = blank_emailer_info.copy()

def setup():
    toAdd = []
    toAdd.append(Company(logo_url="https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1&ipt=21419f3cd82d823842c0297318a102a87ac9b6b801dd2417cc5661c32591fbc4&ipo=images", name="Whole Foods"))
    toAdd.append(Company(logo_url="https://logos-world.net/wp-content/uploads/2022/02/Trader-Joes-Emblem.png", name="Trader Joes"))
    toAdd.append(Store(company_id=1, scraper_id=10413, address="442 Washington St", zipcode='02482', town='Wellesley', state='Massachusetts'))
    toAdd.append(Store(company_id=2, scraper_id=509, address="958 Highland Ave", zipcode='02494', town='Needham', state='Massachusetts'))
    toAdd.append(Store(company_id=1, scraper_id=10319, address="300 Legacy Pl", zipcode="02026", town="Dedham", state="Massachusetts"))
    toAdd.append(Store(company_id=2, scraper_id=512, address="375 Russell St", zipcode='01035', town='Hadley', state='Massachusetts'))
    toAdd.append(Store(company_id=1, scraper_id=10156, address="575 Worcester Rd", zipcode='01701', town='Framingham', state='Massachusetts'))

    count = 1
    for t in categories:
        tags[t] = count
        count+=1
        toAdd.append(Tag(name=t))
    for t in diet_types:
        tags[t] = count
        count+=1
        toAdd.append(Tag(name=t))
    toAdd.append(Tag(name="local"))
    tags['local'] = count
    sess.add_all(toAdd)
    sess.commit()
    return sess.query(Store).all()


def whole_foods(store_id, store_code):
    slugs = []
    for category in wf_categories:
        offset = 0
        limit = 60
        url = f"https://www.wholefoodsmarket.com/api/products/category/{category}?leafCategory={category}&store={store_code}&limit=60&offset="
        raw_products = []
        while True:
            try:
                req = Request(url+str(offset))
                req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36')
                response = urlopen(req)
                results = json.loads(response.read())['results']
            except Exception as e:
                print(e)
                break
            if results == []:
                if len(raw_products) == 0:
                    pass #todo log something went wrong here
                break
            for i in results:
                if i['slug'] not in slugs:
                    slugs.append(i['slug'])
                    raw_products.append(i)
            print(offset)
            offset += limit
        for raw in raw_products:
            size = "N/A"
            n = raw['name'].lower()
            for i in [ "fl oz", "lb", "oz"," gram ","ml", "pound"]:
                if i in n:
                    unitIndex = max(0,n.find(i)-4)
                    aroundUnit = n[unitIndex:unitIndex+len(i)+4]
                    num = re.findall(r"(\d+(\.\d+)?)|(\.\d+)", aroundUnit)
                    if num == [] or num[0][0] == "":
                        break
                    size = f"{num[0][0]} {i}"
                    raw['name'] = "".join(raw['name'].split(size))
                    l = raw['name'].split(",")
                    if len(l) > 1:
                        del l[-1]
                        raw['name'] = "".join(l)

                    if len(raw['name']) < 4:
                        raw['name'] = n
                    break
            if raw['name'][0:1] == "PB" and raw['brand'] == "Renpure":
                size = raw['name'][-5]
            raw['name'] = raw['name'].title()
            prod = sess.query(Product).filter(Product.name == raw['name']).first()
            if prod == None:
                try: 
                    raw['brand'] = raw['brand'].title()
                except:
                    raw['brand'] = "Whole Foods Market"
                try: 
                    x = raw['imageThumbnail']
                except:
                    raw['imageThumbnail'] = "https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1&ipt=21419f3cd82d823842c0297318a102a87ac9b6b801dd2417cc5661c32591fbc4&ipo=images"
                prod = Product(
                    company_id = 1,
                    name = raw['name'],
                    brand = raw['brand'],
                    picture_url = raw['imageThumbnail'],
                    tags = []
                )
                emailer_info["products"].append(prod)
                sess.add(prod)
                sess.flush()
                for i in diet_types:
                    if i in n:
                        sess.add(Tag_Instance(
                            product_id = prod.id,
                            tag_id = tags[i]
                        ))
                if raw['isLocal']:
                    t = Tag_Instance(
                        product_id = prod.id,
                        tag_id = tags['local']
                    )
                    sess.add(t)
                sess.add(Tag_Instance(
                    product_id = prod.id,
                    tag_id = tags[categories[wf_categories.index(category)]]
                ))
            inst = sess.query(Product_Instance).filter(Product_Instance.store_id == store_id, Product_Instance.product_id == prod.id).first()
            if inst == None:
                inst = Product_Instance(
                    store_id = store_id,
                    product_id = prod.id
                )
                emailer_info["product_instances"].append(inst)
                sess.add(inst)
                sess.flush()
            try:
                x = raw['salePrice']
            except:
                raw['salePrice'] = None
            try:
                x = raw['incrementalSalePrice']
            except:
                raw['incrementalSalePrice'] = None
            pricepoint = PricePoint(
                base_price = raw['regularPrice'],
                sale_price = raw['salePrice'],
                member_price = raw['incrementalSalePrice'],
                size = size,
                instance_id = inst.id)
            emailer_info["price_points"].append(pricepoint)
            sess.add(pricepoint)
        sess.commit()

def trader_joes(store_id, store_code):
    url = "https://www.traderjoes.com/api/graphql"
    main_body = {
        "operationName": "SearchProducts",
        "query": "query SearchProducts($categoryId: String, $currentPage: Int, $pageSize: Int, $characteristics: [String], $storeCode: String = \""+str(store_code)+"\", $availability: String = \"1\", $published: String = \"1\") {\n  products(\n    filter: {store_code: {eq: $storeCode}, published: {eq: $published}, availability: {match: $availability}, category_id: {eq: $categoryId}, item_characteristics: {in: $characteristics}}\n    sort: {popularity: DESC}\n    currentPage: $currentPage\n    pageSize: $pageSize\n  ) {\n    items {\n      sku\n      item_title\n      category_hierarchy {\n        id\n        name\n        __typename\n      }\n      primary_image\n      primary_image_meta {\n        url\n        metadata\n        __typename\n      }\n      sales_size\n      sales_uom_description\n      price_range {\n        minimum_price {\n          final_price {\n            currency\n            value\n            __typename\n          }\n          __typename\n        }\n        __typename\n      }\n      retail_price\n      fun_tags\n      item_characteristics\n      __typename\n    }\n    total_count\n    pageInfo: page_info {\n      currentPage: current_page\n      totalPages: total_pages\n      __typename\n    }\n    aggregations {\n      attribute_code\n      label\n      count\n      options {\n        label\n        value\n        count\n        __typename\n      }\n      __typename\n    }\n    __typename\n  }\n}\n",
        "variables": {
            "availability": "1",
            "categoryId": 8,
            "characteristics": [],
            "currentPage": 0,
            "pageSize": 100,
            "published": "1",
            "storeCode": str(store_code)
        }
    }
    json_bytes = json.dumps(main_body).encode('utf-8')
    raw_products = []
    while True:
        try:
            req = Request(url, json_bytes, headers)
            response = urlopen(req)
            results = json.loads(response.read())['data']['products']['items']
        except:
            break
        if results == []:
            break
        for i in results:
            raw_products.append(i)
        print(f"{main_body['variables']['currentPage']} : {len(results)}")
        main_body['variables']['currentPage'] += 1
        json_bytes = json.dumps(main_body).encode('utf-8')
    for raw in raw_products:
        name = raw['item_title']
        p = sess.query(Product).filter(Product.name == name, Product.company_id == 2).first()
        if p == None:
            p = Product(
                brand = "Trader Joes",
                name = name,
                company_id = 2,
                picture_url = f"traderjoes.com{raw['primary_image']}",
            )
            emailer_info["products"].append(p)
            sess.add(p)
            sess.flush()
            t = []
            if raw['item_characteristics'] != None:
                for i in raw['item_characteristics']:
                    if i.lower() in tags.keys():
                        t.append(Tag_Instance(
                            product_id = p.id,
                            tag_id = tags[i.lower()]
                        ))
            ch = raw['category_hierarchy'][2]['name']
            for index, category in enumerate(tj_categories):
                if len(category) < 5:
                    for c in category:
                        if ch == c:
                            t.append(Tag_Instance(
                                product_id = p.id,
                                tag_id = tags[categories[index]]
                            ))
                else:
                    if ch == category:
                        t.append(Tag_Instance(
                            product_id = p.id,
                            tag_id = tags[categories[index]]
                        ))
            sess.add_all(t)
        inst = sess.query(Product_Instance).filter(Product_Instance.store_id == store_id, Product_Instance.product_id == p.id).first()
        if inst == None:
            inst = Product_Instance(
                store_id = store_id,
                product_id = p.id
            )
            emailer_info["product_instances"].append(inst)
            sess.add(inst)
            sess.flush()
        pricepoint = PricePoint(
            base_price = raw['retail_price'],
            sale_price = None,
            member_price = None,
            size = f"{raw['sales_size']} {raw['sales_uom_description']}",
            instance_id = inst.id
        )
        emailer_info["price_points"].append(pricepoint)
        sess.add(pricepoint)
    sess.commit()


def get_joes_store(stores,searchterm):
    url = "https://alphaapi.brandify.com/rest/locatorsearch"
    body = {
        "request": {
            "appkey": "8BC3433A-60FC-11E3-991D-B2EE0C70A832",
            "formdata": {
            "geoip": false,
            "dataview": "store_default",
            "limit": 1,
            "geolocs": {
                "geoloc": [
                {
                    "addressline": searchterm,
                    "country": "US",
                    "latitude": "",
                    "longitude": ""
                }
                ]
            },
            "searchradius": "500",
            "where": {
                "warehouse": {
                "distinctfrom": "1"
                }
            },
            "false": "0"
            }
        }
        }
    json_bytes = json.dumps(body).encode('utf-8')
    req = Request(url, json_bytes, headers)
    response = urlopen(req)
    results = json.loads(response.read())['collection'][0]
    store = Store(
        company_id = 2,
        scraper_id = results['clientkey'],
        address = results['address1'],
        state = results['state'],
        town = results['town'],
        zipcode = results['postalcode']
    )
    for s in stores:
        if s.scraper_id == store.scraper_id:
            return 0
    sess.add(store)
    sess.commit()
    return 1

def store_filter(company_id):
    def x(store):
        return store.company_id == company_id
    return x
    
def get_all_wf(stores):
    for i in stores:
        whole_foods(i.id, i.scraper_id)

def get_all_tj(stores):
    for i in stores:
        trader_joes(i.id, i.scraper_id)


def get_any(stores):
    wf_stores = filter(store_filter(1),stores)
    tj_stores = filter(store_filter(2),stores)
    wf_thread = threading.Thread(target=get_all_wf,args=([wf_stores]))
    tj_thread = threading.Thread(target=get_all_tj,args=([tj_stores]))
    wf_thread.start()
    tj_thread.start()
    wf_thread.join()
    tj_thread.join()


@schedule.repeat(schedule.every().day.at("10:30"))
def scheduled_job():
    emailer_info = blank_emailer_info.copy()
    print(f"SCRAPING - {datetime.now()}")
    start = datetime.now()
    stores = sess.query(Store).all()
    if stores == []:
        stores = setup()
    else:
        for t in sess.query(Tag).all():
            tags[t.name] = t.id
    emailer_info["stores"] = stores
    emailer_info["companies"] = sess.query(Company).all()
    get_any(stores)
    message = f"""\
GS Scraper Daily Test Run

Session ID: {sess_id}
Session Start: {sess_start_time.strftime("%A, %d. %B %Y %I:%M%p %Ss")}

Started at: {start.strftime("%A, %d. %B %Y %I:%M%p %Ss")}
Ended at: {datetime.now().strftime("%A, %d. %B %Y %I:%M%p %Ss")}

Num Stores Scraped: {len(stores)}
Num New Products: {len(emailer_info["products"])}
Num New Product Instances: {len(emailer_info["product_instances"])}
Num New Price Points: {len(emailer_info["price_points"])}

New Products:
""" 
    for p in emailer_info["products"]:
        message += f"\n{p.name} | {p.brand} | {p.company_id}" 
    emailer.simple_send(message)
    emailer.send(emailer_info)

def user_newsletter():
    pass
if len(sys.argv) != 1 and (sys.argv[1] == "debug" or sys.argv[1] == "d"):
    debug=True
else:
    debug=False
if __name__ == "__main__":
    print("starting")
#     message = f"""\
# Subject: GS Scraper (Starting) - {datetime.now().strftime("%A, %d. %B %Y %I:%M%p")}

# :)"""
#     emailer.simple_send(message)

    # If debug, run immediately. Otherwise, run according to schedule.
    if debug:
        scheduled_job()
    else:
        while True:
            schedule.run_pending()
            time.sleep(1)
