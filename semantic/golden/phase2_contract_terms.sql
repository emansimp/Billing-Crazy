-- Contract terms: coverage and the amendment sanity checks. Expected values come from the PDFs / START_HERE, recomputed independently.
select test_name, expected, actual, (expected = actual) as pass from (
  select 'documents covered (register = 32)' as test_name, '32' as expected, (select count(distinct source_document_id) from ref.contract_term_versions)::text as actual
  union all select 'order-form versions', '30', (select count(*) from ref.contract_term_versions where version_type = 'original')::text
  union all select 'amendment versions', '2', (select count(*) from ref.contract_term_versions where version_type = 'amendment')::text
  union all select 'versions without a citation', '0', (select count(*) from ref.contract_term_versions where coalesce(source_citation, '') = '')::text
  union all select 'versions failing a register/arithmetic check', '0', (select count(*) from ref.contract_term_versions where status = 'needs_info')::text
  union all select 'unresolved needs_info fee items', '0', (select count(*) from ref.contract_term_fees where status = 'needs_info')::text
  union all select 'Meridian catch-up owner decision', 'treat_as_required', (select owner_decision from ref.contract_term_fees where kind = 'october_upgrade_catch_up')
  union all select 'sanity checks failing', '0', (select count(*) from ref.v_contract_sanity_checks where expected <> actual)::text
  union all select 'Meridian annual fee v1 -> v2', '48000.00 -> 60000.00', (select string_agg(platform_fee_annual::text, ' -> ' order by version_no) from ref.contract_term_versions where base_document_id = 'OF-2026-164')
  union all select 'Cedar Harbor allowance v1 -> v2', '30000 -> 45000', (select string_agg(included_runs_per_month::text, ' -> ' order by version_no) from ref.contract_term_versions where base_document_id = 'OF-2026-157')
  union all select 'version intervals contiguous (v1 end = v2 start)', '2', (select count(*) from ref.contract_term_versions a join ref.contract_term_versions b on b.base_document_id = a.base_document_id and a.version_no = 1 and b.version_no = 2 and a.effective_to_exclusive = b.effective_from)::text
  union all select 'approved versions (owner approval recorded)', '32', (select count(*) from ref.contract_term_versions where approval_status = 'approved')::text
) t;
