IEnumerable<int> Evens(int max)
{
    for (int i = 0; i <= max; i += 2) yield return i;
}