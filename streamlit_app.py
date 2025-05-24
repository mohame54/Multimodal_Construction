import time
import streamlit as st
from PIL import Image
from utils import (
    get_llm_answer,
    get_vector_store,
    pilImage_2base64
)


index = get_vector_store("index")

st.title("Multimodal Retrieval: Find Similar Texts to Your Image")
st.write(
    "Upload an image, and the app will return the top 3 most similar text chunks, "
    "then stream you an LLM answer based on that context."
)

# Sidebar options
show_rag = st.sidebar.checkbox("Show RAG (retrieval) results", value=True)
if "stop_stream" not in st.session_state:
    st.session_state.stop_stream = False

# Upload
uploaded_image = st.file_uploader("Upload an image", type=["jpg", "jpeg", "png"])
if not uploaded_image:
    st.info("Please upload an image to get started.")
    st.stop()

try:
    image = Image.open(uploaded_image).convert("RGB")
except Exception as e:
    st.error(f"Could not open image: {e}")
    st.stop()


# Show Image

st.image(image)
# Retrieval
with st.spinner("Finding similar documents..."):
    results = index.query(image, top_k=3)

# Show RAG
if show_rag:
    st.subheader("Top 3 Retrieved Text Chunks")
    for i, (doc, score) in enumerate(results, 1):
        st.markdown(f"**{i}. (Score: {score:.4f})**")
        st.write(doc)

# Prepare query
context = "\n".join(doc for doc, _ in results)
query = (
    f"Based on the image plus the provided retrieved context, "
    f"provide an answer. Context:\n\n{context}"
)

st.subheader("LLM Answer")
answer_placeholder = st.empty()
full_answer = ""


if st.button("Stop"):
    st.session_state.stop_stream = True

# Stream loop
try:
    t1 = time.time()
    for chunk in get_llm_answer(pilImage_2base64(image), query):
        if st.session_state.stop_stream:
            # Reset flag and exit loop
            st.session_state.stop_stream = False
            answer_placeholder.markdown(full_answer + "\n\n*Stream stopped by user.*")
            break

        delta = getattr(chunk.choices[0].delta, "content", "")
        if not delta:
            continue

        full_answer += delta
        answer_placeholder.markdown(full_answer)
    elapsed = time.time() - t1
    st.write(f"🕒 Response time: {elapsed:.2f} seconds")
except Exception as e:
    st.error(f"Error while streaming LLM response: {e}")
