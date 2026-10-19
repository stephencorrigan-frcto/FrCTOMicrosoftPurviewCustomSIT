const express = require("express");
const app = express();

function calculateTotal(items) {
  let total = 0;
  for (const item of items) {
    if (item.price > 0) {
      total += item.price;
    }
  }
  return total;
}

app.get("/total", (req, res) => {
  res.json({ total: calculateTotal(req.body.items) });
});