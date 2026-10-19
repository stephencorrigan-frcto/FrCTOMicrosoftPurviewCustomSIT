INSERT INTO archive.Trades (TradeId, Symbol)
SELECT TradeId, Symbol FROM dbo.Trades WHERE TradeDate < '2025-01-01';