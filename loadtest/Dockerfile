FROM python:3.10-slim

WORKDIR /app

COPY loadtest/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt || true

COPY loadtest/ /app/

CMD ["python", "-m", "http.server", "8080"]
