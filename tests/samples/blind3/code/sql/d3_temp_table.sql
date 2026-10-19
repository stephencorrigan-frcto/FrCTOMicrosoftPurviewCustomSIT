SELECT Symbol, SUM(Qty) AS Qty INTO #totals FROM dbo.Trades GROUP BY Symbol;
DROP TABLE #totals;