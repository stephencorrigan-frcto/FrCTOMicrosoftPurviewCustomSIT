MERGE dbo.Positions AS tgt
USING staging.Positions AS src ON tgt.Symbol = src.Symbol
WHEN MATCHED THEN UPDATE SET tgt.Qty = src.Qty
WHEN NOT MATCHED THEN INSERT (Symbol, Qty) VALUES (src.Symbol, src.Qty);