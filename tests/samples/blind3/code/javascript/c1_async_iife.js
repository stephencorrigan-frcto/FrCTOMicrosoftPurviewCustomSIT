(async () => {
  const res = await fetch("/api/positions");
  const json = await res.json();
  render(json);
})();