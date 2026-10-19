        var total = 0m;
        foreach (var t in trades)
        {
            if (t.Qty > 0)
            {
                total += t.Qty * t.Price;
            }
        }
        Console.WriteLine($"Total: {total}");