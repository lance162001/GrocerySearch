from bs4 import BeautifulSoup 
from selenium.webdriver.firefox.options import Options
from selenium import webdriver
from selenium.webdriver.common.by import By
import time
import re
from datetime import datetime


from models.base import Base, engine
from sqlalchemy.orm import Session
from models import Product, PricePoint, Store

sess = Session(engine)

options = Options()
options.headless = False #should be true for server


browser = webdriver.Firefox(options=options)

def get_store(zipcode,company):
    store = sess.query(Store).filter(Store.zipcode == zipcode, Store.company == company).first()
    if store:
        sid = store.id
    else:
        store = Store( 
            company=company,
            address="TODO",
            zipcode=zipcode)
        sess.add(store)
        sess.commit()
        sess.refresh(store)
        sid = store.id
    return sid,store

HADLEY_ZIP_CODE =  '01035'
# WHOLE FOODS 
# TODO Get product size (and maybe other metadata?) by nutritional info text
def get_whole_foods(zipcode):
    
    sid,store = get_store(zipcode,"Whole Foods")

    entranceURL = "https://www.wholefoodsmarket.com/products/all-products?featured=on-sale"
    browser.get(entranceURL)
    time.sleep(3)

    try: 
        storebox = browser.find_element(By.ID,"pie-store-finder-modal-search-field")
    except:
        browser.get(entranceURL)
        time.sleep(2)
        storebox = browser.find_element(By.ID,"pie-store-finder-modal-search-field")
    storebox.send_keys(zipcode)

    time.sleep(3)

    clickerXPATH="/html/body/div[1]/main/div[2]/div[6]/div/div/div/section/div/wfm-search-bar/div[2]/div/ul/li"
    browser.find_element(By.XPATH,clickerXPATH).click()
    time.sleep(3)

    findmoreXPATH="/html/body/div[1]/main/div[2]/div[5]/div[3]/button"

    while True:
        try:
            browser.find_element(By.XPATH,findmoreXPATH).click()
            time.sleep(1)
        except:
            break

    html = browser.page_source
    soup = BeautifulSoup(html, 'html.parser')

    rawProducts = soup.find_all(class_="w-pie--product-tile")
    products = []
    for p in rawProducts:
        d = {}

        price = p.find(class_="w-pie--prices")
        d["name"] = p.find(class_="w-cms--font-body__sans-bold").text
        brand = p.find_all(class_="w-cms--font-disclaimer")
        if len(brand) == 1:
            d['brand'] = "N/A"
        else:
            d['brand'] = brand[1].text

        
        origprice = price.find(class_="regular_price")
        if origprice == None:
            d["origprice"] = "N/A"
        else:
            d["origprice"] = origprice.text
        
        saleprice = price.find(class_="sale_price")
        if saleprice != None:
            d["saleprice"] = saleprice.text[10:]
        else:
            d["saleprice"] = "N/A"
        primeprice = price.find(class_="prime_price prime_incremental")
        if primeprice != None:
            d["primeprice"] = primeprice.text[18:]
        else:
            d["primeprice"] = "N/A"

        img = p.find("img")
        if img == None:
            img = p.find(class_=" ls-is-cached lazyloaded")
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
                     break
        if product['name'][0:1] == "PB" and product['brand'] == "Renpure":
            size = product['name'][-5]
        p = sess.query(Product).filter(Product.name == product['name'], Product.brand == product['brand']).first()
        if p != None:
            print(f"Existing product with name = \"{product['name']}\" found")
            
            if not (p.base_price == product['origprice'] and p.sale_price == product['saleprice'] and p.member_price == product['primeprice'] ):
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
                print(f"Existing product with name = \"{product['name']}\" has same prices, ignoring")

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
# TRADER JOES
def get_trader_joes(zipcode):
    sid,store = get_store(zipcode,"Trader Joes")
    startPoint = 'https://www.traderjoes.com/home/products/category/food-8'

    myStoreButton = "/html/body/div/div[1]/div[1]/div[2]/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div[2]/a"
    searchStoreArea = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[1]/input"
    searchButton = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[1]/div[2]/div/button"
    setStoreButton = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[1]/div[1]/div/header/div[1]/div[1]/div[1]/div/div[1]/div/div[1]/form/div[2]/div/div[1]/div[2]/button"



    xPathArrow = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[2]/main/div/div/div/div[1]/div/div/div[1]/div[2]/section/div/button[2]"
    xPathProducts = "/html/body/div[1]/div[1]/div[1]/div/div[1]/div/div[2]/main/div/div/div/div[1]/div/div/div[1]/div[2]/section/ul"
    browser.get(startPoint)
    time.sleep(4)

    # setting current store to closest from zip code requested
    browser.find_element(By.XPATH,myStoreButton).click
    browser.find_element(By.XPATH,myStoreButton).click

    print("clicked!")
    time.sleep(10)
    browser.find_element(By.XPATH,searchStoreArea).send_keys(zipcode)
    browser.find_element(By.XPATH,searchButton).click()
    browser.find_element(By.XPATH,setStoreButton).click()
    
    #accepting cookies since it blocks the arrow
    try:
        browser.find_element(By.XPATH,"/html/body/div/div[1]/div[1]/div[1]/div/button").click()
    except:
        pass
    more=0
    pages = []
    while more < 3:
        try:
            browser.find_element(By.XPATH,xPathArrow).click()
        except Exception as e:
            print (e)
            more += 1
        else:
            more = 0
            time.sleep(2)
            pages.append(browser.find_element(By.XPATH,xPathProducts).get_attribute('innerHTML'))
    
    products = []
    for page in pages:
        soup = BeautifulSoup(page,'html.parser')
        rawProducts = soup.find_all(class_="ProductList_productList__item__1EIvq")
        overflow = ""
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
                print(f"Existing product with name = \"{product['name']}\" found")
               
                if p.base_price != price or p.size != size:
                    pricePoint = PricePoint(
                        base_price = p.base_price,
                        sale_price = p.sale_price,
                        member_price = p.member_price,
                        size = p.size,
                        timestamp = p.last_updated,
                        product_id = p.id
                    )
                    p.base_price = price
                    p.size = size
                    sess.add(pricePoint)
                    sess.merge(p)
                    sess.commit()
                else:
                    print(f"Existing product with name = \"{product['name']}\" has same prices, ignoring")
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
start_time = time.time()
# get_whole_foods(HADLEY_ZIP_CODE)
whole_foods_time = time.time()
# print(f"Whole foods scraped, took {whole_foods_time-start_time} seconds")
get_trader_joes(HADLEY_ZIP_CODE)
print(f"Trader Joes Scraped, took {time.time()-whole_foods_time} seconds")
end_time = time.time()
print(f"Scraping complete, total time elapsed={end_time-start_time}")

input("-----\nenter to close\n-----\n")
browser.close()
