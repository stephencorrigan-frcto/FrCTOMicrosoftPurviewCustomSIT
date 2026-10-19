const Row = ({ trade }) => (
  <tr>
    <td>{trade.symbol}</td>
    <td>{trade.qty}</td>
  </tr>
);
export default Row;