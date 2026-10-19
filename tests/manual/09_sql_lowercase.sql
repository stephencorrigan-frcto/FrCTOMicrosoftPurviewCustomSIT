select symbol, count(*) as trades
from trades
where trade_date > '2026-09-01'
group by symbol
order by trades desc;