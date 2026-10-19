using System;
using System.Collections.Generic;
using System.Linq;

namespace Contoso.Pricing
{
    public class TradeBook
    {
        private readonly List<Trade> _trades = new List<Trade>();
        public string Desk { get; set; }

        public decimal Total()
        {
            return _trades.Where(t => t.Qty > 0).Sum(t => t.Qty * t.Price);
        }
    }
}