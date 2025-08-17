# services/ocr-pdf2md/Dockerfile
FROM public.ecr.aws/lambda/python:3.12

# Python deps (pin torch CPU build you validated)
RUN python -m pip install --no-cache-dir \
    "torch==2.2.2" \
    "docling>=1.16.0,<2.0" \
    "onnxruntime>=1.17.0" \
    rapidocr-onnxruntime \
    huggingface_hub \
    boto3

# Cache RapidOCR models at build time (no runtime downloads)
RUN python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="SWHL/RapidOCR",
    local_dir="/opt/models/rapidocr",
    local_dir_use_symlinks=False
)
print("RapidOCR models cached.")
PY

# Copy function code
COPY app /var/task/app

# Runtime env
ENV OCR_MODELS_DIR=/opt/models/rapidocr
ENV DOCLING_CACHE_DIR=/tmp/docling_cache
ENV PYTHONUNBUFFERED=1

# Lambda handler (module.submodule.function)
CMD ["app.handler.lambda_handler"]
