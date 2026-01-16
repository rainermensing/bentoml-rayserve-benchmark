"""
Download and save MobileNetV2 model for both BentoML and FastAPI services.
Uses TensorFlow's built-in MobileNetV2 for ImageNet classification.

IMPORTANT: This script must be run with TensorFlow 2.15.0 to ensure
model compatibility with the containerized services.
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import tensorflow as tf

MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(MODEL_DIR, "mobilenet_v2.keras")


def download_and_save_model():
    """Download MobileNetV2 and save locally."""
    print(f"TensorFlow version: {tf.__version__}")
    print()
    
    print("Downloading MobileNetV2 from TensorFlow applications...")
    
    # Use TensorFlow's built-in MobileNetV2 (pre-trained on ImageNet)
    model = tf.keras.applications.MobileNetV2(
        input_shape=(224, 224, 3),
        include_top=True,
        weights='imagenet'
    )
    
    model.summary()
    
    # Save the model in Keras format
    print(f"\nSaving model to {MODEL_PATH}...")
    model.save(MODEL_PATH)
    print("Model saved successfully!")
    
    # Verify the model can be loaded
    print("\nVerifying model can be loaded...")
    loaded_model = tf.keras.models.load_model(MODEL_PATH)
    print(f"Model loaded successfully! Input shape: {loaded_model.input_shape}")
    
    return MODEL_PATH


def download_imagenet_labels():
    """Download ImageNet labels for MobileNetV2."""
    print("\nDownloading ImageNet labels...")
    
    labels_url = "https://storage.googleapis.com/download.tensorflow.org/data/ImageNetLabels.txt"
    labels_path = tf.keras.utils.get_file("ImageNetLabels.txt", labels_url)
    
    with open(labels_path, "r") as f:
        labels = [line.strip() for line in f.readlines()]
    
    # Save labels locally
    labels_file = os.path.join(MODEL_DIR, "imagenet_labels.txt")
    with open(labels_file, "w") as f:
        f.write("\n".join(labels))
    
    print(f"Labels saved to {labels_file} ({len(labels)} classes)")
    return labels


if __name__ == "__main__":
    print("=" * 50)
    print("MobileNetV2 Model Download")
    print("=" * 50)
    print()
    
    # Check TensorFlow version
    tf_version = tf.__version__
    if not tf_version.startswith("2.15"):
        print(f"WARNING: Using TensorFlow {tf_version}")
        print("For best compatibility, use TensorFlow 2.15.0:")
        print("  uv pip install tensorflow==2.15.0")
        print()
    
    model_path = download_and_save_model()
    labels = download_imagenet_labels()
    
    print()
    print("=" * 50)
    print("Download Complete!")
    print("=" * 50)
    print(f"Model: {model_path}")
    print(f"Labels: {len(labels)} classes")
    print()
    print("Next steps:")
    print("  1. Copy model to bentoml/: cp model/mobilenet_v2.keras bentoml/")
    print("  2. Copy labels to bentoml/: cp model/imagenet_labels.txt bentoml/")
    print("  3. Build images: ./scripts/build-images.sh")
