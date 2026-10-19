emitter.on("price", function (p) {
  if (p.change > 0.05) alert("Big move: " + p.symbol);
});