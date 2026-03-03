import os
import re
import smtplib
import sys
from email import encoders
from email.mime.base import MIMEBase
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

if len(sys.argv) < 4:
    raise SystemExit("Usage: send_email.py <sender> <receiver> <subject> <body_or_html_path> [attachment_paths] [cc_address]")

sender_email = sys.argv[1]
receiver_email = sys.argv[2]
subject = sys.argv[3]
content_arg = sys.argv[4] if len(sys.argv) > 4 else ""
attachment_paths = sys.argv[5] if len(sys.argv) > 5 else None
cc_email = sys.argv[6] if len(sys.argv) > 6 else "kstachel@uci.edu"

# Parse multiple attachments (semicolon or comma separated)
attachment_list = []
if attachment_paths and attachment_paths.lower() != "none":
    # Split by semicolon first, then by comma as fallback
    sep = ';' if ';' in attachment_paths else ','
    attachment_list = [p.strip() for p in attachment_paths.split(sep) if p.strip()]

# Get app password from environment
app_password = os.environ.get("GMAIL_APP_PASSWORD")
if not app_password:
    raise SystemExit("Error: GMAIL_APP_PASSWORD environment variable not set")

smtp_server = "smtp.gmail.com"
smtp_port = 465

html_content = None
text_content = ""
content_file_path = None

if content_arg:
    if os.path.exists(content_arg):
        content_file_path = os.path.abspath(content_arg)
        with open(content_arg, "r") as f:
            html_content = f.read()
    else:
        text_content = content_arg

# For HTML content with embedded images, use MIMEMultipart('related')
if html_content:
    message = MIMEMultipart('related')
else:
    message = MIMEMultipart()
message["Subject"] = subject
message["From"] = sender_email
message["To"] = receiver_email
message["Cc"] = cc_email

if text_content:
    message.attach(MIMEText(text_content, "plain"))

if html_content:
    # Extract and replace base64 images with Content-ID references (supports PNG, JPEG, GIF, WebP)
    image_pattern = r'src=["\']data:image/(png|jpeg|jpg|gif|webp|svg\+xml);base64,([A-Za-z0-9+/=]+)["\']'
    matches = list(re.finditer(image_pattern, html_content))
    
    modified_html = html_content
    image_data_map = {}
    for i, match in enumerate(matches):
        image_format = match.group(1).lower().replace('jpg', 'jpeg')
        base64_data = match.group(2)
        image_data_map[i] = (base64_data, image_format)
        cid = f"image_{i}@grtHub"
        old_src = match.group(0)
        new_src = f'src="cid:{cid}"'
        modified_html = modified_html.replace(old_src, new_src)
    
    message.attach(MIMEText(modified_html, "html"))
    
    for i, (base64_data, image_format) in image_data_map.items():
        cid = f"image_{i}@grtHub"
        try:
            import base64
            image_bytes = base64.b64decode(base64_data)
            img = MIMEImage(image_bytes, image_format)
            img.add_header('Content-ID', f'<{cid}>')
            img.add_header('Content-Disposition', 'inline')
            message.attach(img)
        except Exception as e:
            print(f"Warning: Failed to extract image {i}: {e}")

for attachment_path in attachment_list:
    if attachment_path.lower() == "none":
        continue
    attachment_abs = os.path.abspath(attachment_path) if os.path.exists(attachment_path) else attachment_path
    if content_file_path and attachment_abs == content_file_path:
        pass
    elif os.path.exists(attachment_path):
        with open(attachment_path, "rb") as f:
            part = MIMEBase("application", "octet-stream")
            part.set_payload(f.read())
        encoders.encode_base64(part)
        part.add_header(
            "Content-Disposition",
            f"attachment; filename={os.path.basename(attachment_path)}",
        )
        message.attach(part)
    else:
        print(f"Attachment not found: {attachment_path}")

try:
    with smtplib.SMTP_SSL(smtp_server, smtp_port) as server:
        server.login(sender_email, app_password)
        # Build recipient list including cc
        recipients = [receiver_email, cc_email]
        server.sendmail(sender_email, recipients, message.as_string())
    print(f"Email sent successfully to {receiver_email} (cc: {cc_email})!")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)

