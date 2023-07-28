from sqlalchemy import create_engine, MetaData
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from sqlalchemy import Column, Integer, DateTime

Base = declarative_base()

#TODO: move to api 
engine = create_engine('sqlite:///app.db?check_same_thread=False', echo=True)

class BaseModel:
    id = Column(Integer, primary_key=True)