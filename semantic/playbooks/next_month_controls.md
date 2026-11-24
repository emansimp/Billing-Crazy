# Playbook: next-month controls
Run before each close; every control is a view that records a result per customer.
1. Amendment load check: any signed amendment with blank `billing_loaded_at` (`amendment_not_loaded`).
2. Expected vs billed by customer, platform and usage separately (`platform_variance`, `usage_variance`) - not totals vs last month.
3. Invoice existence: overage with no invoice is an error; no overage and no invoice is valid (`missing_usage_invoice`).
4. Rate and quantity vs contract on every usage line (diagnosis in `usage_variance`).
5. Usage control reconciliation by date after dedup (`stg.v_usage_batch_reconciliation`).
6. Unverified-usage queue with an owner and due date (`unassigned_usage`).
7. Accrual vs contract before close (`calc.usage_accrual_comparison`) so billing corrections and accounting adjustments are decided separately.
8. Later-service invoices (`later_service_platform`) as follow-ups.
