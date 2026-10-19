var sb = new StringBuilder();
sb.AppendLine("Symbol,Qty");
File.WriteAllText(path, sb.ToString());