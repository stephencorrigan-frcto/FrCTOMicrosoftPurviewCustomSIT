PreparedStatement ps = conn.prepareStatement("SELECT qty FROM trades WHERE id = ?");
ps.setLong(1, id);
ResultSet rs = ps.executeQuery();