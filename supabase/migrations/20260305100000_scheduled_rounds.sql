-- Add scheduled_at column to rounds for scheduling future rounds
ALTER TABLE rounds ADD COLUMN scheduled_at TIMESTAMPTZ NULL;

-- Add 'scheduled' status option
-- (status is text, no enum constraint to update)
COMMENT ON COLUMN rounds.scheduled_at IS 'When set, the round is scheduled for a future date/time. Status should be scheduled until play begins.';
