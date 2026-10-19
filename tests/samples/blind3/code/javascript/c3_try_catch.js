try {
  JSON.parse(raw);
} catch (e) {
  console.error("bad json", e);
}