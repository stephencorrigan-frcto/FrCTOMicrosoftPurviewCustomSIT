var totals = new Dictionary<string, decimal>();
foreach (var kv in totals.OrderByDescending(x => x.Value))
    Console.WriteLine($"{kv.Key}: {kv.Value}");