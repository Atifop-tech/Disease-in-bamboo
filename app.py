import os
import tempfile

import numpy as np
from flask import Flask, jsonify, request
from flask_cors import CORS
from tensorflow.keras.models import load_model
from tensorflow.keras.preprocessing import image

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

model = load_model("bamboo_disease_model.h5")

CLASSES = [
    "Fungal_Rust",
    "Healthy",
    "Mosaic_Virus",
    "Sooty_Mold",
    "Yellow_Bamboo",
]


def predict_image(img_path):
    img = image.load_img(img_path, target_size=(224, 224))
    img_array = image.img_to_array(img)
    img_array = np.expand_dims(img_array, axis=0)
    img_array = img_array / 255.0

    prediction = model.predict(img_array, verbose=0)
    predicted_index = int(np.argmax(prediction))
    confidence = float(prediction[0][predicted_index])

    return {
        "class": CLASSES[predicted_index],
        "confidence": confidence,
    }


@app.route("/predict", methods=["POST"])
def predict():
    if "file" not in request.files:
        return jsonify({"error": "No file field named 'file' was provided."}), 400

    file = request.files["file"]
    if file.filename == "":
        return jsonify({"error": "No file was selected."}), 400

    temp_path = None

    try:
        _, extension = os.path.splitext(file.filename)
        with tempfile.NamedTemporaryFile(delete=False, suffix=extension or ".jpg") as temp_file:
            file.save(temp_file.name)
            temp_path = temp_file.name

        result = predict_image(temp_path)
        return jsonify(result)
    except Exception as error:
        return jsonify({"error": str(error)}), 500
    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
