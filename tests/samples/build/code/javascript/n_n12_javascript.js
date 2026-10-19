function total(items) {
  let t = 0;
  for (const i of items) { t += i.price; }
  return t;
}