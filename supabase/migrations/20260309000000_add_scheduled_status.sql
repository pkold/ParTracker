-- Add 'scheduled' to rounds status check constraint
ALTER TABLE rounds DROP CONSTRAINT IF EXISTS rounds_status_check;
ALTER TABLE rounds ADD CONSTRAINT rounds_status_check
  CHECK (status IN ('setup', 'active', 'completed', 'cancelled', 'scheduled'));
