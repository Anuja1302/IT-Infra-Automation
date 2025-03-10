import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import os
import sys
import json
import datetime

with open('config/config.json', 'r') as config_file:
            config = json.load(config_file)


def send_email(ticket_number, email_address):
    # Email configuration
    smtp_server = config["smtp_server"]
    smtp_port = 587  # or your SMTP port
    smtp_username = config["smtp_username"]
    smtp_password = config["smtp_password"]
    sender_email = config["from_address"]

    # Create message container
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = email_address
    msg['Subject'] = 'Your ServiceNow Ticket Number'

    # Compose the message (plain-text version)
    text = f"{ticket_number}"
    msg.attach(MIMEText(text, 'plain'))

    # Create SMTP session
    server = smtplib.SMTP(smtp_server, smtp_port)
    server.starttls()
    server.login(smtp_username, smtp_password)

    # Send email
    server.sendmail(sender_email, email_address, msg.as_string())
    server.quit()



#send_email(ticket_number, email_address)
'''
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

def send_email(ticket_number, email_address):
    sender_email = config["from_address"]
    receiver_email = email_address  # Use the provided email address
    smtp_server = config["smtp_server"]
    smtp_port = config["smtp_port"]
    subject = "Your ServiceNow Ticket Number"
    body = f"{ticket_number}"
    
    # Create the email object
    message = MIMEMultipart()
    message["From"] = sender_email
    message["To"] = receiver_email
    message["Subject"] = subject
    # Add the body of the email
    message.attach(MIMEText(body, "plain"))
    # Connect to the SMTP server and send the email
    with smtplib.SMTP(smtp_server, smtp_port) as server:
        server.send_message(message)

'''
