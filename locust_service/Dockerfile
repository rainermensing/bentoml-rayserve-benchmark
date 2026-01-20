FROM python:3.11-slim

WORKDIR /app

COPY locust_service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt || true

COPY locust_service/ /app/

CMD ["python", "-m", "http.server", "8080"]
