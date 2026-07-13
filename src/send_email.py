import base64
import os
import re
import smtplib
import sys
import zipfile
from email import encoders
from email.mime.base import MIMEBase
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from io import BytesIO

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
    sep = ';' if ';' in attachment_paths else ','
    attachment_list = [p.strip() for p in attachment_paths.split(sep) if p.strip()]

# Dry-run mode: set SEND_EMAIL_DRY_RUN=1 to compose but not send
DRY_RUN = os.environ.get("SEND_EMAIL_DRY_RUN", "").lower() in ("1", "true", "yes")

# Get app password from environment
app_password = os.environ.get("GMAIL_APP_PASSWORD")
if not app_password and not DRY_RUN:
    raise SystemExit("Error: GMAIL_APP_PASSWORD environment variable not set")
if DRY_RUN:
    print("SEND_EMAIL_DRY_RUN=1 -> dry-run mode enabled; will not perform SMTP send")

smtp_server = "smtp.gmail.com"
smtp_port = 465

# Large-email handling settings
# When the MIME message would exceed EMAIL_MAX_SIZE_MB, we may attach plots.zip
EMAIL_MAX_SIZE_MB = 10  # Trigger large-email fallback above this threshold
ATTACH_PLOTS_ZIP = os.environ.get("ATTACH_PLOTS_ZIP", "").lower() in ("1", "true", "yes")

# Inline image recompression settings (CID path)
EMAIL_IMG_MAX_WIDTH = 800   # px — readable for QC plots
EMAIL_IMG_QUALITY = 50      # JPEG quality — good balance of size/readability


def recompress_for_email(image_bytes):
    """Resize and recompress a JPEG/PNG for inline email embedding."""
    try:
        from PIL import Image as _PIL
        img = _PIL.open(BytesIO(image_bytes)).convert('RGB')
        if img.width > EMAIL_IMG_MAX_WIDTH:
            ratio = EMAIL_IMG_MAX_WIDTH / img.width
            img = img.resize((EMAIL_IMG_MAX_WIDTH, int(img.height * ratio)), _PIL.Resampling.LANCZOS)
        buf = BytesIO()
        img.save(buf, format='JPEG', quality=EMAIL_IMG_QUALITY, optimize=True)
        return buf.getvalue(), 'jpeg'
    except Exception as e:
        print(f"Warning: image recompression failed ({e}), using original")
        return image_bytes, 'jpeg'


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

# ── Build email ────────────────────────────────────────────────────────────────

use_zip = False      # will be set True if we attach plots.zip instead
image_data_map = {} # populated below if html_content has inline images

if html_content:
    image_pattern = r'src=["\']data:image/(png|jpeg|jpg|gif|webp|svg\+xml);base64,([A-Za-z0-9+/=]+)["\']'
    matches = list(re.finditer(image_pattern, html_content))
    print(f"Found {len(matches)} inline images in HTML.")

    # Decode images; recompress for CID path, keep raw for zip (avoids double-compression)
    image_data_map = {}  # idx -> (compressed_bytes, fmt, original_src_attr, raw_bytes)
    for i, match in enumerate(matches):
        fmt = match.group(1).lower().replace('jpg', 'jpeg')
        raw = base64.b64decode(match.group(2))
        compressed, fmt = recompress_for_email(raw)
        image_data_map[i] = (compressed, fmt, match.group(0), raw)

    # Also detect externally-referenced plot files in the HTML (e.g. results/fastp_plots/...)
    external_plot_paths = set()
    for m in re.finditer(r"(?:src|href)=[\"'](results/fastp_plots/[^\"']+\.(?:png|jpe?g))[\"']", html_content, flags=re.IGNORECASE):
        external_plot_paths.add(os.path.normpath(m.group(1)))

    # Estimate MIME size for the CID path:
    #   - HTML with base64 stripped out (replaced by short cid: refs)
    #   - Recompressed images attached as base64-encoded MIME parts
    #   - Any file attachments
    base64_bytes_in_html = sum(len(m.group(0)) for m in matches)
    cid_ref_bytes = len(matches) * 40  # approx size of each cid: replacement
    est_html_stripped = max(0, len(html_content.encode('utf-8', errors='replace'))
                            - base64_bytes_in_html + cid_ref_bytes)
    est_images = sum(len(b) * 4 // 3 for b, _, _, _ in image_data_map.values())
    est_attach = sum(os.path.getsize(p) * 4 // 3
                     for p in attachment_list if os.path.exists(p))
    # Estimate external plot bytes (if files exist) and account for base64 expansion
    est_external = 0
    for rel in external_plot_paths:
        abs_path = os.path.abspath(rel)
        if not os.path.exists(abs_path) and content_arg:
            # try relative to the HTML file directory
            abs_path = os.path.join(os.path.dirname(content_file_path or ''), rel)
        if os.path.exists(abs_path):
            try:
                est_external += os.path.getsize(abs_path) * 4 // 3
            except Exception:
                pass

    est_total_mb = (est_html_stripped + est_images + est_attach + est_external) / 1024 / 1024
    print(f"Estimated MIME size: {est_total_mb:.1f} MB (limit: {EMAIL_MAX_SIZE_MB} MB)")

    too_large = est_total_mb > EMAIL_MAX_SIZE_MB

    # Determine total plot count (inline + external references)
    total_plots = len(image_data_map) + len(external_plot_paths)
    # Only attach plots.zip when BOTH conditions are met
    zip_condition = (total_plots > 100 and est_total_mb > EMAIL_MAX_SIZE_MB)

    if too_large and not ATTACH_PLOTS_ZIP:
        # attach zip only when both thresholds are met
        if zip_condition:
            print(f"Email large ({est_total_mb:.1f} MB) — attaching plots.zip ({total_plots} plots)")
            use_zip = True
        else:
            print(f"Email large ({est_total_mb:.1f} MB) but zip criteria not met (plots: {total_plots}); not attaching zip.")
    if ATTACH_PLOTS_ZIP:
        # Honor explicit request only if the thresholds are met
        if zip_condition:
            print(f"ATTACH_PLOTS_ZIP set — attaching {total_plots} images as plots.zip.")
            use_zip = True
        else:
            print(f"ATTACH_PLOTS_ZIP set but zip criteria not met (plots: {total_plots}, size: {est_total_mb:.1f} MB); skipping zip.")

if use_zip:
    # ── Zip attachment path ────────────────────────────────────────────────────
    zip_buf = BytesIO()
    with zipfile.ZipFile(zip_buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        # include inline raw images
        for i, (_, fmt, _, raw_bytes) in image_data_map.items():
            zf.writestr(f"plot_{i:04d}.jpg", raw_bytes)
        # include externally referenced plot files when available
        for rel in sorted(external_plot_paths):
            abs_path = os.path.abspath(rel)
            if not os.path.exists(abs_path) and content_file_path:
                abs_path = os.path.join(os.path.dirname(content_file_path), rel)
            if os.path.exists(abs_path):
                try:
                    zf.write(abs_path, arcname=os.path.basename(abs_path))
                except Exception:
                    pass
    zip_bytes = zip_buf.getvalue()
    print(f"Created plots.zip: {len(zip_bytes)/1024/1024:.1f} MB ({len(image_data_map)} images + {len(external_plot_paths)} external)")

    # Strip inline base64 images from HTML; replace with a labelled placeholder
    modified_html = html_content
    for i, (_, fmt, old_src, _) in image_data_map.items():
        modified_html = modified_html.replace(
            old_src, f'alt="plot_{i:04d}.jpg" src=""', 1)

    # Insert a notice banner after the opening <body> tag
    notice = (
        '<div style="background:#fff3cd;border:1px solid #e6ac00;padding:8px 12px;'
        'margin:8px 0;font-family:sans-serif;font-size:13px;>'
        f'QC plots ({len(image_data_map)} images) are attached as <strong>plots.zip</strong>.'
        '</div>'
    )
    body_match = re.search(r'<body[^>]*>', modified_html)
    if body_match:
        pos = body_match.end()
        modified_html = modified_html[:pos] + notice + modified_html[pos:]

    message = MIMEMultipart('mixed')
    message["Subject"] = subject
    message["From"] = sender_email
    message["To"] = receiver_email
    message["Cc"] = cc_email
    message.attach(MIMEText(modified_html, "html"))

    zip_part = MIMEBase("application", "zip")
    zip_part.set_payload(zip_bytes)
    encoders.encode_base64(zip_part)
    zip_part.add_header("Content-Disposition", "attachment; filename=plots.zip")
    message.attach(zip_part)

else:
    # ── Inline CID path ───────────────────────────────────────────────────────
    # Top-level container is multipart/mixed and carries the file attachments.
    # The HTML body and its inline cid: images live in a nested multipart/related
    # so clients (notably Gmail) bind the cid refs and render the plots inline
    # instead of demoting them to attachments.
    message = MIMEMultipart('mixed')
    message["Subject"] = subject
    message["From"] = sender_email
    message["To"] = receiver_email
    message["Cc"] = cc_email

    if text_content:
        message.attach(MIMEText(text_content, "plain"))

    if html_content:
        related = MIMEMultipart('related')

        modified_html = html_content
        for i, (img_bytes, fmt, old_src, _) in image_data_map.items():
            cid = f"image_{i}@grtHub"
            modified_html = modified_html.replace(old_src, f'src="cid:{cid}"', 1)

        related.attach(MIMEText(modified_html, "html"))

        for i, (img_bytes, fmt, _, _) in image_data_map.items():
            cid = f"image_{i}@grtHub"
            try:
                img = MIMEImage(img_bytes, fmt)
                img.add_header('Content-ID', f'<{cid}>')
                img.add_header('Content-Disposition', 'inline')
                related.attach(img)
            except Exception as e:
                print(f"Warning: Failed to attach image {i}: {e}")

        message.attach(related)

# ── Attachments ───────────────────────────────────────────────────────────────
for attachment_path in attachment_list:
    if attachment_path.lower() == "none":
        continue
    attachment_abs = os.path.abspath(attachment_path) if os.path.exists(attachment_path) else attachment_path
    if content_file_path and attachment_abs == content_file_path:
        continue
    if os.path.exists(attachment_path):
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

# ── Send ──────────────────────────────────────────────────────────────────────
msg_str = message.as_string()
actual_mb = len(msg_str) / 1024 / 1024
print(f"Actual MIME message size: {actual_mb:.1f} MB")

# If dry-run mode is enabled, don't attempt SMTP send
if DRY_RUN:
    print(f"Dry-run: would send email to {receiver_email} (cc: {cc_email}), subject: {subject}")
    sys.exit(0)

try:
    with smtplib.SMTP_SSL(smtp_server, smtp_port) as server:
        server.login(sender_email, app_password)
        recipients = [receiver_email, cc_email]
        server.sendmail(sender_email, recipients, msg_str)
    print(f"Email sent successfully to {receiver_email} (cc: {cc_email})!")
except Exception as e:

    print(f"Error sending email: {e}")
    sys.exit(1)