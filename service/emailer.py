import smtplib, ssl
from dotenv import load_dotenv

load_dotenv()

port = 465
password = os.gotenv("password")
sender_email = os.gotenv("username")
receiver_email = "lancegruber2@gmail.com"
default_message = """\
Subject: Testing!

Cool!!"""
def send(message):
    if message == None:
        message = default_message
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL("smtp.gmail.com",port,context=context) as server:
        server.login(sender_email,password)
        server.sendmail(sender_email, receiver_email, message)

