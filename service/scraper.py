from bs4 import BeautifulSoup 
# from selenium.webdriver.firefox.options import Options
# from selenium import webdriver
# from selenium.webdriver.common.by import By
import time
from datetime import datetime
from models.base import Base, engine
from sqlalchemy.orm import Session
from models import Product, Product_Instance, PricePoint, Store, Tag, Tag_Instance, Company
import sys
import time
from concurrent.futures import ThreadPoolExecutor, wait, as_completed

sess = Session(engine)


headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36'}

import os
from urllib.request import Request, urlopen
import json
import ast
doing_it_with_selenium = False

# add in batches. all products, then instances, then pricepoints? 
categories = ["produce","dairy-eggs","meat","prepared-foods","pantry-essentials","breads-rolls-bakery","desserts","frozen-foods","snacks-chips-salsas-dips","seafood","beverages"]
diet_types = ["organic", "vegan", "kosher", "gluten free", "dairy free", "vegetarian"]
tags = {}

def setup():
    wf = Company(logo_url=None, name="Whole Foods")
    joes = Company(logo_url=None, name="Trader Joes")
    test_wf = Store(company_id=1, scraper_id=10413, address=None, zipcode='02482')
    test_joes = Store(company_id=2, scraper_id=509, address=None, zipcode='02482')
    count = 1
    for t in categories:
        tags[t] = count
        count+=1
        sess.add(Tag(name=t))
    for t in diet_types:
        tags[t] = count
        count+=1
        sess.add(Tag(name=t))
    sess.add(Tag(name="local"))
    tags['local'] = count
    sess.add_all([wf,test_wf,joes,test_joes])
    sess.commit()
    return sess.query(Store).all()

def whole_foods(store_id, store_code):
    names = []
    for category in categories:
        offset = 0
        limit = 60
        url = f"https://www.wholefoodsmarket.com/api/products/category/[leafCategory]?leafCategory={category}&store={store_code}&limit=60&offset="
        raw_products = []
        while True:
            try:
                req = Request(url+str(offset))
                req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36')
                response = urlopen(req)
                results = json.loads(response.read())['results']
            except:
                break
            if results == []:
                break
            for i in results:
                if i['name'] in names:
                    print(f"{i['name']} is already in raw products???")
                else:
                    names.append(i['name'])
                    raw_products.append(i)
            print(offset)
            offset += limit
        for raw in raw_products:
            size = "N/A"
            # if "/" in raw['regularPrice']:
            #     size = "per " + raw['regularPrice'].split("/")[-1] # almost always lb        
            # else:
            for i in [ "fl oz", "lb", "oz"," gram ","ml"]:
                if " " + i in raw['name'] or " "+i+" " in raw['name'] or " "+i+"s " in raw['name'] or " "+i+")" in raw['name']:
                    size = raw['name'].split(",")[-1]
                    raw['name'] = raw['name'][0:len(raw['name'])-len(size)-1].strip()
                    break
            if raw['name'][0:1] == "PB" and raw['brand'] == "Renpure":
                size = raw['name'][-5]
            prod = sess.query(Product).filter(Product.name == raw['name']).first()
            if prod == None:
                try: 
                    raw['brand'] = raw['brand'].title()
                except:
                    raw['brand'] = None
                try: 
                    x = raw['imageThumbnail']
                except:
                    raw['imageThumbnail'] = None
                prod = Product(
                    company_id = 1,
                    name = raw['name'].title(),
                    brand = raw['brand'],
                    picture_url = raw['imageThumbnail'],
                    tags = []
                )
                sess.add(prod)
                sess.flush()
                if raw['isLocal']:
                    t = Tag_Instance(
                        product_id = prod.id,
                        tag_id = tags['local']
                    )
                    sess.add(t)
                sess.add(Tag_Instance(
                    product_id = prod.id,
                    tag_id = tags[category]
                ))
            inst = sess.query(Product_Instance).filter(Product_Instance.store_id == store_id, Product_Instance.product_id == prod.id).first()
            if inst == None:
                inst = Product_Instance(
                    store_id = store_id,
                    product_id = prod.id
                )
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
            sess.add(pricepoint)
        sess.commit()


h = {
    'Host': 'www.traderjoes.com',
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0',
    'Referer': 'https://www.traderjoes.com/home/products/category/food-8',
    'Origin': 'https://www.traderjoes.com',
    'Connection': 'keep-alive',
    'Cookie': 'affinity="ebb0141da8e53aa0"; AMCV_B5B4708F5F4CE8D80A495ED9%40AdobeOrg=-2121179033%7CMCIDTS%7C19567%7CMCMID%7C59202760330854573354314556646638726566%7CMCOPTOUT-1690581920s%7CNONE%7CvVersion%7C5.3.0; AMCVS_B5B4708F5F4CE8D80A495ED9%40AdobeOrg=1',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'no-cors',
    'Sec-Fetch-Site': 'same-origin',
    'DNT': 1,
    'Sec-GPC': 1,
}
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
    h['Content-Length'] = len(json_bytes)
    raw_products = []
    while True:
        try:
            req = Request(url, json_bytes, h)
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
            sess.add(p)
            sess.flush()
            t = []
            if raw['item_characteristics'] != None:
                for i in raw['item_characteristics']:
                    if i in tags.keys():
                        sess.add(Tag_Instance(
                            product_id = p.id,
                            tag_id = tags[i]
                        ))
        inst = sess.query(Product_Instance).filter(Product_Instance.store_id == store_id, Product_Instance.product_id == p.id).first()
        if inst == None:
            inst = Product_Instance(
                store_id = store_id,
                product_id = p.id
            )
            sess.add(inst)
            sess.flush()
        pricepoint = PricePoint(
            base_price = raw['retail_price'],
            sale_price = None,
            member_price = None,
            size = f"{raw['sales_size']} {raw['sales_uom_description']}",
            instance_id = inst.id
        )
        sess.add(pricepoint)
    sess.commit()
            



def get_joes_store(zipcode):
    store_search_url = "https://alphaapi.brandify.com/rest/locatorsearch"
    store_search_body = {
        "request": {
            "appkey": "8BC3433A-60FC-11E3-991D-B2EE0C70A832",
            "formdata": {
            "geoip": false,
            "dataview": "store_default",
            "limit": 4,
            "geolocs": {
                "geoloc": [
                {
                    "addressline": "02481",
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

stores = sess.query(Store).all()
if stores == []:
    stores = setup()
for store in stores:
    if store.company_id == 1:
        whole_foods(store.id, store.scraper_id)
    elif store.company_id == 2:
        trader_joes(store.id, store.scraper_id)




if doing_it_with_selenium: 
    options = Options()
    options.headless = True #should be true for server

    try:
        debug_mode=bool(int(sys.argv[1]))
    except:
        debug_mode = False
    else:
        print("DEBUG MODE ACTIVE")
    def log(msg):
        if debug_mode:
            print(f"###LOG###\n{msg}\n#########")

    def update_stores(stores):
        for store in stores:
            if store.company == "Whole Foods":
                get_whole_foods(store)
            elif store.company == "Trader Joes":
                get_trader_joes(store)
            log(f"{store.company} from zipcode {store.zipcode} updated at {datetime.now()}")

    def get_store(zipcode,brand):
        store = sess.query(Store).filter(Store.zipcode == zipcode, Store.company == company).first()
        if not store:
            store = Store( 
                brand=brand,
                address="TODO",
                zipcode=zipcode)
            sess.add(store)
            sess.commit()
            sess.refresh(store)
        return store

    def get_location(zipcode):
        print(f"Getting Location {zipcode}")
        stores = []
        for brand in ["Whole Foods","Trader Joes"]:
            stores.append(get_store(zipcode,brand))
        update_stores(stores)



    HADLEY_ZIP_CODE =  '01035'
    WORKERS = 4
    # WHOLE FOODS 
    # TODO Get product size (and maybe other metadata?) by nutritional info text
    def get_whole_foods(store):
        sid,zipcode = store.id,store.zipcode

        entranceURL = "https://www.wholefoodsmarket.com/products/products/"
        
        findmoreXPATH="/html/body/div[1]/main/div[2]/div[5]/div[3]/button"
        clickerXPATH="/html/body/div[1]/main/div[2]/div[6]/div/div/div/section/div/wfm-search-bar/div[2]/div/ul/li[1]"
        rawProducts = []
        allProductsXPATH = "/html/body/div/main/div[2]/div[5]/div[1]/aside/nav/div[1]/div/ul/li[1]/span/button"
        

        def get_category(category):
            log(f"{category} is beginning browser")
            b = webdriver.Firefox(options=options)
            b.implicitly_wait(10)
            try:
                b.get(entranceURL+category)
                storebox = b.find_element(By.ID,"pie-store-finder-modal-search-field")
                storebox.send_keys(zipcode)
                time.sleep(2)
                b.find_element(By.XPATH,clickerXPATH).click()
            except:
                b.refresh()
                b.get(entranceURL+category)
                storebox = b.find_element(By.ID,"pie-store-finder-modal-search-field")
                storebox.send_keys(zipcode)
                time.sleep(2)
                b.find_element(By.XPATH,clickerXPATH).click()

            log(f"{category} is beginning search")
            while True:
                try:
                    b.find_element(By.XPATH,findmoreXPATH).click()
                except:
                    break
            time.sleep(2)

            html = b.page_source
            b.quit()
            return BeautifulSoup(html, 'html.parser').find_all(class_="w-pie--product-tile")
        rawProducts = []
        categories = ["produce","dairy-eggs","meat","prepared-foods","pantry-essentials","breads-rolls-bakery","desserts","frozen-foods","snacks-chips-salsas-dips","seafood","beverages"]
        with ThreadPoolExecutor(max_workers=WORKERS) as executor:
            future_to_data = {executor.submit(get_category, category): category for category in categories}
            for future in as_completed(future_to_data):
                category = future_to_data[future]

                try:
                    data = future.result()
                except Exception as exc:
                    print('%r generated an exception: %s' % (category, exc))
                else:
                    rawProducts += data
                    print(f"{category} worked!")
        products = []
        for p in rawProducts:
            d = {}

            price = p.find(class_="w-pie--prices")
            if price == None:
                print(p)
            else:
                print("this one worked")
            d["name"] = p.find(class_="w-cms--font-body__sans-bold").text
            brand = p.find_all(class_="w-cms--font-disclaimer")
            if len(brand) < 2:
                d['brand'] = "N/A"
            else:
                d['brand'] = brand[1].text
            
            origprice = price.find(class_="regular_price")
            if origprice == None:
                d["origprice"] = "N/A"
            else:
                d["origprice"] = origprice.text
            
            saleprice = price.find(class_="sale_price")
            if saleprice == None:
                d["saleprice"] = "N/A"
            else:
                d["saleprice"] = saleprice.text[10:]
                
            primeprice = price.find(class_="prime_price prime_incremental")
            if primeprice == None:
                d["primeprice"] = "N/A"
            else:
                d["primeprice"] = primeprice.text[18:]

            img = p.find("img")
            if img == None:
                img = p.find(class_=" ls-is-cached lazyloaded")
            if img == None:
                d["img"] = ""
            else:
                d["img"] = img["src"] 

            products.append(d)
            print(d)
        for product in products:
            print(f"Adding product #{products.index(product)+1}/{len(products)}")
            
            size = "N/A"
            if "/" in product['origprice']:
                size = "per " + product['origprice'].split("/")[-1] # almost always lb        
            else:
                for i in ["lb", "oz"," gram ","ml"]:
                    if " " + i in product['name'] or " "+i+" " in product['name'] or " "+i+"s " in product['name'] or " "+i+")" in product['name']:
                        size = product['name'].split(",")[-1]
                        product['name'] = product['name'][0:len(product['name'])-len(size)-2]
                        break
            if product['name'][0:1] == "PB" and product['brand'] == "Renpure":
                size = product['name'][-5]
            p = sess.query(Product).filter(Product.store_id == sid, Product.name == product['name'], Product.brand == product['brand']).first()
            if p != None:
                print(f"Existing product with name = \"{product['name']}\" found")
                
                if p.last_updated.date() != datetime.now().date():
                    p.last_updated = datetime.now()
                    p.base_price = product['origprice']
                    p.sale_price = product['saleprice']
                    p.member_price = product['primeprice']
                    p.size = size

                    pricePoint = PricePoint(
                        base_price = p.base_price,
                        sale_price = p.sale_price,
                        member_price = p.member_price,
                        size = p.size,
                        timestamp = p.last_updated,
                        product_id = p.id
                    )
                    sess.add(pricePoint)

                    sess.merge(p)
                    sess.commit()
            else:
                sess.add(Product(
                    name = product['name'],
                    brand = product['brand'],
                    size = size,
                    base_price = product['origprice'],
                    sale_price = product['saleprice'],
                    member_price = product['primeprice'],
                    picture_url = product['img'],
                    store_id = sid,
                ))
                sess.commit()
        store.last_updated = datetime.now()
        sess.merge(store)
        sess.commit()
        if __name__ != "__main__":
            browser.close()


    # just use selenium for picking location, then beautifulsoup each page
    def get_trader_joes_2(store):
        sid,zipcode = store.id,store.zipcode
        myStoreButton = "/html/body/div/div[1]/div[1]/div[2]/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div[2]/a"
        searchStoreArea = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[1]/input"
        searchButton = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[2]/div/button"
        setStoreButton = "/html/body/div/div[1]/div[1]/div[2]/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[2]/div/div[1]/div[2]/button"
        xX = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[2]/button"
        
        startPoint = 'https://www.traderjoes.com/home/products/category/food-8'
        browser.get(startPoint)
        # setting current store to closest from zip code requested
        browser.find_element(By.XPATH,myStoreButton).click()
        browser.find_element(By.XPATH,searchStoreArea).send_keys(zipcode)
        browser.find_element(By.XPATH,searchButton).click()
        browser.find_element(By.XPATH,setStoreButton).click()
        browser.find_element(By.XPATH,xX).click()
        
        num = 0
        try:
            while True:
                num += 1
                r = requests.get(f"https://www.traderjoes.com/home/products/category/food-8?filters=%7B%22page%22%3A{num}%7D", timeout=5)
                r.raise_for_status()
                print(r.text)

                if ("Food" not in r.text):
                    break
        except:
            pass
        

    # TRADER JOES
    def get_trader_joes(store):
        browser = webdriver.Firefox(options=options)
        browser.implicitly_wait(10)
        sid,zipcode = store.id,store.zipcode
        startPoint = 'https://www.traderjoes.com/home/products/category/food-8'
        myStoreButton = "/html/body/div/div[1]/div[1]/div[2]/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div[2]/a"
        searchStoreArea = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[1]/input"
        searchButton = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[2]/div/button"
        setStoreButton = "/html/body/div/div[1]/div[1]/div[2]/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[2]/div/div[1]/div[2]/button"
        xX = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[2]/button"
        xPathArrow = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[2]/main/div/div/div/div[1]/div/div/div[1]/div[2]/section/div/button[2]"
        xPathProducts = "/html/body/div[1]/div[1]/div[1]/div/div[1]/div/div[2]/main/div/div/div/div[1]/div/div/div[1]/div[2]/section/ul"
        browser.get(startPoint)

        # setting current store to closest from zip code requested
        browser.find_element(By.XPATH,myStoreButton).click()
        browser.find_element(By.XPATH,searchStoreArea).send_keys(zipcode)
        browser.find_element(By.XPATH,searchButton).click()
        browser.find_element(By.XPATH,setStoreButton).click()
        browser.find_element(By.XPATH,xX).click()

        #accepting cookies since it blocks the arrow
        try:
            browser.find_element(By.XPATH,"/html/body/div/div[1]/div[1]/div[1]/div/button").click()
        except:
            pass
        pages = []
        breaks = 0
        while breaks < 3:
            try:
                browser.find_element(By.XPATH,xPathArrow).click()
                pages.append(browser.find_element(By.XPATH,xPathProducts).get_attribute('innerHTML'))
            except:
                breaks += 1
        
        products = []
        for page in pages:
            soup = BeautifulSoup(page,'html.parser')
            rawProducts = soup.find_all(class_="ProductList_productList__item__1EIvq")
            # overflow = ""
            for p in rawProducts:
                d = {}
                
                img = "traderjoes.com" + p.find("img")["src"]

                price = p.find(class_="ProductPrice_productPrice__wrapper__20hep").text.replace('\n','')
                price,size = price.split("/")
                # if overflow == "":
                #     d["name"] = p.find(class_="ProductCard_card__title__text__uiWLe").text.replace('\n','')
                # else:
                #     d["name"] = overflow + p.find(class_="ProductCard_card__title__text__uiWLe").text.replace('\n','')
                #     overflow = ""
                name = p.find(class_="ProductCard_card__title__text__uiWLe").text.replace('\n','')
                brand = p.find(class_="ProductCard_card__category__Hh3rT").text.replace('\n','')
                # if price == "":
                #     overflow = d["name"]
                #     continue

                p = sess.query(Product).filter(Product.store_id == sid, Product.name == name, Product.brand == brand).first()
                if p:
                    print(f"Existing product with name = \"{name}\" found")
                
                    if p.last_updated.date() != datetime.now().date():
                        pricePoint = PricePoint(
                            base_price = p.base_price,
                            sale_price = p.sale_price,
                            member_price = p.member_price,
                            size = p.size,
                            timestamp = p.last_updated,
                            product_id = p.id)
                        p.last_updated = datetime.now()
                        p.base_price = price
                        p.size = size
                        sess.add(pricePoint)
                        sess.merge(p)
                        sess.commit()
                else:
                    sess.add(Product(
                        name = name,
                        brand = brand,
                        size = size,
                        base_price = price,
                        sale_price = "N/A",
                        member_price = "N/A",
                        picture_url = img,
                        store_id = sid,
                    ))
                    sess.commit()
        store.last_updated = datetime.now()
        sess.merge(store)
        sess.commit()
        browser.close()

    if __name__ == "__main__":
        update_stores(stores = sess.query(Store).all())