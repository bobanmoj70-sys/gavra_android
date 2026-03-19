-- ===================================================================
-- TEST SCRIPT za v3_gps_raspored tabelu
-- ===================================================================

-- Test 1: Insert test data
INSERT INTO public.v3_gps_raspored (
  vozac_id,
  putnik_id, 
  datum,
  grad,
  vreme,
  nav_bar_type,
  aktivno,
  created_by
) VALUES 
-- BC 07:00 - Vozač 1 sa 3 putnika
('07d52635-570d-48c3-a597-afddc7c1ec60', 
 (SELECT id FROM v3_putnici LIMIT 1), 
 CURRENT_DATE + 1, 'BC', '07:00', 'zimski', true, 'test'),
('07d52635-570d-48c3-a597-afddc7c1ec60', 
 (SELECT id FROM v3_putnici OFFSET 1 LIMIT 1), 
 CURRENT_DATE + 1, 'BC', '07:00', 'zimski', true, 'test'),
('07d52635-570d-48c3-a597-afddc7c1ec60', 
 (SELECT id FROM v3_putnici OFFSET 2 LIMIT 1), 
 CURRENT_DATE + 1, 'BC', '07:00', 'zimski', true, 'test'),

-- BC 07:00 - Vozač 2 sa 2 putnika
('9d4d9cbd-b1cc-4347-ab09-4439555315d9', 
 (SELECT id FROM v3_putnici OFFSET 3 LIMIT 1), 
 CURRENT_DATE + 1, 'BC', '07:00', 'zimski', true, 'test'),
('9d4d9cbd-b1cc-4347-ab09-4439555315d9', 
 (SELECT id FROM v3_putnici OFFSET 4 LIMIT 1), 
 CURRENT_DATE + 1, 'BC', '07:00', 'zimski', true, 'test');

-- Test 2: Verify trigger computed polazak_vreme and activation_time
SELECT 
  vozac_id,
  datum,
  vreme, 
  polazak_vreme,
  activation_time,
  polazak_vreme - (datum + vreme) as polazak_diff_should_be_zero,
  (datum + vreme) - activation_time as activation_diff_should_be_15min
FROM v3_gps_raspored 
WHERE created_by = 'test';

-- Test 3: Test GPS function GROUP BY logic
SELECT 
  vozac_id,
  grad,
  vreme,
  COUNT(*) as putnici_count,
  MIN(polazak_vreme) as polazak_vreme,
  MIN(activation_time) as activation_time
FROM v3_gps_raspored 
WHERE datum = CURRENT_DATE + 1 
  AND nav_bar_type = 'zimski'
  AND aktivno = true
GROUP BY vozac_id, grad, vreme
ORDER BY vreme, grad, vozac_id;

-- Test 4: Test new GPS function
SELECT public.fn_v3_populate_gps_activation_schedule_v2();

-- Test 5: Verify GPS activation schedule populated correctly
SELECT 
  vozac_id,
  datum,
  grad, 
  vreme,
  putnici_count,
  status,
  polazak_vreme,
  activation_time
FROM v3_gps_activation_schedule 
WHERE datum = CURRENT_DATE + 1
ORDER BY vreme, grad, vozac_id;

-- Test 6: Test constraint - unique putnik per termin
-- This should FAIL (good!)
/*
INSERT INTO public.v3_gps_raspored (
  vozac_id,
  putnik_id, 
  datum,
  grad,
  vreme,
  nav_bar_type
) VALUES 
('bc0f945f-a8ab-41d7-b611-ae4600082ef0', 
 (SELECT id FROM v3_putnici LIMIT 1), -- SAME putnik as test data
 CURRENT_DATE + 1, 'BC', '07:00', 'zimski');
*/

-- Test 7: Test invalid nav_bar_type/vreme combination
-- This should FAIL (good!)
/*
INSERT INTO public.v3_gps_raspored (
  vozac_id,
  putnik_id, 
  datum,
  grad,
  vreme,
  nav_bar_type
) VALUES 
('bc0f945f-a8ab-41d7-b611-ae4600082ef0', 
 (SELECT id FROM v3_putnici OFFSET 10 LIMIT 1),
 CURRENT_DATE + 1, 'BC', '09:00', 'praznici'); -- Invalid time for praznici
*/

-- Test 8: Performance test - index usage
EXPLAIN (ANALYZE, BUFFERS) 
SELECT vozac_id, COUNT(*) 
FROM v3_gps_raspored 
WHERE datum >= CURRENT_DATE 
  AND nav_bar_type = 'zimski' 
  AND aktivno = true 
GROUP BY vozac_id, datum, grad, vreme;

-- Cleanup test data
-- DELETE FROM v3_gps_raspored WHERE created_by = 'test';
-- DELETE FROM v3_gps_activation_schedule WHERE datum = CURRENT_DATE + 1;