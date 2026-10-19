SELECT Symbol FROM dbo.Equities
UNION ALL
SELECT Symbol FROM dbo.Bonds;