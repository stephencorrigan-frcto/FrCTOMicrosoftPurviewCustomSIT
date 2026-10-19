public async Task<List<string>> LoadSymbolsAsync(string path)
{
    var lines = await File.ReadAllLinesAsync(path);
    var result = new List<string>();
    foreach (var line in lines)
    {
        if (!string.IsNullOrWhiteSpace(line)) result.Add(line.Trim());
    }
    return result;
}