from fastapi import FastAPI
from api import router
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os


app = FastAPI()

origins = ["*"]

app.add_middleware(CORSMiddleware, 
                  allow_origins=origins,
                  allow_credentials=True,
                  allow_methods=["*"],
                  allow_headers=["*"])

# Mount static files (e.g., logos saved to service/static/logos)
static_dir = os.path.join(os.path.dirname(__file__), 'static')
os.makedirs(static_dir, exist_ok=True)
app.mount('/static', StaticFiles(directory=static_dir), name='static')

app.include_router(router)
