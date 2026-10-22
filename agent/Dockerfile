FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends pandoc && apt-get clean
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY common.py engine.py server.py ./
RUN useradd -m app && mkdir /data && chown app:app /data
USER app
ENV DATA_DIR=/data
CMD ["uvicorn","server:app","--host","0.0.0.0","--port","8000","--workers","1"]
