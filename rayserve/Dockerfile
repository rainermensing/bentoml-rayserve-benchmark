FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install
COPY rayserve/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy model assets
COPY model/mobilenet_v2.keras /app/model/
COPY model/imagenet_labels.txt /app/

# Copy application code and prebuilt serve config
COPY rayserve/app.py .
COPY rayserve/serve_config.yaml .

ENV MODEL_PATH=/app/model/mobilenet_v2.keras
ENV LABELS_PATH=/app/imagenet_labels.txt
ENV SERVE_HTTP_HOST=0.0.0.0
ENV SERVE_HTTP_PORT=8000
ENV TF_CPP_MIN_LOG_LEVEL=2
ENV TF_NUM_INTRAOP_THREADS=1
ENV TF_NUM_INTEROP_THREADS=1

EXPOSE 8000

# Use the ray serve CLI installed via pip
CMD ["serve", "run", "serve_config.yaml"]
