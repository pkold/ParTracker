-- Allow friends to read rounds marked as visible_to_friends
CREATE POLICY "rounds_select_friends_visible" ON rounds
  FOR SELECT TO authenticated
  USING (
    visible_to_friends = true
    AND EXISTS (
      SELECT 1 FROM friendships f
      WHERE f.status = 'accepted'
        AND (
          (f.requester_id = auth.uid() AND f.addressee_id = rounds.created_by)
          OR (f.addressee_id = auth.uid() AND f.requester_id = rounds.created_by)
        )
    )
  );
