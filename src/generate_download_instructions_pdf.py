#!/usr/bin/env python3
"""
Generate a PDF with download instructions for sequencing data.
"""
import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib.enums import TA_LEFT, TA_JUSTIFY
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib import colors
from reportlab.lib.colors import HexColor

def generate_download_instructions_pdf(output_path):
    """Generate a PDF with download instructions."""
    
    # Create the PDF document
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        rightMargin=0.75*inch,
        leftMargin=0.75*inch,
        topMargin=0.75*inch,
        bottomMargin=0.75*inch
    )
    
    # Container for the 'Flowable' objects
    elements = []
    
    # Define styles
    styles = getSampleStyleSheet()
    
    # Custom title style
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=HexColor('#003262'),
        spaceAfter=20,
        alignment=TA_LEFT
    )
    
    # Custom heading style
    heading_style = ParagraphStyle(
        'CustomHeading',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=HexColor('#003262'),
        spaceAfter=12,
        spaceBefore=16
    )
    
    # Custom body style
    body_style = ParagraphStyle(
        'CustomBody',
        parent=styles['Normal'],
        fontSize=11,
        textColor=HexColor('#1c2b36'),
        alignment=TA_JUSTIFY,
        spaceAfter=10,
        leading=14
    )
    
    # Code style
    code_style = ParagraphStyle(
        'Code',
        parent=styles['Normal'],
        fontSize=9,
        textColor=HexColor('#f7fafc'),
        backColor=HexColor('#0f172a'),
        fontName='Courier',
        leftIndent=10,
        rightIndent=10,
        spaceAfter=8,
        spaceBefore=8
    )
    
    # Add title
    elements.append(Paragraph("How to Download Your Sequencing Data", title_style))
    elements.append(Spacer(1, 0.2*inch))
    
    # Add introduction
    intro_text = """Choose the method that works best for your setup. All methods allow you to download 
    the entire folder as a zip archive or individual files."""
    elements.append(Paragraph(intro_text, body_style))
    elements.append(Spacer(1, 0.3*inch))
    
    # Method 1: Browser
    elements.append(Paragraph("🌐 Browser (One-click)", heading_style))
    elements.append(Paragraph("<i>Windows, macOS, Linux</i>", body_style))
    elements.append(Spacer(1, 0.1*inch))
    
    elements.append(Paragraph("• Open your download link (provided in the email) in any web browser.", body_style))
    elements.append(Paragraph("• Click <b>Download</b> (top-right in the Nextcloud interface) to fetch the entire folder as a zip.", body_style))
    elements.append(Paragraph("• Or click individual files to download them one by one.", body_style))
    elements.append(Spacer(1, 0.2*inch))
    
    # Method 2: Command Line (wget)
    elements.append(Paragraph("💻 Command Line (wget)", heading_style))
    elements.append(Paragraph("<i>Linux / macOS / Windows (WSL)</i>", body_style))
    elements.append(Spacer(1, 0.1*inch))
    
    elements.append(Paragraph("• Open a terminal and navigate to your target folder.", body_style))
    elements.append(Paragraph("• Download the entire folder as zip:", body_style))
    
    wget_cmd1 = '<font face="Courier" color="#f7fafc">wget --content-disposition "YOUR_LINK/download"</font>'
    elements.append(Paragraph(wget_cmd1, code_style))
    
    elements.append(Paragraph("• Or download a single file:", body_style))
    
    wget_cmd2 = '<font face="Courier" color="#f7fafc">wget --content-disposition "YOUR_LINK/download?path=/&amp;files=FILENAME"</font>'
    elements.append(Paragraph(wget_cmd2, code_style))
    elements.append(Spacer(1, 0.2*inch))
    
    # Method 3: HPC / Remote Servers
    elements.append(Paragraph("🖥️ HPC / Remote Servers", heading_style))
    elements.append(Paragraph("<i>Cluster or shared server environments</i>", body_style))
    elements.append(Spacer(1, 0.1*inch))
    
    elements.append(Paragraph("• SSH to your remote server and navigate to desired directory.", body_style))
    elements.append(Paragraph("• Use the same <font face=\"Courier\">wget</font> commands as above to download directly to the remote filesystem.", body_style))
    elements.append(Paragraph("• For faster transfers, consider using <font face=\"Courier\">parallel wget</font> or <font face=\"Courier\">aria2</font> for large datasets.", body_style))
    elements.append(Spacer(1, 0.2*inch))
    
    # Method 4: Download Managers
    elements.append(Paragraph("📥 Download Managers", heading_style))
    elements.append(Paragraph("<i>For resumable/multi-threaded downloads</i>", body_style))
    elements.append(Spacer(1, 0.1*inch))
    
    elements.append(Paragraph("• <b>Windows:</b> VisualWget, Internet Download Manager (IDM)", body_style))
    elements.append(Paragraph("• <b>macOS:</b> iGetter, Downie", body_style))
    elements.append(Paragraph("• <b>Cross-platform:</b> aria2, axel", body_style))
    elements.append(Spacer(1, 0.3*inch))
    
    # Add note about verifying integrity
    elements.append(Paragraph("Verifying File Integrity", heading_style))
    verify_text = """After downloading your files, it is strongly recommended to verify their integrity using the 
    md5 checksums provided in the md5sums.txt file. This ensures that your files were downloaded correctly 
    without corruption."""
    elements.append(Paragraph(verify_text, body_style))
    elements.append(Spacer(1, 0.1*inch))
    
    verify_cmd = """On Linux/macOS/WSL, you can verify checksums with:"""
    elements.append(Paragraph(verify_cmd, body_style))
    
    md5_cmd = '<font face="Courier" color="#f7fafc">md5sum -c md5sums.txt</font>'
    elements.append(Paragraph(md5_cmd, code_style))
    elements.append(Spacer(1, 0.3*inch))
    
    # Add support footer
    footer_text = """<b>Need Help?</b><br/>
    If you encounter any issues downloading your data, please contact the GRTHub support team."""
    elements.append(Paragraph(footer_text, body_style))
    
    # Build PDF
    doc.build(elements)
    print(f"Generated download instructions PDF: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        output_path = sys.argv[1]
    else:
        output_path = "Download_Instructions.pdf"
    
    generate_download_instructions_pdf(output_path)
