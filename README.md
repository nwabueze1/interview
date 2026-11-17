# Support Inbox

In-memory support inbox for this interview. It is not a production app and does not run a web server.

`SupportInbox` stores tickets on a `Company` and records side effects as `BackgroundJob` records. Ticket ids come from a counter that starts at `1` on each inbox.

## Models

**Company** holds an id, a `public_inbox_enabled` flag, a ticket list, a notification list, and a background-job list. New companies start with public inbox enabled. The notification list is never written by these methods. Jobs go on `background_jobs`.

**Ticket** starts as `open`. It keeps the company id, subject, and optional screenshot key. Priority starts as `nil` and is set when an agent starts work.

**BackgroundJob** stores a notification name (`work_started` or `resolved`), the company id, and the ticket id.

## Methods

### `create_ticket`

Public form submission. Creates an open ticket and appends it to `company.tickets`.

Raises `"rejected"` when any of these are true:

- `public_key_company_id` does not equal `company.id`
- `company.public_inbox_enabled` is false
- `subject` is blank after stripping
- `screenshot_key` is blank after stripping

A missing screenshot key is blank, so a ticket needs both a subject and a screenshot key.

### `start_work`

Agent starts work on an existing ticket. Sets `priority` to the given value and `status` to `"inprogress"`. Ticket id and `screenshot_key` stay as they were. Appends one `work_started` job.

Raises `"rejected"` when:

- `staff_company_id` does not equal `company.id`
- the ticket exists and its status is already `"resolved"`

Calling this again on a ticket that is still open or in progress adds another `work_started` job. A missing ticket id is not rejected here. The method then calls methods on `nil`.

### `resolution_webhook`

Marks a ticket resolved from a webhook. Idempotent on `event_id` for this inbox instance.

If `event_id` was already handled, the method returns and does nothing. The same event id is ignored even when it names a different ticket or company.

Otherwise it finds the ticket on that company. A missing ticket raises `"rejected"` and the event id is not stored, so a later call with the same id can still succeed.

On the first successful call it stores the event id, sets status to `"resolved"`, and appends one `resolved` job. A later `start_work` on that ticket is rejected.

## Run the script

```bash
ruby support_inbox.rb
```

The bottom of the file runs only when the file is executed directly. It creates a ticket, starts work, delivers the same resolution event four times, then tries to start work again on the resolved ticket.
