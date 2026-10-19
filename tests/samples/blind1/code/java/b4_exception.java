} catch (SQLException e) {
    throw new IllegalStateException("db failure", e);
} finally {
    conn.close();
}