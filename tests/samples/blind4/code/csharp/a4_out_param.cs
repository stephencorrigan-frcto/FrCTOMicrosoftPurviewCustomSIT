if (int.TryParse(input, out var qty) && qty > 0)
    orders.Add(new Order(sym, qty));