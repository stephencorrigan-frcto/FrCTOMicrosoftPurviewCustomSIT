const results = await Promise.all(symbols.map((s) => getQuote(s)));
results.forEach((q) => cache.set(q.symbol, q));