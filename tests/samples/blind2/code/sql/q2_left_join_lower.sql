select c.client_name, max(t.trade_date) as last_trade
from clients c
left join trades t on t.client_id = c.id
group by c.client_name;