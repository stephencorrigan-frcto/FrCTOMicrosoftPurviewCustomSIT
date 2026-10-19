SELECT Symbol, TradeDate, SUM(Qty) OVER (PARTITION BY Symbol ORDER BY TradeDate) AS RunningQty
FROM dbo.Trades;