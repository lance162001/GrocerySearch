from bs4 import BeautifulSoup 
from selenium.webdriver.firefox.options import Options
from selenium import webdriver
from selenium.webdriver.common.by import By
import time
import re


from models.base import Base, engine
from sqlalchemy.orm import Session
from models import Product, PricePoint

sess = Session(engine)

options = Options()
options.headless = False #should be true for server


browser = webdriver.Firefox(options=options)



# WHOLE FOODS 
# !!TODO!! Get product size (and maybe other metadata?) by nutritional info text
def get_whole_foods():
    
    entranceURL = "https://www.wholefoodsmarket.com/products/all-products?featured=on-sale"
    browser.get(entranceURL)
    time.sleep(3)

    try: 
        hadleybox = browser.find_element(By.ID,"pie-store-finder-modal-search-field")
    except:
        browser.get(entranceURL)
        time.sleep(2)
        hadleybox = browser.find_element(By.ID,"pie-store-finder-modal-search-field")
    hadleybox.send_keys("Hadley")

    time.sleep(3)

    clickerXPATH="/html/body/div[1]/main/div[2]/div[6]/div/div/div/section/div/wfm-search-bar/div[2]/div/ul/li"
    browser.find_element(By.XPATH,clickerXPATH).click()
    time.sleep(3)

    findmoreXPATH="/html/body/div[1]/main/div[2]/div[5]/div[3]/button"

    more=True
    while more:
        try:
            browser.find_element(By.XPATH,findmoreXPATH).click()
            time.sleep(1)
        except:
            more=False

    time.sleep(3)
    html = browser.page_source
    soup = BeautifulSoup(html, 'html.parser')

    rawProducts = soup.find_all(class_="w-pie--product-tile")
    products = []
    for p in rawProducts:
        d = {}

        price = p.find(class_="w-pie--prices")
        d["name"] = p.find(class_="w-cms--font-body__sans-bold").text
        d['brand'] = p.find(class_="w-cms--font-disclaimer").text
        print(f"###BRAND#### {d['brand']}")

        
        origprice = price.find(class_="regular_price has_sale")
        if origprice == None:
            continue
        else:
            d["origprice"] = origprice.text
        
        saleprice = price.find(class_="sale_price")
        if saleprice != None:
            d["saleprice"] = saleprice.text[10:]
        else:
            d["saleprice"] = "N/A"
        primeprice = price.find(class_="prime_price prime_incremental")
        if primeprice != None:
            d["primeprice"]=primeprice.text[18:]
        else:
            d["primeprice"] = "N/A"
        img = p.find("img")
        if img == None:
            img = p.find(class_=" ls-is-cached lazyloaded")
        d["img"] = img["src"]


        products.append(d)
        print(d)
    f=open("WholeScraped.txt","w+")
    for product in products:
        print(f"Adding product #{products.index(product)+1}/{len(products)}")
        s =  f"{product['name']} | {product['origprice']} | {product['saleprice']} | {product['primeprice']} | {product['img']}\n"
        f.write(s)
        size = "N/A"
        if "/" in product['origprice']:
            size = "per "+product['origprice'].split("/")[1]
        else:
            for i in ["lb","oz","gram"]:
                if i in product['name'] and "," in product['name']:
                    size = product['name'].split(",")[-1]
                    break
        p = sess.query(Product).filter(Product.name == product['name'], Product.brand == product['brand']).first()
        if p != None:
            print(f"Existing product with name = \"{product['name']}\" found")
            pricePoint = PricePoint(
                base_price = p.base_price,
                sale_price = p.sale_price,
                member_price = p.member_price,
                size = p.size,
                timestamp = p.last_updated
            )
            if not (p.base_price == product['origprice'] and p.sale_price == product['saleprice'] and p.member_price == product['primeprice'] ):
                p.price_history.append(pricePoint)
                p.base_price = product['origprice']
                p.sale_price = product['saleprice']
                p.member_price = product['primeprice']
                p.size = size
                p.active = True
                sess.merge(p)
                sess.commit()
            else:
                print(f"Existing product with name = \"{product['name']}\" has same prices, ignoring")

        else:
            newP = Product(
                name = product['name'],
                brand = product['brand'],
                size = size,
                base_price = product['origprice'],
                sale_price = product['saleprice'],
                member_price = product['primeprice'],
                picture_url = product['img'],
                store_id = 0,
                active = True,
            )
            sess.add(newP)
            sess.commit()
    f.close()


# TRADER JOES
def get_trader_joes():
    startPoint = 'https://www.traderjoes.com/home/products/category/food-8'
    xPathArrow = "/html/body/div/div[1]/div[1]/div/div[1]/div/div[2]/main/div/div/div/div[1]/div/div/div[1]/div[2]/section/div/button[2]"
    xPathProducts = "/html/body/div[1]/div[1]/div[1]/div/div[1]/div/div[2]/main/div/div/div/div[1]/div/div/div[1]/div[2]/section/ul"
    browser.get(startPoint)
    time.sleep(4)
    
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
    
    f=open("TraderScraped.txt","w+")
    products = []
    for page in pages:
        soup = BeautifulSoup(page,'html.parser')
        rawProducts = soup.find_all(class_="ProductList_productList__item__1EIvq")
        overflow = ""
        for p in rawProducts:
            d = {}
            
            d["img"] = "traderjoes.com" + p.find("img")["src"]

            d["price"] = p.find(class_="ProductPrice_productPrice__wrapper__20hep").text.replace('\n','')
            if overflow == "":
                d["name"] = p.find(class_="ProductCard_card__title__text__uiWLe").text.replace('\n','')
            else:
                d["name"] = overflow + p.find(class_="ProductCard_card__title__text__uiWLe").text.replace('\n','')
                overflow = ""

            if d["price"] == "":
                overflow = d["name"]
                continue
            
            products.append(d)

            s = f"{d['name']} | {d['price']} | {d['img']}\n"

            f.write(s)
            sess.add(Product(
                name = product['name'],
                base_price = product['price'],
                sale_price = product['price'],
                member_price = product['price'],
                picture_url = product['img'],
                store_id = 1
            ))
    sess.commit()
    f.close()

start_time = time.time()
get_whole_foods()
whole_foods_time = time.time()
print(f"Whole foods scraped, took {whole_foods_time-start_time} seconds")
get_trader_joes()
print(f"Whole foods scraped, took {time.time()-whole_foods_time} seconds")
end_time = time.time()
print(f"Scraping complete, total time elapsed={end_time-start_time}")

input("-----\nenter to close\n-----\n")
browser.close()
