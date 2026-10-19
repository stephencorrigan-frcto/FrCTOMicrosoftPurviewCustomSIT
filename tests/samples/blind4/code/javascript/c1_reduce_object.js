const bySymbol = trades.reduce((acc, t) => {
  (acc[t.symbol] ||= []).push(t);
  return acc;
}, {});