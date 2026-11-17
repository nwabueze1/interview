require "cgi"
require "socket"
require "uri"
require_relative "support_inbox"

company = Company.new(id: 1)
inbox = SupportInbox.new

def h(value)
  CGI.escapeHTML(value.to_s)
end

def page(company, notice)
  ticket_rows = company.tickets.map do |ticket|
    priority = ticket.priority || "—"
    <<~ROW
      <tr>
        <td>#{h(ticket.id)}</td>
        <td>#{h(ticket.subject)}</td>
        <td>#{h(ticket.screenshot_key)}</td>
        <td>#{h(ticket.status)}</td>
        <td>#{h(priority)}</td>
      </tr>
    ROW
  end.join
  ticket_rows = "<tr><td colspan=\"5\">No tickets yet.</td></tr>" if ticket_rows.empty?

  job_rows = company.background_jobs.map do |job|
    <<~ROW
      <li>#{h(job.notification)} for ticket #{h(job.ticket_id)}</li>
    ROW
  end.join
  job_rows = "<li>No background jobs yet.</li>" if job_rows.empty?

  notice_html = notice.to_s.empty? ? "" : "<p class=\"notice\">#{h(notice)}</p>"
  inbox_checked = company.public_inbox_enabled ? "checked" : ""

  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Support inbox</title>
      <style>
        * { box-sizing: border-box; }
        body { margin: 0; font-family: Georgia, "Iowan Old Style", serif; background: #f6f7f8; color: #1c2430; }
        main { max-width: 980px; margin: 0 auto; padding: 32px 20px 64px; }
        h1 { font-size: 32px; font-weight: 500; margin: 0 0 8px; }
        h2 { font-size: 18px; font-weight: 500; margin: 0 0 12px; }
        p { line-height: 1.45; }
        .notice { background: #e7eef2; padding: 10px 12px; margin: 16px 0; }
        form { display: grid; gap: 8px; margin: 0; }
        label { display: grid; gap: 4px; font-size: 14px; }
        input, select, button { font: inherit; font-size: 15px; }
        input, select { border: 1px solid #c5ced6; background: #fff; padding: 8px 10px; }
        button { border: 0; background: #1f4b5a; color: #fff; padding: 9px 12px; cursor: pointer; }
        button:focus, input:focus, select:focus { outline: 2px solid #1f4b5a; outline-offset: 2px; }
        .layout { display: grid; grid-template-columns: 1.4fr 0.8fr; gap: 28px; align-items: start; }
        .panel { background: #fff; border: 1px solid #d5dde3; padding: 16px; margin-bottom: 16px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid #e4eaee; font-size: 15px; }
        ul { margin: 0; padding-left: 18px; }
        .company { display: flex; gap: 12px; align-items: end; flex-wrap: wrap; }
        .check { display: flex; gap: 8px; align-items: center; }
        @media (max-width: 800px) { .layout { grid-template-columns: 1fr; } }
      </style>
    </head>
    <body>
      <main>
        <h1>Support inbox</h1>
        <p>Company #{h(company.id)}. Tickets and jobs come from the in-memory inbox.</p>
        #{notice_html}
        <section class="panel">
          <h2>Company</h2>
          <form class="company" method="post" action="/company">
            <label>Company id
              <input name="company_id" type="number" value="#{h(company.id)}" required>
            </label>
            <label class="check">
              <input name="public_inbox_enabled" type="checkbox" value="1" #{inbox_checked}>
              Public inbox enabled
            </label>
            <button type="submit">Save company</button>
          </form>
        </section>
        <div class="layout">
          <section>
            <div class="panel">
              <h2>Tickets</h2>
              <table>
                <thead>
                  <tr><th>Id</th><th>Subject</th><th>Screenshot</th><th>Status</th><th>Priority</th></tr>
                </thead>
                <tbody>#{ticket_rows}</tbody>
              </table>
            </div>
            <div class="panel">
              <h2>Background jobs</h2>
              <ul>#{job_rows}</ul>
            </div>
          </section>
          <section>
            <div class="panel">
              <h2>Create ticket</h2>
              <form method="post" action="/tickets">
                <label>Public key company id
                  <input name="public_key_company_id" type="number" value="#{h(company.id)}" required>
                </label>
                <label>Subject
                  <input name="subject" type="text" required>
                </label>
                <label>Screenshot key
                  <input name="screenshot_key" type="text" required>
                </label>
                <button type="submit">Create ticket</button>
              </form>
            </div>
            <div class="panel">
              <h2>Start work</h2>
              <form method="post" action="/work">
                <label>Staff company id
                  <input name="staff_company_id" type="number" value="#{h(company.id)}" required>
                </label>
                <label>Ticket id
                  <input name="ticket_id" type="number" required>
                </label>
                <label>Priority
                  <select name="priority">
                    <option value="low">low</option>
                    <option value="normal">normal</option>
                    <option value="high" selected>high</option>
                  </select>
                </label>
                <button type="submit">Start work</button>
              </form>
            </div>
            <div class="panel">
              <h2>Resolution webhook</h2>
              <form method="post" action="/resolve">
                <label>Event id
                  <input name="event_id" type="text" value="evt_1" required>
                </label>
                <label>Ticket id
                  <input name="ticket_id" type="number" required>
                </label>
                <button type="submit">Mark resolved</button>
              </form>
            </div>
          </section>
        </div>
      </main>
    </body>
    </html>
  HTML
end

def integer_param(params, key)
  Integer(params[key])
rescue ArgumentError, TypeError
  nil
end

def form_params(request_target, body)
  query = URI.parse(request_target).query
  raw = [query, body].compact.reject(&:empty?).join("&")
  CGI.parse(raw).transform_values(&:first)
end

def write_response(client, status, body, location: nil)
  reason = status == 303 ? "See Other" : "OK"
  headers = [
    "HTTP/1.1 #{status} #{reason}",
    "Content-Type: text/html; charset=utf-8",
    "Content-Length: #{body.bytesize}",
    "Connection: close"
  ]
  headers << "Location: #{location}" if location
  client.write(headers.join("\r\n") + "\r\n\r\n" + body)
end

def handle_request(company, inbox, method, path, params)
  if method == "POST"
    case path
    when "/company"
      company_id = integer_param(params, "company_id")
      return [303, "", "Enter a company id."] if company_id.nil?

      company.id = company_id
      company.public_inbox_enabled = params["public_inbox_enabled"] == "1"
      return [303, "", "Company saved."]
    when "/tickets"
      public_key_company_id = integer_param(params, "public_key_company_id")
      return [303, "", "Enter the public key company id."] if public_key_company_id.nil?

      inbox.create_ticket(
        company: company,
        public_key_company_id: public_key_company_id,
        subject: params["subject"],
        screenshot_key: params["screenshot_key"]
      )
      return [303, "", "Ticket created."]
    when "/work"
      staff_company_id = integer_param(params, "staff_company_id")
      ticket_id = integer_param(params, "ticket_id")
      return [303, "", "Enter the staff company id and ticket id."] if staff_company_id.nil? || ticket_id.nil?

      inbox.start_work(
        company: company,
        staff_company_id: staff_company_id,
        ticket_id: ticket_id,
        priority: params["priority"]
      )
      return [303, "", "Work started."]
    when "/resolve"
      ticket_id = integer_param(params, "ticket_id")
      event_id = params["event_id"].to_s
      return [303, "", "Enter an event id and a ticket id."] if ticket_id.nil? || event_id.strip.empty?

      jobs_before = company.background_jobs.length
      result = inbox.resolution_webhook(company: company, event_id: event_id, ticket_id: ticket_id)
      already_handled = result.nil? && company.background_jobs.length == jobs_before
      notice = already_handled ? "This event was already handled." : "Ticket resolved."
      return [303, "", notice]
    end
  end

  [200, page(company, params["notice"]), nil]
rescue RuntimeError => error
  notice = error.message == "rejected" ? "Rejected." : error.message
  [303, "", notice]
rescue NoMethodError
  [303, "", "Rejected. That ticket does not exist."]
end

server = TCPServer.new("127.0.0.1", 4567)
puts "Support inbox UI at http://127.0.0.1:4567"

loop do
  client = server.accept
  request = client.gets
  break if request.nil?

  method, target, _http = request.split(" ", 3)
  headers = {}
  while (line = client.gets)
    break if line == "\r\n"
    name, value = line.split(":", 2)
    headers[name.to_s.downcase] = value.to_s.strip
  end
  body_length = headers["content-length"].to_i
  body = body_length.positive? ? client.read(body_length) : ""
  path = URI.parse(target).path
  params = form_params(target, body)
  status, response_body, notice = handle_request(company, inbox, method, path, params)
  location = notice ? "/?notice=#{CGI.escape(notice)}" : nil
  write_response(client, status, response_body, location: location)
ensure
  client&.close
end
