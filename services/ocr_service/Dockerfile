# Use the AWS Lambda Python base (AL2023)
FROM public.ecr.aws/lambda/python:3.12

# ---- System libs (native deps for onnxruntime/torch/Pillow) ----
RUN dnf install -y \
      libgomp \
      libstdc++ \
      zlib \
      libjpeg-turbo \
      libpng \
      freetype \
  && dnf clean all

# ---- Python deps (Docling v2 + headless OpenCV to avoid libGL) ----
# numpy<2 keeps ABI friction low with current wheels
RUN python -m pip install --no-cache-dir --upgrade pip \
 && python -m pip install --no-cache-dir \
      "numpy==1.26.4" \
      "onnxruntime==1.17.1" \
      "torch==2.2.2" \
      "opencv-python-headless<5" \
      "docling>=2.0.0,<3.0.0" \
      rapidocr-onnxruntime \
      huggingface_hub \
      boto3 \
      pillow

# ---- Cache RapidOCR ONNX models in the image (no runtime downloads) ----
RUN python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="SWHL/RapidOCR",
    local_dir="/opt/models/rapidocr",
    local_dir_use_symlinks=False
)
print("RapidOCR models cached at /opt/models/rapidocr")
PY

# ---- Build-time smoke checks (fail early if imports break) ----
RUN python - <<'PY'
import docling
from docling.document_converter import DocumentConverter
from docling.datamodel.pipeline_options import PdfPipelineOptions, RapidOcrOptions
print("Docling version:", getattr(docling, "__version__", "unknown"))
print("Imports OK:", DocumentConverter, PdfPipelineOptions, RapidOcrOptions)
PY

# ---- App code & runtime env ----
COPY app /var/task/app
ENV OCR_MODELS_DIR=/opt/models/rapidocr
ENV DOCLING_CACHE_DIR=/tmp/docling_cache
ENV PYTHONUNBUFFERED=1

# Lambda entrypoint: module.function
CMD ["app.handler.lambda_handler"]
