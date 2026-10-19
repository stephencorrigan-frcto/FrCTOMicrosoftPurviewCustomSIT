SELECT a.AccountId FROM dbo.Accounts a
WHERE NOT EXISTS (SELECT 1 FROM dbo.Trades t WHERE t.AccountId = a.AccountId);