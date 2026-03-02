-- Dodaje created_at kolonu i CHECK constraint za grad na v2_adrese tabelu

-- Dodaj created_at sa default vrijednošću (NULL za postojeće redove je ok)
ALTER TABLE public.v2_adrese
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- CHECK constraint: grad smije biti samo 'BC', 'VS' ili NULL
ALTER TABLE public.v2_adrese
  DROP CONSTRAINT IF EXISTS v2_adrese_grad_check;

ALTER TABLE public.v2_adrese
  ADD CONSTRAINT v2_adrese_grad_check CHECK (grad IN ('BC', 'VS'));

COMMENT ON COLUMN public.v2_adrese.created_at IS 'Timestamp kada je adresa kreirana';
COMMENT ON CONSTRAINT v2_adrese_grad_check ON public.v2_adrese IS 'Dozvoljeni gradovi: BC (Bela Crkva), VS (Vrsac)';
