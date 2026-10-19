const express = require("express");
const app = express();

app.get("/prices", async (req, res) => {
  const rows = await db.query("select * from prices");
  res.json(rows.filter((r) => r.active === true));
});

module.exports = app;