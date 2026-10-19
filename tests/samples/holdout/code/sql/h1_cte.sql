WITH recent AS (
    SELECT Symbol, Price, ROW_NUMBER() OVER (PARTITION BY Symbol ORDER BY PriceTime DESC) AS rn
    FROM dbo.Prices
)
SELECT Symbol, Price FROM recent WHERE rn = 1;