# In-memory support inbox for this interview. Not a production app.
# Implement the three methods on SupportInbox. Do not add a web server.

class Company
  attr_accessor :id, :public_inbox_enabled, :tickets, :notifications, :background_jobs
  def initialize(id:, public_inbox_enabled: true)
    @id = id
    @public_inbox_enabled = public_inbox_enabled
    @tickets = []
    @notifications = []
    @background_jobs = []
  end
end

class Ticket
  attr_accessor :id, :company_id, :status, :subject, :screenshot_key, :priority
  def initialize(id:, company_id:, subject:, screenshot_key: nil)
    @id = id
    @company_id = company_id
    @status = "open"
    @subject = subject
    @screenshot_key = screenshot_key
    @priority = nil
  end
end

class BackgroundJob
  attr_accessor :notification, :company_id, :ticket_id

  def initialize(notification:, company_id:, ticket_id:)
    @notification = notification
    @company_id = company_id
    @ticket_id = ticket_id
  end
end

class SupportInbox
  def initialize
    @next_ticket_id = 1
    @seen_events = {} # fill this in if you want
  end

  # 1. Public form. Reject if public_key_company_id != company.id or !public_inbox_enabled.
  def create_ticket(company:, public_key_company_id:, subject:, screenshot_key: nil)
    public_key_matches_company = public_key_company_id == company.id
    raise "rejected" unless public_key_matches_company

    public_inbox_is_enabled = company.public_inbox_enabled
    raise "rejected" unless public_inbox_is_enabled

    subject_is_blank = subject.to_s.strip.empty?
    screenshot_is_blank = screenshot_key.to_s.strip.empty?
    raise "rejected" if subject_is_blank || screenshot_is_blank

    ticket = Ticket.new(
      id: @next_ticket_id,
      company_id: company.id,
      subject: subject,
      screenshot_key: screenshot_key
    )
    @next_ticket_id += 1
    company.tickets << ticket
    ticket
  end

  # 2. Agent starts work. Preserve ticket id + screenshot_key. One work_started notification.
  def start_work(company:, staff_company_id:, ticket_id:, priority:)
    staff_belongs_to_company = staff_company_id == company.id
    raise "rejected" unless staff_belongs_to_company

    ticket = company.tickets.find { |stored_ticket| stored_ticket.id == ticket_id }
    ticket_is_resolved = ticket&.status == "resolved"
    raise "rejected" unless !ticket_is_resolved

    ticket.priority = priority
    ticket.status = "inprogress"
    company.background_jobs << BackgroundJob.new(
      notification: "work_started",
      company_id: company.id,
      ticket_id: ticket.id
    )
    ticket
  end

  # 3. Webhook. Idempotent on event_id. One resolved notification.
  def resolution_webhook(company:, event_id:, ticket_id:)
    webhook_already_handled = @seen_events.key?(event_id)
    return if webhook_already_handled

    ticket = company.tickets.find { |stored_ticket| stored_ticket.id == ticket_id }
    ticket_is_missing = ticket.nil?
    raise "rejected" if ticket_is_missing

    @seen_events[event_id] = true
    ticket.status = "resolved"
    company.background_jobs << BackgroundJob.new(
      notification: "resolved",
      company_id: company.id,
      ticket_id: ticket.id
    )
    ticket
  end
end

# Optional checks — uncomment as you go.
# company = Company.new(id: 1)
# inbox = SupportInbox.new
# ticket = inbox.create_ticket(company: company, public_key_company_id: 1, subject: "Login broken", screenshot_key: "img_1")
# inbox.start_work(company: company, staff_company_id: 1, ticket_id: ticket.id, priority: "high")
# raise "lost screenshot" unless company.tickets.first.screenshot_key == "img_1"
# 3.times { inbox.resolution_webhook(company: company, event_id: "evt_1", ticket_id: ticket.id) }
# raise "dup notify" unless company.background_jobs.count { |n| n.notification == "resolved" } == 1
# puts "ok"

if __FILE__ == $0
company = Company.new(id: 1)
inbox = SupportInbox.new
ticket = inbox.create_ticket(company: company, public_key_company_id: 1, subject: "Add to cart not working", screenshot_key: "img_url")

puts "before work start"
puts ticket.inspect
inbox.start_work(company: company, staff_company_id: 1, ticket_id: ticket.id, priority: "high")

puts ticket.inspect

inbox.resolution_webhook(company: company, event_id: "evt_1", ticket_id: ticket.id)
inbox.resolution_webhook(company: company, event_id: "evt_1", ticket_id: ticket.id)
inbox.resolution_webhook(company: company, event_id: "evt_1", ticket_id: ticket.id)
inbox.resolution_webhook(company: company, event_id: "evt_1", ticket_id: ticket.id)

puts "jobs after resolution webhook"
puts company.background_jobs.inspect
puts "tickets after resolution webhook"
puts company.tickets.inspect

inbox.start_work(company: company, staff_company_id: 1, ticket_id: ticket.id, priority: "high")
end