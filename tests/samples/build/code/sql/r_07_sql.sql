SELECT t.TradeId, t.Symbol, SUM(t.Quantity) AS Qty
FROM dbo.Trades t
INNER JOIN dbo.Accounts a ON a.AccountId = t.AccountId
WHERE t.TradeDate >= '2026-01-01'
GROUP BY t.TradeId, t.Symbol
ORDER BY Qty DESC;