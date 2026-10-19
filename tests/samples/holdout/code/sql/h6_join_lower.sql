select a.name, sum(t.qty) as total_qty
from accounts a
join trades t on t.account_id = a.id
group by a.name;