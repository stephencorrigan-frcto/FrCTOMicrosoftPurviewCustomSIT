SELECT * FROM (SELECT Desk, Month, Pnl FROM dbo.Pnl) src
PIVOT (SUM(Pnl) FOR Month IN ([Jan], [Feb], [Mar])) p;