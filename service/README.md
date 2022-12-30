# Backend
Data is served over [FastAPI](https://fastapi.tiangolo.com/), an ASGI framework for fast REST APIs in Python.

## Installation
We're currently using `requirements.txt` for saving and locking our dependencies.

```bash
pip install -r requirements.txt
```

## Local Development
To run the FastAPI app locally, run
```bash
uvicorn main:app
```
You may pass the `--reload` flag if you want refresh synced with the source.

The API docs are accesible at `/docs`.
