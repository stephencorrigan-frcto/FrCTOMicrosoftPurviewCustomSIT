  const total = items
    .filter((i) => i.qty > 0)
    .map((i) => i.qty * i.price)
    .reduce((a, b) => a + b, 0);
  console.log("total", total);