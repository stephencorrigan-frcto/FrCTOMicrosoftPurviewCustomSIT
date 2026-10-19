if (msg is TradeMessage { Qty: > 0 } tm)
{
    _queue.Enqueue(tm);
}