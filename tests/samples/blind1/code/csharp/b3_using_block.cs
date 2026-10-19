using (var conn = new SqlConnection(_cs))
{
    conn.Open();
    var cmd = new SqlCommand("SELECT 1", conn);
    var n = (int)cmd.ExecuteScalar();
}