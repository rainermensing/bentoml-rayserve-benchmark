FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install with pip
COPY fastapi/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy model files from model directory
COPY model/mobilenet_v2.keras /app/model/
COPY model/imagenet_labels.txt /app/

# Copy application code
COPY fastapi/main.py .

ENV MODEL_PATH=/app/model/mobilenet_v2.keras
ENV LABELS_PATH=/app/imagenet_labels.txt
ENV TF_CPP_MIN_LOG_LEVEL=2
# Pin TensorFlow thread pools to reduce oversubscription on small nodes
ENV TF_NUM_INTRAOP_THREADS=1
ENV TF_NUM_INTEROP_THREADS=1

EXPOSE 8000

# Run with uvicorn, align workers to 1 core (matches k8s limits)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
