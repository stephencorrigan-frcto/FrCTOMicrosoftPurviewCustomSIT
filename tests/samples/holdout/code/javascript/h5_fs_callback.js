fs.readFile("trades.csv", "utf8", (err, data) => {
  if (err) throw err;
  const lines = data.split("\n");
  console.log(lines.length);
});