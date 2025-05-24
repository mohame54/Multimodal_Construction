import os
import io
import re
import json
import faiss
import base64
import traceback
import numpy as np
from PIL import Image
import onnxruntime as ort
from transformers import CLIPProcessor
from openai import OpenAI
import streamlit as  st
from pdfminer.high_level import extract_text
from prompts import SYSTEM_PROMPT
import time


class FaissVecStore:
    def __init__(self, local_index_path=None, dim=512):
        self.dim = dim
        self.index = self.create_index()
        self.all_chunks = {}  # Mapping from ID to chunk text

        if local_index_path:
            index_file = os.path.join(local_index_path, "index.faiss")
            chunks_file = os.path.join(local_index_path, "chunks.json")

            if os.path.exists(index_file):
                self.index = faiss.read_index(index_file)
            else:
                raise FileNotFoundError(f"Index file not found at {index_file}")

            if os.path.exists(chunks_file):
                with open(chunks_file, "r", encoding="utf-8") as f:
                    self.all_chunks = json.load(f)
            else:
                raise FileNotFoundError(f"Chunks file not found at {chunks_file}")

        # Initialize ONNX sessions and processor
        self.txt_session = ort.InferenceSession("onnx_models/text_model.onnx")
        self.vision_session = ort.InferenceSession("onnx_models/vision_model.onnx")
        self.processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")

    def create_index(self):
        return faiss.IndexIDMap(faiss.IndexFlatL2(self.dim))

    def add_vecs(self, chunks, ids=None):
        if ids is None:
            # Auto-generate IDs starting from the current maximum
            if self.all_chunks:
                max_id = max(int(k) for k in self.all_chunks.keys())
                ids = [str(i) for i in range(max_id + 1, max_id + 1 + len(chunks))]
            else:
                ids = [str(i) for i in range(len(chunks))]
        else:
            ids = [str(i) for i in ids]

        embeddings = self.get_texts_embeddings(chunks)
        embeddings = np.array(embeddings, dtype=np.float32)
        ids_array = np.array([int(i) for i in ids], dtype=np.int64)

        self.index.add_with_ids(embeddings, ids_array)
        for i, chunk in zip(ids, chunks):
            self.all_chunks[i] = chunk

    def get_texts_embeddings(self, texts):
        inputs = self.processor(text=texts, return_tensors="np", padding=True, truncation=True)
        ort_inputs = {"input_ids": inputs["input_ids"], "attention_mask": inputs["attention_mask"]}
        outputs = self.txt_session.run(["text_features"], ort_inputs)
        return outputs[0]

    def get_images_embeddings(self, images):
        inputs = self.processor(images=images, return_tensors="np")["pixel_values"]
        outputs = self.vision_session.run(["image_features"], {"pixel_values": inputs})
        return outputs[0]

    def delete_vecs(self, ids_to_delete):
        if not ids_to_delete:
            return

        ids_array = np.array([int(i) for i in ids_to_delete], dtype=np.int64)
        self.index.remove_ids(ids_array)

        for idx in ids_to_delete:
            self.all_chunks.pop(str(idx), None)

    def query(self, query, top_k=5):
        if isinstance(query, str):
            query_embedding = self.get_texts_embeddings([query])
        else:
            query_embedding = self.get_images_embeddings([query])
        query_embedding = np.array(query_embedding, dtype=np.float32)

        distances, indices = self.index.search(query_embedding, top_k)

        results = []
        for idx, dist in zip(indices[0], distances[0]):
            if idx != -1:
                chunk = self.all_chunks.get(str(idx))
                if chunk:
                    results.append((chunk, dist))
        return results

    def save(self, folder_path):
        os.makedirs(folder_path, exist_ok=True)
        index_file = os.path.join(folder_path, "index.faiss")
        chunks_file = os.path.join(folder_path, "chunks.json")

        faiss.write_index(self.index, index_file)

        with open(chunks_file, "w", encoding="utf-8") as f:
            json.dump(self.all_chunks, f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, folder_path, dim=512):
        return cls(local_index_path=folder_path, dim=dim)

def chunk_chars(
    text: str,
    max_len: int,
    overlap: int
):
    if overlap >= max_len:
        raise ValueError("overlap must be smaller than max_len")

    chunks = []
    start = 0
    n = len(text)
    while start < n:
        end = min(start + max_len, n)
        chunks.append(text[start:end])
        start += max_len - overlap
    return chunks


def simple_text_splitter(text, chunk_size=300, overlap=50):
    # Split text into sentences, then group into chunks
    sentences = re.split(r'(?<=[.!?])\s+', text)
    chunks = []
    current_chunk = ""
    if not len(sentences):
        return chunk_chars(text, max_len=chunk_size, overlap=overlap)
    for sentence in sentences:
        if len(current_chunk) + len(sentence) < chunk_size:
            current_chunk += " " + sentence if current_chunk else sentence
        else:
            chunks.append(current_chunk.strip())
            overlap_text = current_chunk[-overlap:] if overlap > 0 else ""
            current_chunk = overlap_text + " " + sentence
    if current_chunk.strip():
        chunks.append(current_chunk.strip())
    return [c for c in chunks if c.strip()]


@st.cache_resource
def get_vector_store(local_path=None):
    index = FaissVecStore.load(local_path)
    if local_path is None or not os.path.exists(local_path):
        chunks = simple_text_splitter(extract_text("./Regulations.pdf"))
        index.add_vecs(chunks)
        local_path = "index" if local_path is None else local_path
        index.save(local_path)
    return index


def get_llm_answer(b64_image, query):
    client = OpenAI(
        base_url = 'http://localhost:11434/v1',
        api_key='ollama'
    )

    t1 = time.time()
    messages = [
        {"role":"system", "content":SYSTEM_PROMPT},
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/png;base64,{b64_image}"
                    }
                },
                {
                    "type": "text",
                    "text":query
                },
               
            ]
        }
    ]
    response = client.chat.completions.create(
        model="qwen2.5vl:3b",
        messages=messages,
        stream=True
    )
    return response


def base64_2image(base64_str: str):
    image_data = base64.b64decode(base64_str)
    return Image.open(io.BytesIO(image_data))
   


def pilImage_2base64(img, format="PNG"):
    buffer = io.BytesIO()
    img.save(buffer, format=format)
    return base64.b64encode(buffer.getvalue()).decode("utf-8")