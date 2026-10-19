private void btnLoad_Click(object sender, EventArgs e)
{
    dataGridView1.DataSource = _repo.GetAll().ToList();
    MessageBox.Show("Loaded");
}