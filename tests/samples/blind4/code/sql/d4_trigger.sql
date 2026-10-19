CREATE TRIGGER trg_Trades_Audit ON dbo.Trades AFTER UPDATE AS
INSERT INTO dbo.TradeAudit (TradeId) SELECT TradeId FROM inserted;