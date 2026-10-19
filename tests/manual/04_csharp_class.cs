using System;
using System.Collections.Generic;
using System.Linq;

namespace Contoso.Test
{
    public class TradeBook
    {
        private readonly List<Trade> _trades = new List<Trade>();

        public decimal Total()
        {
            return _trades.Where(t => t.Qty > 0).Sum(t => t.Qty * t.Price);
        }
    }
}