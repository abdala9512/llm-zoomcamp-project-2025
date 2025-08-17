# services/ocr_service/app/handler.py
import os, json, hashlib, tempfile, datetime, re
import boto3

from docling.document_converter import DocumentConverter, PdfFormatOption, InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions, RapidOcrOptions
from docling_core.types.doc import ImageRefMode  # may be unused if your version lacks PLACEHOLDER

s3 = boto3.client("s3")
OUT_BUCKET = os.environ.get("OUT_BUCKET")
ENABLE_OCR = os.environ.get("ENABLE_OCR", "auto")  # "auto" | "always" | "never"
OCR_MODELS_DIR = os.environ.get("OCR_MODELS_DIR", "/opt/models/rapidocr")

def _sha256_bytes(b: bytes) -> str:
    h = hashlib.sha256(); h.update(b); return h.hexdigest()

def _should_do_ocr(_obj_bytes: bytes) -> bool:
    if ENABLE_OCR == "always": return True
    if ENABLE_OCR == "never":  return False
    return True  # "auto": let pipeline use OCR when needed

def _front_matter(meta: dict) -> str:
    lines = ["---"]
    for k, v in meta.items():
        if isinstance(v, (dict, list)):
            v = json.dumps(v, ensure_ascii=False)
        lines.append(f"{k}: {v}")
    lines.append("---\n")
    return "\n".join(lines)

def lambda_handler(event, context):
    for rec in event.get("Records", []):
        bkt = rec["s3"]["bucket"]["name"]
        key = rec["s3"]["object"]["key"]
        if not key.lower().endswith(".pdf"):
            continue

        # Download PDF
        obj = s3.get_object(Bucket=bkt, Key=key)
        pdf_bytes = obj["Body"].read()
        digest = _sha256_bytes(pdf_bytes)

        base_no_ext = re.sub(r"\.pdf$", "", key, flags=re.IGNORECASE)
        out_md_key = f"{base_no_ext}.md"

        with tempfile.TemporaryDirectory() as tmpd:
            pdf_path = os.path.join(tmpd, "input.pdf")
            with open(pdf_path, "wb") as f:
                f.write(pdf_bytes)

            # Docling pipeline
            pipe = PdfPipelineOptions()
            pipe.do_ocr = _should_do_ocr(pdf_bytes)

            # RapidOCR paths (pre-bundled)
            from pathlib import Path
            det = Path(OCR_MODELS_DIR) / "PP-OCRv4" / "en_PP-OCRv3_det_infer.onnx"
            recp = Path(OCR_MODELS_DIR) / "PP-OCRv4" / "ch_PP-OCRv4_rec_server_infer.onnx"
            cls = Path(OCR_MODELS_DIR) / "PP-OCRv3" / "ch_ppocr_mobile_v2.0_cls_train.onnx"
            pipe.ocr_options = RapidOcrOptions(
                det_model_path=str(det),
                rec_model_path=str(recp),
                cls_model_path=str(cls),
            )

            # Explicitly disable image generation
            pipe.generate_page_images = False
            pipe.generate_picture_images = False

            converter = DocumentConverter(format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipe)
            })

            conv = converter.convert(pdf_path)

            # Save Markdown (no images)
            out_dir = os.path.join(tmpd, "out")
            os.makedirs(out_dir, exist_ok=True)
            md_path = os.path.join(out_dir, "doc.md")

            # Some Docling versions support placeholders; otherwise omit image_mode
            try:
                conv.document.save_as_markdown(md_path, image_mode=ImageRefMode.PLACEHOLDER)
            except Exception:
                conv.document.save_as_markdown(md_path)

            title = conv.document.title or os.path.basename(key)
            meta = {
                "title": title,
                "source_s3": f"s3://{bkt}/{key}",
                "output_s3_md": f"s3://{OUT_BUCKET}/{out_md_key}",
                "sha256": digest,
                "pages": len(conv.document.pages),
                "converted_at": datetime.datetime.utcnow().isoformat() + "Z",
                "docling_version": "runtime",
                "ocr": pipe.do_ocr,
            }

            body = open(md_path, "r", encoding="utf-8").read()
            fm = _front_matter(meta) + body
            s3.put_object(
                Bucket=OUT_BUCKET,
                Key=out_md_key,
                Body=fm.encode("utf-8"),
                ContentType="text/markdown; charset=utf-8",
            )

    return {"status": "ok"}
