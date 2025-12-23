# send_email.py
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import sys

# Email details from Snakemake arguments
sender_email = sys.argv[1]
receiver_email = sys.argv[2]
subject = sys.argv[3]
html_file_path = sys.argv[4]

# SMTP server details (modify as needed for your server)
smtp_server = "smtp.example.com"
smtp_port = 587  # or 465 for SSL
# If authentication is needed, add username and password variables

# Create the root message and set the headers
message = MIMEMultipart("alternative")
message["Subject"] = subject
message["From"] = sender_email
message["To"] = receiver_email

# Read the HTML file
with open(html_file_path, "r") as f:
    html_content = f.read()

# Turn the HTML content into a MIMEText object
html_part = MIMEText(html_content, "html")

# Add HTML parts to MIMEMultipart message
# The email client will try to render the last part first
message.attach(html_part)

# Send the email
try:
    with smtplib.SMTP(smtp_server, smtp_port) as server:
        # server.login("your_username", "your_password") # Uncomment if authentication is needed
        server.sendmail(sender_email, receiver_email, message.as_string())
    print(f"Email sent successfully to {receiver_email}!")
except Exception as e:
    print(f"Error: {e}")

