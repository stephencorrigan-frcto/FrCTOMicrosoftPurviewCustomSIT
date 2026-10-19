CREATE VIEW dbo.OpenTrades AS
SELECT TradeId, Symbol, Qty FROM dbo.Trades WHERE Status = 'Open';