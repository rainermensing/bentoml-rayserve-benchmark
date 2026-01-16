import os
import io
import numpy as np
from PIL import Image
from locust import HttpUser, task, between

class MLServiceUser(HttpUser):
    wait_time = between(0.1, 0.5)
    
    def on_start(self):
        # Generate a sample image for testing
        img_array = np.random.randint(0, 256, (224, 224, 3), dtype=np.uint8)
        img = Image.fromarray(img_array, 'RGB')
        img_byte_arr = io.BytesIO()
        img.save(img_byte_arr, format='JPEG')
        self.image_content = img_byte_arr.getvalue()

    @task
    def predict(self):
        files = {
            'files': ('test_image.jpg', self.image_content, 'image/jpeg')
        }
        self.client.post("/predict", files=files)

    @task(0) # Not running health check by default in load test
    def health(self):
        self.client.get("/health")
