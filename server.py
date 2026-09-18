import base64
import json
import mimetypes
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def load_dotenv():
    env_path = ROOT / ".env"
    if not env_path.exists():
        return

    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_dotenv()
API_VERSION = os.getenv("WHATSAPP_API_VERSION", "v20.0")
WHATSAPP_TOKEN = os.getenv("WHATSAPP_TOKEN", "")
WHATSAPP_PHONE_NUMBER_ID = os.getenv("WHATSAPP_PHONE_NUMBER_ID", "")


def normalize_phone(phone):
    digits = "".join(ch for ch in str(phone or "") if ch.isdigit())
    if len(digits) == 10:
        return f"91{digits}"
    return digits


def graph_request(path, data, headers):
    request = urllib.request.Request(
        f"https://graph.facebook.com/{API_VERSION}/{path}",
        data=data,
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(detail or str(error)) from error


def make_multipart(fields, files):
    boundary = f"----MediStock{uuid.uuid4().hex}"
    chunks = []

    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                str(value).encode(),
                b"\r\n",
            ]
        )

    for name, file_info in files.items():
        filename, content, content_type = file_info
        chunks.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'.encode(),
                f"Content-Type: {content_type}\r\n\r\n".encode(),
                content,
                b"\r\n",
            ]
        )

    chunks.append(f"--{boundary}--\r\n".encode())
    return boundary, b"".join(chunks)


def upload_pdf_to_whatsapp(file_name, pdf_bytes):
    boundary, body = make_multipart(
        {
            "messaging_product": "whatsapp",
            "type": "application/pdf",
        },
        {
            "file": (file_name, pdf_bytes, "application/pdf"),
        },
    )
    result = graph_request(
        f"{WHATSAPP_PHONE_NUMBER_ID}/media",
        body,
        {
            "Authorization": f"Bearer {WHATSAPP_TOKEN}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    media_id = result.get("id")
    if not media_id:
        raise RuntimeError(f"WhatsApp media upload did not return an id: {result}")
    return media_id


def send_whatsapp_document(phone, media_id, file_name, caption):
    body = json.dumps(
        {
            "messaging_product": "whatsapp",
            "to": normalize_phone(phone),
            "type": "document",
            "document": {
                "id": media_id,
                "filename": file_name,
                "caption": caption,
            },
        }
    ).encode("utf-8")
    return graph_request(
        f"{WHATSAPP_PHONE_NUMBER_ID}/messages",
        body,
        {
            "Authorization": f"Bearer {WHATSAPP_TOKEN}",
            "Content-Type": "application/json",
        },
    )


class MediStockHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/api/send-invoice-whatsapp":
            self.send_json(404, {"error": "Unknown API route."})
            return

        if not WHATSAPP_TOKEN or not WHATSAPP_PHONE_NUMBER_ID:
            self.send_json(
                503,
                {
                    "error": "Automatic WhatsApp is not configured. Set WHATSAPP_TOKEN and WHATSAPP_PHONE_NUMBER_ID before starting server.py.",
                },
            )
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            phone = normalize_phone(payload.get("phone"))
            pdf_base64 = payload.get("pdfBase64", "")
            file_name = payload.get("fileName") or "MediStock-Bill.pdf"
            message = payload.get("message") or "MediStock bill PDF."

            if not phone:
                self.send_json(400, {"error": "Customer phone number is required."})
                return
            if not pdf_base64:
                self.send_json(400, {"error": "PDF data is required."})
                return

            pdf_bytes = base64.b64decode(pdf_base64)
            media_id = upload_pdf_to_whatsapp(file_name, pdf_bytes)
            result = send_whatsapp_document(phone, media_id, file_name, message)
            self.send_json(200, {"ok": True, "whatsapp": result})
        except Exception as error:
            self.send_json(500, {"error": str(error)})


def main():
    port = int(os.getenv("PORT", "8000"))
    server = ThreadingHTTPServer(("localhost", port), MediStockHandler)
    print(f"MediStock running at http://localhost:{port}/index.html")
    print("Automatic WhatsApp requires WHATSAPP_TOKEN and WHATSAPP_PHONE_NUMBER_ID.")
    server.serve_forever()


if __name__ == "__main__":
    main()
