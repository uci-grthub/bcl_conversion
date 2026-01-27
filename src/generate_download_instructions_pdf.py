#!/usr/bin/env python3
"""
Generate a PDF with download instructions for sequencing data.
Updated with WebDAV best practices: Resumable clients over Zip downloads.
"""
import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_LEFT, TA_JUSTIFY
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Preformatted
from reportlab.lib import colors
from reportlab.lib.colors import HexColor

def generate_download_instructions_pdf(output_path):
    """Generate a PDF with download instructions."""
    
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        rightMargin=0.75*inch,
        leftMargin=0.75*inch,
        topMargin=0.75*inch,
        bottomMargin=0.75*inch
    )

    elements = []
    styles = getSampleStyleSheet()
    
    # Custom Styles
    title_style = ParagraphStyle('CustomTitle', parent=styles['Heading1'], fontSize=22, textColor=HexColor('#003262'), spaceAfter=15)
    heading_style = ParagraphStyle('CustomHeading', parent=styles['Heading2'], fontSize=14, textColor=HexColor('#003262'), spaceAfter=10, spaceBefore=14)
    body_style = ParagraphStyle('CustomBody', parent=styles['Normal'], fontSize=10.5, textColor=HexColor('#1c2b36'), alignment=TA_JUSTIFY, spaceAfter=8, leading=13)
    code_style = ParagraphStyle('Code', parent=styles['Code'], fontSize=9, textColor=HexColor('#0f172a'), backColor=HexColor('#f4f4f4'), fontName='Courier', leftIndent=6, rightIndent=6, spaceAfter=6, spaceBefore=6)
    warning_style = ParagraphStyle('Warning', parent=body_style, textColor=HexColor('#b91c1c'), fontName='Helvetica-Bold')

    # Title & Intro
    elements.append(Paragraph("Sequencing Data Download Instructions", title_style))
    elements.append(Paragraph("<b>Important:</b> Sequencing datasets are often very large. We strongly recommend using <b>WebDAV</b> with a dedicated file transfer client so downloads can resume if interrupted.", body_style))
    elements.append(Paragraph("<i>Downloading a very large dataset as a single ZIP via a web browser is discouraged because it cannot be resumed.</i>", warning_style))
    elements.append(Spacer(1, 0.2*inch))

    # Method 1: Dedicated Transfer Clients (Best for Stability)
    elements.append(Paragraph("Recommended: Dedicated Transfer Clients", heading_style))
    elements.append(Paragraph("Use these apps for the most reliable, resumable transfers. They handle network disruptions much better than web browsers.", body_style))

    elements.append(Paragraph("<b>Cyberduck (Windows & macOS)</b>", body_style))
    elements.append(Paragraph("1. Download and install from cyberduck.io.<br/>2. Click <b>Open Connection</b> and choose <b>WebDAV (HTTPS)</b>.<br/>3. Server: https://precision.biochem.uci.edu/public.php/webdav/<br/>4. Enter your share token as the username (leave password blank if instructed).", body_style))

    elements.append(Paragraph("<b>WinSCP (Windows)</b>", body_style))
    elements.append(Paragraph("1. Choose <b>WebDAV</b> as the protocol and use TLS/SSL if available.<br/>2. Hostname: https://precision.biochem.uci.edu/public.php/webdav/<br/>3. If resumable transfers fail, try Cyberduck instead.", body_style))
    elements.append(Spacer(1, 0.1*inch))

    # Method 2: Mounting as a Network Drive
    elements.append(Paragraph("🔗 Method 2: OS Network Mounting", heading_style))
    elements.append(Paragraph("You can mount the server as a local folder. For large transfers, use <b>rsync</b> from the mount to your destination to ensure integrity.", body_style))
    
    elements.append(Paragraph("<b>Windows & macOS:</b>", body_style))
    elements.append(Paragraph("• <b>Windows:</b> Right-click 'This PC' → 'Map network drive' → Enter https://precision.biochem.uci.edu/public.php/webdav/.<br/>• <b>macOS:</b> Finder → Command+K → Enter https://precision.biochem.uci.edu/public.php/webdav/ → Enter the Share token as username and leave the password blank.", body_style))
    
    elements.append(Paragraph("<b>Linux (HPC/Command Line):</b>", body_style))
    elements.append(Paragraph("Mount using davfs2 and sync with rsync for the best CLI experience:", body_style))
    linux_cmds = "sudo mount -t davfs https://precision.biochem.uci.edu/public.php/webdav/ /mnt/nextcloud\nrsync -avP /mnt/nextcloud/project_folder/ /home/user/local_data/"
    elements.append(Preformatted(linux_cmds, code_style))
    elements.append(Spacer(1, 0.1*inch))

    # Method 3: HPC / rclone
    elements.append(Paragraph("Method 3: HPC / Remote Servers (rclone)", heading_style))
    elements.append(Paragraph("For cluster environments, rclone is a good choice for high-performance WebDAV transfers.", body_style))
    rclone_cmds = "rclone config  # Create a WebDAV remote\nrclone copy -P myremote:project_folder ./local_folder"
    elements.append(Preformatted(rclone_cmds, code_style))
    elements.append(Spacer(1, 0.1*inch))

    # Integrity Check
    elements.append(Paragraph("Verifying File Integrity", heading_style))
    elements.append(Paragraph("Once your transfer is complete, verify your files against the provided checksums:", body_style))
    elements.append(Preformatted("md5sum -c md5sums.txt", code_style))
    
    # Footer
    elements.append(Spacer(1, 0.3*inch))
    elements.append(Paragraph("<b>Support:</b> Contact the GRTHub team if you experience connectivity issues.", body_style))

    doc.build(elements)
    print(f"Generated updated instructions: {output_path}")

if __name__ == "__main__":
    output = sys.argv[1] if len(sys.argv) > 1 else "Download_Instructions.pdf"
    generate_download_instructions_pdf(output)