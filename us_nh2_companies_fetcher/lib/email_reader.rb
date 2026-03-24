require 'net/imap'

def email_reader(email, password)
  imap = Net::IMAP.new(IMAP_SERVER, IMAP_PORT, IMAP_SSL)
  imap.login(email, password)
  sleep(5)
  imap.select('INBOX')
  emails = imap.search(['FROM', 'quickstart@sos.nh.gov'])
  if emails.empty?
    puts "No emails found from quickstart@sos.nh.gov"
  else
    envelopes = imap.fetch(emails, "ENVELOPE")

    # Map message IDs to their parsed dates
    email_dates = envelopes.map do |fetch_data|
      message_id = fetch_data.seqno
      envelope = fetch_data.attr["ENVELOPE"]
      [message_id, Time.parse(envelope.date).to_datetime]
    end
    # Sort by date
    sorted_emails = email_dates.sort_by { |_, date| date }
    latest_email_id = sorted_emails.last[0]
    envelope = imap.fetch(latest_email_id, "ENVELOPE")[0].attr["ENVELOPE"]
    body = imap.fetch(latest_email_id, "BODY[TEXT]")[0].attr["BODY[TEXT]"]

    # Print email details
    puts "From: #{envelope.from[0].name} <#{envelope.from[0].mailbox}@#{envelope.from[0].host}>"
    puts "Subject: #{envelope.subject}"
    puts "Date: #{envelope.date}"
    puts "---------------------------------"
    sleep(0.5)
    auth_code = extract_auth_code(body)
    puts "Authentication Code: #{auth_code}" if auth_code
    puts "---------------------------------"
    imap.logout
    imap.disconnect
  end
  auth_code
end
  
def extract_auth_code(body)
  match = body.match(/\b\d{6}\b/)
  match ? match[0] : nil
end
