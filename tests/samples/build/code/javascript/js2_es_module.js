import { useState, useEffect } from "react";

export default function PriceTable({ symbol }) {
  const [rows, setRows] = useState([]);
  useEffect(() => {
    fetch(`/api/prices/${symbol}`).then((r) => r.json()).then(setRows);
  }, [symbol]);
  return rows.length;
}