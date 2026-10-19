const express = require("express");
const app = express();

app.get("/prices", async (req, res) => {
  const rows = await db.query("select * from prices");
  res.json(rows);
});

module.exports = app;