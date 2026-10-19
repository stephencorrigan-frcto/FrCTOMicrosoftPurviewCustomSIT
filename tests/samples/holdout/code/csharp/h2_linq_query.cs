var big = from t in trades
          where t.Qty > 1000
          orderby t.Price descending
          select new { t.Symbol, t.Qty };