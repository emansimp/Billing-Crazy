-- 0021: recommended-action text in the mockup's wording, owner line, and related items for the Finding detail page.
create view public.ui_finding_action as
select l.finding_id,
       case
         when l.check_code = 'usage_variance' and l.direction_label = 'Over-billed' then
           'Issue a linked credit note for $' || to_char(l.amount, 'FM999,990.00') || ' against ' || coalesce(bu.invoice_numbers[1], 'the October usage invoice') || ' with a November issue date. The finalized invoice is not edited.'
         when l.check_code = 'usage_variance' then
           'Issue a supplemental usage invoice for $' || to_char(l.amount, 'FM999,990.00') || ' for October service with a November issue date. The finalized invoices are not edited.'
         when l.check_code = 'platform_variance' then
           'Issue a supplemental invoice for the $' || to_char(l.amount, 'FM999,990.00') || ' October upgrade catch-up with a November issue date, and recognize the October true-up.'
         else f.recommended_action end as action_text,
       'Owner: ' || l.owner || ' · Approval: ' || case when f.approver like 'n/a%' then 'not required' else 'Controller' end ||
         case when exists (select 1 from raw.contract_register r where r.salesforce_account_id = l.salesforce_account_id and r.document_type = 'amendment' and r.billing_loaded_at is null)
                   and l.check_code in ('usage_variance', 'platform_variance')
              then ' · Also load the signed amendment in the billing system before the next invoice run' else '' end as owner_line,
       bu.invoice_numbers[1] as related_invoice
from public.ui_findings_list l join calc.v_findings f using (finding_id) left join calc.v_billed_usage bu on bu.salesforce_account_id = l.salesforce_account_id and l.stream = 'usage';
grant select on public.ui_finding_action to anon, authenticated;
